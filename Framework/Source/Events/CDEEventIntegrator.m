//
//  CDEEventIntegrator.m
//  Test App iOS
//
//  Created by Drew McCormack on 4/23/13.
//  Copyright (c) 2013 The Mental Faculty B.V. All rights reserved.
//

#import "CDEEventIntegrator.h"
#import "NSMapTable+CDEAdditions.h"
#import "CDEEventBuilder.h"
#import "NSMapTable+CDEAdditions.h"
#import "CDEEventStore.h"
#import "CDEStoreModificationEvent.h"
#import "CDEObjectChange.h"
#import "CDEGlobalIdentifier.h"
#import "CDEEventRevision.h"
#import "CDERevisionSet.h"
#import "CDERevision.h"
#import "CDEPropertyChangeValue.h"
#import "CDERevisionManager.h"

@interface CDEEventIntegrator ()

@property (readwrite) NSManagedObjectContext *managedObjectContext;

@end

@implementation CDEEventIntegrator {
    CDECompletionBlock completion;
    NSManagedObjectContext *eventStoreChildContext;
    CDERevisionNumber fromRevisionNumber;
    NSDictionary *saveInfoDictionary;
    dispatch_queue_t queue;
    id eventStoreChildContextSaveObserver;
}

@synthesize storeURL = storeURL;
@synthesize managedObjectContext = managedObjectContext;
@synthesize managedObjectModel = managedObjectModel;
@synthesize eventStore = eventStore;
@synthesize willSaveBlock = willSaveBlock;
@synthesize didSaveBlock = didSaveBlock;
@synthesize failedSaveBlock = failedSaveBlock;


#pragma mark Initialization

- (instancetype)initWithStoreURL:(NSURL *)newStoreURL managedObjectModel:(NSManagedObjectModel *)model eventStore:(CDEEventStore *)newEventStore
{
    self = [super init];
    if (self) {
        storeURL = [newStoreURL copy];
        managedObjectModel = model;
        eventStore = newEventStore;
        willSaveBlock = NULL;
        didSaveBlock = NULL;
        failedSaveBlock = NULL;
        queue = dispatch_queue_create("com.mentalfaculty.ensembles.eventintegrator", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:eventStoreChildContextSaveObserver];
}


#pragma mark Completing

- (void)failWithError:(NSError *)error
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (completion) completion(error);
    });
}

- (void)completeSuccessfully
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (completion) completion(nil);
    });
}


#pragma mark Accessing Values

// Use this to avoid calling a custom accessor
- (id)valueForKey:(NSString *)key inObject:(id)object
{
    [object willAccessValueForKey:key];
    id related = [object primitiveValueForKey:key];
    [object didAccessValueForKey:key];
    return related;
}

- (void)setValue:(id)value forKey:(NSString *)key inObject:(id)object
{
    id currentValue = [self valueForKey:key inObject:object];
    if (value != currentValue && ![value isEqual:currentValue]) {
        [object willChangeValueForKey:key];
        [object setPrimitiveValue:value forKey:key];
        [object didChangeValueForKey:key];
    }
}


#pragma mark Merging Store Modification Events

- (void)mergeEventsImportedSinceRevision:(CDERevisionNumber)revision completion:(CDECompletionBlock)newCompletion
{
    NSAssert([NSThread isMainThread], @"mergeEvents... called off main thread");
    
    completion = [newCompletion copy];
    fromRevisionNumber = revision;
    
    // Setup child context of the event store
    eventStoreChildContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    [eventStoreChildContext performBlockAndWait:^{
        eventStoreChildContext.parentContext = eventStore.managedObjectContext;
        eventStoreChildContext.undoManager = nil;
    }];
    
    [[NSNotificationCenter defaultCenter] removeObserver:eventStoreChildContextSaveObserver];
    eventStoreChildContextSaveObserver = [[NSNotificationCenter defaultCenter] addObserverForName:NSManagedObjectContextDidSaveNotification object:eventStoreChildContext queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        [self.eventStore.managedObjectContext performBlockAndWait:^{
            [self.eventStore.managedObjectContext mergeChangesFromContextDidSaveNotification:note];
        }];
    }];
    
    // Setup a context for accessing the main store
    NSError *error;
    NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:managedObjectModel];
    NSPersistentStore *persistentStore = [coordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:nil error:&error];
    if (!persistentStore) {
        [self failWithError:error];
        return;
    }
    
    self.managedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    [self.managedObjectContext performBlockAndWait:^{
        self.managedObjectContext.persistentStoreCoordinator = coordinator;
        self.managedObjectContext.undoManager = nil;
    }];
    
    // Integrate on background queue
    dispatch_async(queue,^{
        @try {
            __block NSError *error;
            
            // Apply changes
            BOOL integrationSucceeded = [self integrate:&error];
            if (!integrationSucceeded) {
                [self failWithError:error];
                return;
            }
            
            // If no changes, complete
            __block BOOL hasChanges;
            [managedObjectContext performBlockAndWait:^{
                hasChanges = managedObjectContext.hasChanges;
            }];
            if (!hasChanges) {
                [self completeSuccessfully];
                return;
            }
            
            // Create a merge event
            CDEEventBuilder *eventBuilder = [[CDEEventBuilder alloc] initWithEventStore:self.eventStore eventManagedObjectContext:eventStoreChildContext];
            eventBuilder.ensemble = self.ensemble;
            [eventBuilder makeNewEventOfType:CDEStoreModificationEventTypeMerge];
            
            // Register event in case of crashes
            [self.eventStore registerIncompleteEventIdentifier:eventBuilder.event.uniqueIdentifier isMandatory:NO];
            
            // Repair inconsistencies caused by integration
            BOOL repairSucceeded = [self repairWithMergeEventBuilder:eventBuilder error:&error];
            if (!repairSucceeded) {
                [self failWithError:error];
                return;
            }
            
            // Commit (save) the changes
            BOOL commitSucceeded = [self commitWithMergeEventBuilder:eventBuilder error:&error];
            if (!commitSucceeded) {
                [self failWithError:error];
                return;
            }
            
            // Save changes in child event context. First save child, then parent.
            __block BOOL eventSaveSucceeded = YES;
            [eventStoreChildContext performBlockAndWait:^{
                hasChanges = eventStoreChildContext.hasChanges;
                if (hasChanges) eventSaveSucceeded = [eventStoreChildContext save:&error];
            }];
            if (!hasChanges) {
                [self completeSuccessfully];
                return;
            }
            if (!eventSaveSucceeded) {
                [self failWithError:error];
                return;
            }
            
            // Save parent event context
            [self.eventStore.managedObjectContext performBlockAndWait:^{
                eventSaveSucceeded = [self.eventStore.managedObjectContext save:&error];
            }];
            if (!eventSaveSucceeded) {
                [self failWithError:error];
                return;
            }
            
            // Deregister event
            [self.eventStore deregisterIncompleteEventIdentifier:eventBuilder.event.uniqueIdentifier];
            
            // Notify of save
            [managedObjectContext performBlockAndWait:^{
                if (didSaveBlock) didSaveBlock(managedObjectContext, saveInfoDictionary);
                saveInfoDictionary = nil;
            }];
            
            // Complete
            [self completeSuccessfully];
        }
        @catch (NSException *exception) {
            NSDictionary *info = @{NSLocalizedFailureReasonErrorKey:exception.reason};
            NSError *error = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeUnknown userInfo:info];
            [self failWithError:error];
        }
    });
}


#pragma mark Integrating Changes

// Called on background queue.
- (BOOL)integrate:(NSError * __autoreleasing *)error
{
    CDERevisionManager *revisionManager = [[CDERevisionManager alloc] initWithEventStore:self.eventStore eventManagedObjectContext:eventStoreChildContext];
    
    // Check prerequisites
    BOOL canIntegrate = [revisionManager checkIntegrationPrequisites:error];
    if (!canIntegrate) return NO;
    
    // Move to the child event store queue
    __block BOOL success = YES;
    [eventStoreChildContext performBlockAndWait:^{
        // Get all modification events added since the last merge
        NSArray *storeModEvents = [revisionManager fetchUncommittedStoreModificationEvents:error];
        if (!storeModEvents) {
            success = NO;
            return;
        }
        if (storeModEvents.count == 0) return;
        
        // Add any modification events concurrent with the new events. Results are ordered.
        // We repeat this until there is no change in the set. This will be when there are
        // no events existing outside the set that are concurrent with the events in the set.
        NSUInteger eventCount = 0;
        while (storeModEvents.count != eventCount) {
            eventCount = storeModEvents.count;
            storeModEvents = [revisionManager fetchStoreModificationEventsConcurrentWithEvents:storeModEvents error:error];
            if (!storeModEvents) {
                success = NO;
                return;
            }
        }
        if (storeModEvents.count == 0) return;
        
        // If all events are from this device, don't merge
        NSArray *storeIds = [storeModEvents valueForKeyPath:@"@distinctUnionOfObjects.eventRevision.persistentStoreIdentifier"];
        if (storeIds.count == 1 && [storeIds.lastObject isEqualToString:self.eventStore.persistentStoreIdentifier]) return;
        
        // Apply changes in the events, in order.
        for (CDEStoreModificationEvent *storeModEvent in storeModEvents) {
            @autoreleasepool {
                // Insertions are split into two parts: first, we perform an insert without applying property changes,
                // and later, we do an update to set the properties.
                // This is because the object inserts must be carried out before trying to set relationships, because
                // otherwise related objects may not exist. So we create objects first, and only
                // set relationships in the next phase.
                NSMutableDictionary *appliedInsertsByEntity = [NSMutableDictionary dictionary];
                for (NSEntityDescription *entity in managedObjectModel.entities) {
                    NSArray *appliedInsertChanges = [self insertObjectsForStoreModificationEvents:@[storeModEvent] entity:entity error:error];
                    if (!appliedInsertChanges) {
                        success = NO;
                        return;
                    }
                    appliedInsertsByEntity[entity.name] = appliedInsertChanges;
                }
                
                // Now that all objects exist, we can apply property changes.
                // We treat insertions on a par with updates here.
                for (NSEntityDescription *entity in managedObjectModel.entities) {
                    NSArray *inserts = appliedInsertsByEntity[entity.name];
                    success = [self updateObjectsForStoreModificationEvents:@[storeModEvent] entity:entity includingInsertedObjects:inserts error:error];
                    if (!success) return;
                }
                
                // Finally deletions
                for (NSEntityDescription *entity in managedObjectModel.entities) {
                    success = [self deleteObjectsForStoreModificationEvents:@[storeModEvent] entity:entity error:error];
                    if (!success) return;
                }
            }
        }
    }];
    
    return success;
}

// Called on event child context queue
- (NSArray *)insertObjectsForStoreModificationEvents:(NSArray *)storeModEvents entity:(NSEntityDescription *)entity error:(NSError * __autoreleasing *)error
{
    // Fetch all inserts for this entity, including locally saved inserts.
    NSArray *insertChanges = [self fetchObjectChangesOfType:CDEObjectChangeTypeInsert fromStoreModificationEvents:storeModEvents forEntity:entity error:error];
    if (!insertChanges) return nil;
    
    // Insert objects, but don't apply properties yet
    BOOL insertSucceeded = [self insertObjectsForEntity:entity objectChanges:insertChanges error:error];
    if (!insertSucceeded) return nil;

    return insertChanges;
}

// Called on event child context queue
- (BOOL)updateObjectsForStoreModificationEvents:(NSArray *)storeModEvents entity:(NSEntityDescription *)entity includingInsertedObjects:(NSArray *)insertedObjects error:(NSError * __autoreleasing *)error
{
    // Fetch all updates for this entity, excluding deleted objects
    NSArray *updateChanges = [self fetchObjectChangesOfType:CDEObjectChangeTypeUpdate fromStoreModificationEvents:storeModEvents forEntity:entity error:error];
    if (!updateChanges) return NO;
    
    // Mix insertions and updates, and re-sort
    NSArray *changes = [updateChanges arrayByAddingObjectsFromArray:insertedObjects];
    changes = [changes sortedArrayUsingDescriptors:[self objectChangeSortDescriptors]];
    
    // Apply property changes to objects.
    if (![self applyObjectPropertyChanges:changes error:error]) return NO;

    return YES;
}

// Called on event child context queue
- (BOOL)deleteObjectsForStoreModificationEvents:(NSArray *)storeModEvents entity:(NSEntityDescription *)entity error:(NSError * __autoreleasing *)error
{
    NSArray *deletionChanges = [self fetchObjectChangesOfType:CDEObjectChangeTypeDelete fromStoreModificationEvents:storeModEvents forEntity:entity error:error];
    if (!deletionChanges) return NO;
    
    if (![self applyDeletionChanges:deletionChanges error:error]) return NO;
    
    return YES;
}

- (NSArray *)objectChangeSortDescriptors
{
    NSSortDescriptor *countDesc = [NSSortDescriptor sortDescriptorWithKey:@"storeModificationEvent.globalCount" ascending:YES];
    NSSortDescriptor *timestampDesc = [NSSortDescriptor sortDescriptorWithKey:@"storeModificationEvent.timestamp" ascending:YES];
    NSSortDescriptor *storeDesc = [NSSortDescriptor sortDescriptorWithKey:@"storeModificationEvent.eventRevision.persistentStoreIdentifier" ascending:YES];
    NSSortDescriptor *typeDesc = [NSSortDescriptor sortDescriptorWithKey:@"type" ascending:YES];
    return @[countDesc, timestampDesc, storeDesc, typeDesc];
}


#pragma mark Applying Insertions

// Called on event child context queue
- (BOOL)insertObjectsForEntity:(NSEntityDescription *)entity objectChanges:(NSArray *)insertChanges error:(NSError * __autoreleasing *)error
{
    // Loop over insertions, and create all objects before applying properties, because
    // they might be related to each other, and they all need to exist before setting
    // relationships.
    NSMapTable *newObjectsByGlobalId = [NSMapTable strongToStrongObjectsMapTable];
    NSMutableArray *changesNeedingNewObjects = [[NSMutableArray alloc] initWithCapacity:insertChanges.count];
    for (CDEObjectChange *change in insertChanges) {
        // Check if this object has already been created in this import
        // due to multiple inserts of the same global id in different stores
        if ([newObjectsByGlobalId objectForKey:change.globalIdentifier]) continue;
        
        // Check if object already exists in store, and thus doesn't need creating
        if (change.globalIdentifier.storeURI) {
            // Object seems to exist already. Check to be sure.
            NSURL *url = [NSURL URLWithString:change.globalIdentifier.storeURI];
            
            // Check if the object really exists on the queue of the store context
            __block BOOL objectAlreadyExists = NO;
            [managedObjectContext performBlockAndWait:^{
                NSManagedObjectID *objectID = [managedObjectContext.persistentStoreCoordinator managedObjectIDForURIRepresentation:url];
                NSManagedObject *object = [managedObjectContext existingObjectWithID:objectID error:NULL];
                objectAlreadyExists = object && !object.isDeleted && object.managedObjectContext;
            }];
            if (objectAlreadyExists) continue; // Object does exist. Don't create again, but we do apply property changes later.
        }
        
        [changesNeedingNewObjects addObject:change];
    }
        
    // Only now actually create objects, on the main context queue
    NSArray *globalIds = [changesNeedingNewObjects valueForKeyPath:@"globalIdentifier"];
    NSMutableArray *newObjects = [[NSMutableArray alloc] initWithCapacity:globalIds.count];
    __block BOOL success = YES;
    [managedObjectContext performBlockAndWait:^{
        for (CDEGlobalIdentifier *globalId in globalIds) {
            id newObject = [NSEntityDescription insertNewObjectForEntityForName:entity.name inManagedObjectContext:managedObjectContext];
            if (!newObject) {
                success = NO;
                return;
            }
            [newObjectsByGlobalId setObject:newObject forKey:globalId];
            [newObjects addObject:newObject];
        }
    }];
    if (!success) return NO;
    
    // Get permanent store object ids, and then URIs
    __block NSArray *uris;
    [managedObjectContext performBlockAndWait:^{
        success = [managedObjectContext obtainPermanentIDsForObjects:newObjects error:error];
        if (!success) return;
        
        uris = [newObjects valueForKeyPath:@"objectID.URIRepresentation.absoluteString"];
    }];
    if (!success) return NO;
    
    // Update the global ids with the store object ids
    NSUInteger i = 0;
    for (CDEGlobalIdentifier *globalId in globalIds) {
        NSString *uri = uris[i++];
        globalId.storeURI = uri;
    }
    
    return YES;
}


#pragma mark Applying Deletion Changes

// Called on event child context queue
- (BOOL)applyDeletionChanges:(NSArray *)changes error:(NSError * __autoreleasing *)error
{
    NSMapTable *objectsByGlobalId = [self fetchObjectsByGlobalIdentifierForObjectChanges:changes error:error];
    if (!objectsByGlobalId) return NO;
    
    for (CDEObjectChange *change in changes) {
        NSManagedObject *object = [objectsByGlobalId objectForKey:change.globalIdentifier.globalIdentifier];
        
        // Clear the store URI in the global id
        change.globalIdentifier.storeURI = nil;
        
        if (!object) continue;
        
        [managedObjectContext performBlockAndWait:^{
            if (object.isDeleted || object.managedObjectContext == nil) return;

            // Nullify relationships first to prevent cascading
            NSEntityDescription *entity = object.entity;
            for (NSString *relationshipName in entity.relationshipsByName) {
                id related = [self valueForKey:relationshipName inObject:object];
                if (related == nil) continue;
                
                NSRelationshipDescription *description = entity.relationshipsByName[relationshipName];
                if (description.isToMany && [related count] > 0) {
                    if (description.isOrdered) {
                        related = [object mutableOrderedSetValueForKey:relationshipName];
                        [related removeAllObjects];
                    } else {
                        related = [object mutableSetValueForKey:relationshipName];
                        [related removeAllObjects];
                    }
                }
                else {
                    [self setValue:nil forKey:relationshipName inObject:object];
                }
            }
            
            [managedObjectContext deleteObject:object];
        }];
    }
    
    return YES;
}


#pragma mark Applying Property Changes

// Called on event child context queue
- (BOOL)applyObjectPropertyChanges:(NSArray *)changes error:(NSError * __autoreleasing *)error
{
    if (changes.count == 0) return YES;
    
    NSMapTable *objectsByGlobalId = [self fetchObjectsByGlobalIdentifierForObjectChanges:changes error:error];
    if (!objectsByGlobalId) return NO;
    
    NSMapTable *globalIdsByObject = [NSMapTable strongToStrongObjectsMapTable];
    for (CDEGlobalIdentifier *globalId in objectsByGlobalId) {
        id object = [objectsByGlobalId objectForKey:globalId];
        [globalIdsByObject setObject:globalId forKey:object];
    }
    
    @try {
        NSPredicate *attributePredicate = [NSPredicate predicateWithFormat:@"type = %d", CDEPropertyChangeTypeAttribute];
        NSPredicate *toOneRelationshipPredicate = [NSPredicate predicateWithFormat:@"type = %d", CDEPropertyChangeTypeToOneRelationship];
        NSPredicate *toManyRelationshipPredicate = [NSPredicate predicateWithFormat:@"type = %d", CDEPropertyChangeTypeToManyRelationship];
        NSPredicate *orderedToManyRelationshipPredicate = [NSPredicate predicateWithFormat:@"type = %d", CDEPropertyChangeTypeOrderedToManyRelationship];
        
        for (CDEObjectChange *change in changes) {
            @autoreleasepool {
                NSManagedObject *object = [objectsByGlobalId objectForKey:change.globalIdentifier.globalIdentifier];
                NSArray *propertyChangeValues = change.propertyChangeValues;
                if (!object || propertyChangeValues.count == 0) continue;
                
                [managedObjectContext performBlockAndWait:^{
                    // Attribute changes
                    NSArray *attributeChanges = [propertyChangeValues filteredArrayUsingPredicate:attributePredicate];
                    [self applyAttributeChanges:attributeChanges toObject:object];
                    
                    // To-one relationship changes
                    NSArray *toOneChanges = [propertyChangeValues filteredArrayUsingPredicate:toOneRelationshipPredicate];
                    [self applyToOneRelationshipChanges:toOneChanges toObject:object withObjectsByGlobalId:objectsByGlobalId];
                    
                    // To-many relationship changes
                    NSArray *toManyChanges = [propertyChangeValues filteredArrayUsingPredicate:toManyRelationshipPredicate];
                    [self applyToManyRelationshipChanges:toManyChanges toObject:object withObjectsByGlobalId:objectsByGlobalId];
                    
                    // Ordered to-many relationship changes
                    NSArray *orderedToManyChanges = [propertyChangeValues filteredArrayUsingPredicate:orderedToManyRelationshipPredicate];
                    [self applyOrderedToManyRelationshipChanges:orderedToManyChanges toObject:object withObjectsByGlobalId:objectsByGlobalId andGlobalIdsByObject:globalIdsByObject];
                }];
            }
        }
    }
    @catch (NSException *exception) {
        *error = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeUnknown userInfo:@{NSLocalizedFailureReasonErrorKey:exception.reason}];
        return NO;
    }
    
    return YES;
}

// Called on main context queue
- (void)applyAttributeChanges:(NSArray *)properyChangeValues toObject:(NSManagedObject *)object
{
    NSEntityDescription *entity = object.entity;
    for (CDEPropertyChangeValue *changeValue in properyChangeValues) {
        id newValue = changeValue.value;
        if (newValue == [NSNull null]) newValue = nil;
        
        NSAttributeDescription *attribute = entity.attributesByName[changeValue.propertyName];
        if (!attribute) {
            // Likely attribute removed from model since change
            CDELog(CDELoggingLevelWarning, @"Attribute from change value not in model: %@", changeValue.propertyName);
            continue;
        }
        
        if (attribute.valueTransformerName) {
            NSValueTransformer *valueTransformer = [NSValueTransformer valueTransformerForName:attribute.valueTransformerName];
            if (!valueTransformer) {
                CDELog(CDELoggingLevelWarning, @"Failed to retrieve value transformer: %@", attribute.valueTransformerName);
                continue;
            }
            newValue = [valueTransformer reverseTransformedValue:newValue];
        }
        
        [self setValue:newValue forKey:changeValue.propertyName inObject:object];
    }
}

// Called on main context queue
- (void)applyToOneRelationshipChanges:(NSArray *)changes toObject:(NSManagedObject *)object withObjectsByGlobalId:(NSMapTable *)objectsByGlobalId
{
    NSEntityDescription *entity = object.entity;
    for (CDEPropertyChangeValue *relationshipChange in changes) {
        NSRelationshipDescription *relationship = entity.relationshipsByName[relationshipChange.propertyName];
        if (!relationship || relationship.isToMany) {
            CDELog(CDELoggingLevelWarning, @"Could not find relationship in entity, or found a to-many relationship for a to-one property change. Skipping: %@ %@", relationshipChange.propertyName, relationshipChange.relatedIdentifier);
            continue;
        }
        
        id newRelatedObject = nil;
        if (relationshipChange.relatedIdentifier && (id)relationshipChange.relatedIdentifier != [NSNull null]) {
            newRelatedObject = [objectsByGlobalId objectForKey:relationshipChange.relatedIdentifier];
            if (!newRelatedObject) {
                CDELog(CDELoggingLevelWarning, @"Could not find object for identifier while setting to-one relationship. Skipping: %@", relationshipChange.relatedIdentifier);
                continue;
            }
        }
        
        [self setValue:newRelatedObject forKey:relationshipChange.propertyName inObject:object];
    }
}

// Called on main context queue
- (void)applyToManyRelationshipChanges:(NSArray *)changes toObject:(NSManagedObject *)object withObjectsByGlobalId:(NSMapTable *)objectsByGlobalId
{
    NSEntityDescription *entity = object.entity;
    for (CDEPropertyChangeValue *relationshipChange in changes) {
        NSRelationshipDescription *relationship = entity.relationshipsByName[relationshipChange.propertyName];
        if (!relationship || !relationship.isToMany) {
            CDELog(CDELoggingLevelWarning, @"Could not find relationship in entity, or found a to-one relationship for a to-many property change. Skipping: %@ %@", relationshipChange.propertyName, relationshipChange.relatedIdentifier);
            continue;
        }
        
        NSMutableSet *relatedObjects = [object mutableSetValueForKey:relationshipChange.propertyName];
        for (NSString *identifier in relationshipChange.addedIdentifiers) {
            id newRelatedObject = [objectsByGlobalId objectForKey:identifier];
            if (newRelatedObject)
                [relatedObjects addObject:newRelatedObject];
            else
                CDELog(CDELoggingLevelWarning, @"Could not find object with identifier while adding to relationship. Skipping: %@", identifier);
        }
        
        for (NSString *identifier in relationshipChange.removedIdentifiers) {
            id removedObject = [objectsByGlobalId objectForKey:identifier];
            if (removedObject)
                [relatedObjects removeObject:removedObject];
            else
                CDELog(CDELoggingLevelWarning, @"Could not find object with identifier to remove from relationship. Skipping: %@", identifier);
        }
    }
}

// Called on main context queue
- (void)applyOrderedToManyRelationshipChanges:(NSArray *)changes toObject:(NSManagedObject *)object withObjectsByGlobalId:(NSMapTable *)objectsByGlobalId andGlobalIdsByObject:(NSMapTable *)globalIdsByObject
{
    NSEntityDescription *entity = object.entity;
    for (CDEPropertyChangeValue *relationshipChange in changes) {
        NSRelationshipDescription *relationship = entity.relationshipsByName[relationshipChange.propertyName];
        if (!relationship || !relationship.isToMany || !relationship.isOrdered) {
            CDELog(CDELoggingLevelWarning, @"Could not find relationship in entity, or found the wrong type of relationship. Skipping: %@ %@", relationshipChange.propertyName, relationshipChange.relatedIdentifier);
            continue;
        }
        
        // Merge indexes for global ids
        NSMutableOrderedSet *relatedObjects = [object mutableOrderedSetValueForKey:relationshipChange.propertyName];
        NSMapTable *finalIndexesByObject = [NSMapTable strongToStrongObjectsMapTable];
        for (NSUInteger index = 0; index < relatedObjects.count; index++) {
            [finalIndexesByObject setObject:@(index) forKey:relatedObjects[index]];
        }
        
        // Added objects
        for (NSString *identifier in relationshipChange.addedIdentifiers) {
            id newRelatedObject = [objectsByGlobalId objectForKey:identifier];
            if (newRelatedObject)
                [relatedObjects addObject:newRelatedObject];
            else
                CDELog(CDELoggingLevelWarning, @"Could not find object with identifier while adding to relationship. Skipping: %@", identifier);
        }
        
        // Delete removed objects
        for (NSString *identifier in relationshipChange.removedIdentifiers) {
            id removedObject = [objectsByGlobalId objectForKey:identifier];
            if (removedObject)
                [relatedObjects removeObject:removedObject];
            else
                CDELog(CDELoggingLevelWarning, @"Could not find object with identifier to remove from relationship. Skipping: %@", identifier);
        }
        
        // Determine indexes for objects in the moved identifiers
        NSDictionary *movedIdentifiersByIndex = relationshipChange.movedIdentifiersByIndex;
        for (NSNumber *index in movedIdentifiersByIndex.allKeys) {
            NSString *globalId = movedIdentifiersByIndex[index];
            id relatedObject = [objectsByGlobalId objectForKey:globalId];
            [finalIndexesByObject setObject:(index) forKey:relatedObject];
        }
        
        // Apply new ordering. Sort first on index, and use global id to resolve conflicts.
        [relatedObjects sortUsingComparator:^NSComparisonResult(id object1, id object2) {
            NSNumber *index1 = [finalIndexesByObject objectForKey:object1];
            NSNumber *index2 = [finalIndexesByObject objectForKey:object2];
            NSComparisonResult indexResult = [index1 compare:index2];
            
            if (indexResult != NSOrderedSame) return indexResult;
            
            NSString *globalId1 = [globalIdsByObject objectForKey:object1];
            NSString *globalId2 = [globalIdsByObject objectForKey:object2];
            NSComparisonResult globalIdResult = [globalId1 compare:globalId2];
            
            return globalIdResult;
        }];
    }
}


#pragma mark Repairing (Conflict Resolution)

// Called on background queue
- (BOOL)repairWithMergeEventBuilder:(CDEEventBuilder *)eventBuilder error:(NSError * __autoreleasing *)error
{
    // Give opportunity to merge/repair changes in a child context.
    // We can then retrieve the changes and generate a new store mod event to represent the merge.
    __block BOOL merged = YES;
    __block BOOL contextHasChanges = NO;
    
    [managedObjectContext performBlockAndWait:^{
        contextHasChanges = managedObjectContext.hasChanges;
    }];
    
    if (contextHasChanges && willSaveBlock) {
        __block NSDictionary *info = nil;
        [managedObjectContext performBlockAndWait:^{
            info = [self infoDictionaryForChangesInContext:managedObjectContext];
        }];
        
        NSManagedObjectContext *userMergeContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
        [userMergeContext performBlockAndWait:^{
            userMergeContext.parentContext = managedObjectContext;
            willSaveBlock(userMergeContext, info);
            
            if (userMergeContext.hasChanges) {
                BOOL success = [eventBuilder addChangesForUnsavedManagedObjectContext:userMergeContext error:error];
                if (!success) {
                    merged = NO;
                    return;
                }
                merged = [self saveUserMergeContext:userMergeContext error:error];
            }
        }];
    }
    return merged;
}

- (void)mergeChangesFromUserMergeContextDidSaveNotification:(NSNotification *)notif
{
    [managedObjectContext performBlockAndWait:^{
        [managedObjectContext mergeChangesFromContextDidSaveNotification:notif];
    }];
}

// Call on user merge context queue
- (BOOL)saveUserMergeContext:(NSManagedObjectContext *)userMergeContext error:(NSError * __autoreleasing *)error
{
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(mergeChangesFromUserMergeContextDidSaveNotification:) name:NSManagedObjectContextDidSaveNotification object:userMergeContext];
    
    __block BOOL saved;
    saved = [userMergeContext save:error];
    [userMergeContext reset];

    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSManagedObjectContextDidSaveNotification object:userMergeContext];
    
    return saved;
}

- (NSDictionary *)infoDictionaryForChangesInContext:(NSManagedObjectContext *)aContext
{
    NSSet *insertedObjectIDs = [aContext.insertedObjects valueForKeyPath:@"objectID"];
    NSSet *updatedObjectIDs = [aContext.updatedObjects valueForKeyPath:@"objectID"];
    NSSet *deletedObjectIDs = [aContext.deletedObjects valueForKeyPath:@"objectID"];
    NSDictionary *result = @{NSInsertedObjectsKey: insertedObjectIDs, NSUpdatedObjectsKey: updatedObjectIDs, NSDeletedObjectsKey: deletedObjectIDs};
    return result;
}

// Call on event child context queue
- (NSArray *)fetchObjectChangesOfType:(CDEObjectChangeType)type fromStoreModificationEvents:(id <NSFastEnumeration>)events forEntity:(NSEntityDescription *)entity error:(NSError * __autoreleasing *)error;
{
    NSArray *result = nil;
    @autoreleasepool {
        NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"CDEObjectChange"];
        fetch.predicate = [NSPredicate predicateWithFormat:@"nameOfEntity = %@ && type = %d && storeModificationEvent in %@", entity.name, type, events];
        fetch.sortDescriptors = [self objectChangeSortDescriptors];
        fetch.relationshipKeyPathsForPrefetching = @[@"globalIdentifier"];
        result = [eventStoreChildContext executeFetchRequest:fetch error:error];
    }
    return result;
}


#pragma mark Fetching from Synced Store

- (NSMapTable *)fetchObjectsByGlobalIdentifierForEntityName:(NSString *)entityName globalIdentifiers:(id)globalIdentifiers error:(NSError * __autoreleasing *)error
{
    // Setup mappings between types of identifiers
    NSPersistentStoreCoordinator *coordinator = managedObjectContext.persistentStoreCoordinator;
    NSMutableSet *objectIDs = [[NSMutableSet alloc] initWithCapacity:[globalIdentifiers count]];
    NSMapTable *objectIDByGlobalId = [NSMapTable strongToStrongObjectsMapTable];
    for (CDEGlobalIdentifier *globalId in globalIdentifiers) {
        NSString *storeIdString = globalId.storeURI;
        if (!storeIdString) continue; // Doesn't exist in store
        
        NSURL *uri = [NSURL URLWithString:storeIdString];
        NSManagedObjectID *objectID = [coordinator managedObjectIDForURIRepresentation:uri];
        [objectIDs addObject:objectID];
        
        [objectIDByGlobalId setObject:objectID forKey:globalId];
    }
    
    // Fetch objects
    __block NSArray *objects = nil;
    __block NSArray *objectIDsOfFetched = nil;
    [managedObjectContext performBlockAndWait:^{
        NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:entityName];
        fetch.predicate = [NSPredicate predicateWithFormat:@"SELF IN %@", objectIDs];
        objects = [managedObjectContext executeFetchRequest:fetch error:error];
        objectIDsOfFetched = [objects valueForKeyPath:@"objectID"];
    }];
    if (!objects) return nil;
    
    // ObjectID to object mapping
    NSDictionary *objectByObjectID = [[NSDictionary alloc] initWithObjects:objects forKeys:objectIDsOfFetched];
    
    // Prepare results
    NSMapTable *result = [NSMapTable strongToStrongObjectsMapTable];
    for (CDEGlobalIdentifier *globalId in globalIdentifiers) {
        NSManagedObjectID *objectID = [objectIDByGlobalId objectForKey:globalId];
        [result setObject:objectByObjectID[objectID] forKey:globalId];
    }
    
    return result;
}

// Called on event store child context
- (NSMapTable *)fetchObjectsByGlobalIdentifierForObjectChanges:(id)objectChanges error:(NSError * __autoreleasing *)error
{
    // Get ids for objects directly involved in the change
    NSSet *globalIdStrings = [self globalIdentifierStringsInObjectChanges:objectChanges];
    NSArray *globalIds = [self fetchGlobalIdentifiersForIdentifierStrings:globalIdStrings];
    NSMapTable *changeObjectsByIdString = [self fetchObjectsByIdStringForGlobalIdentifiers:globalIds];

    // We need to get ids for existing related objects in ordered relationships.
    // The existing objects are needed, because we always need
    // to sort an ordered relationship, and this involves all objects, whether they are new or not.
    NSMapTable *relatedOrderedObjectsByIdString = [self fetchObjectsByIdStringForRelatedObjectsInOrderedRelationshipsOfObjectChanges:objectChanges];
    
    NSMapTable *result = [NSMapTable strongToStrongObjectsMapTable];
    [result cde_addEntriesFromMapTable:changeObjectsByIdString];
    [result cde_addEntriesFromMapTable:relatedOrderedObjectsByIdString];
    
    return result;
}

- (NSMapTable *)fetchObjectsByIdStringForRelatedObjectsInOrderedRelationshipsOfObjectChanges:(id)objectChanges
{
    NSMapTable *changedOrderedPropertiesByGlobalId = [NSMapTable strongToStrongObjectsMapTable];
    for (CDEObjectChange *change in objectChanges) {
        NSArray *propertyChangeValues = change.propertyChangeValues;
        for (CDEPropertyChangeValue *value in propertyChangeValues) {
            if (value.movedIdentifiersByIndex.count > 0) {
                // Store the property name, so we can add existing related objects below
                CDEGlobalIdentifier *globalId = change.globalIdentifier;
                NSMutableSet *propertyNames = [changedOrderedPropertiesByGlobalId objectForKey:globalId];
                if (!propertyNames) propertyNames = [[NSMutableSet alloc] initWithCapacity:3];
                [propertyNames addObject:value.propertyName];
                [changedOrderedPropertiesByGlobalId setObject:propertyNames forKey:globalId];
            }
        }
    }
    
    NSArray *allGlobalIds = changedOrderedPropertiesByGlobalId.cde_allKeys;
    NSDictionary *globalIdsByEntity = [self entityGroupedGlobalIdentifiersForIdentifiers:allGlobalIds];
    NSMutableArray *relatedObjects = [[NSMutableArray alloc] init];
    for (NSString *entityName in globalIdsByEntity) {
        NSError *error;
        NSArray *globalIds = globalIdsByEntity[entityName];
        NSMapTable *objectsByGlobalId = [self fetchObjectsByGlobalIdentifierForEntityName:entityName globalIdentifiers:globalIds error:&error];
        for (CDEGlobalIdentifier *globalId in globalIds) {
            NSSet *changedOrderedProperties = [changedOrderedPropertiesByGlobalId objectForKey:globalId];
            NSManagedObject *object = [objectsByGlobalId objectForKey:globalId];
            for (NSString *propertyName in changedOrderedProperties) {
                NSOrderedSet *relatedSet = [object valueForKey:propertyName];
                [relatedObjects addObjectsFromArray:relatedSet.array];
            }
        }
    }
    
    NSArray *objectIDs = [relatedObjects valueForKeyPath:@"objectID"];
    NSArray *globalIds = [CDEGlobalIdentifier fetchGlobalIdentifiersForObjectIDs:objectIDs inManagedObjectContext:eventStoreChildContext];

    NSMapTable *relatedObjectsByGlobalId = [NSMapTable strongToStrongObjectsMapTable];
    [relatedObjects enumerateObjectsUsingBlock:^(id object, NSUInteger index, BOOL *stop) {
        CDEGlobalIdentifier *globalId = globalIds[index];
        if (globalId == (id)[NSNull null]) {
            CDELog(CDELoggingLevelError, @"A global identifier was not found for an ordered-relationship object");
            return;
        }
        [relatedObjectsByGlobalId setObject:object forKey:globalId.globalIdentifier];
    }];
    
    return relatedObjectsByGlobalId;
}

- (NSMapTable *)fetchObjectsByIdStringForGlobalIdentifiers:(NSArray *)globalIds
{
    NSDictionary *globalIdsByEntityName = [self entityGroupedGlobalIdentifiersForIdentifiers:globalIds];
    NSMapTable *results = [NSMapTable strongToStrongObjectsMapTable];
    for (NSString *entityName in globalIdsByEntityName) {
        NSSet *entityGlobalIds = globalIdsByEntityName[entityName];
        NSError *error;
        NSMapTable *resultsForEntity = [self fetchObjectsByGlobalIdentifierForEntityName:entityName globalIdentifiers:entityGlobalIds error:&error];
        if (!resultsForEntity) return nil;
        
        for (CDEGlobalIdentifier *globalId in resultsForEntity) {
            [results setObject:[resultsForEntity objectForKey:globalId] forKey:globalId.globalIdentifier];
        }
    }
    return results;
}

- (NSArray *)fetchGlobalIdentifiersForIdentifierStrings:(id)idStrings
{
    NSError *error;
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"CDEGlobalIdentifier"];
    fetch.predicate = [NSPredicate predicateWithFormat:@"globalIdentifier IN %@", idStrings];
    NSArray *globalIds = [eventStoreChildContext executeFetchRequest:fetch error:&error];
    if (!globalIds) NSLog(@"Error fetching ids: %@", error);
    return globalIds;
}

- (NSSet *)globalIdentifierStringsInObjectChanges:(id)objectChanges
{
    NSMutableSet *globalIdStrings = [NSMutableSet setWithCapacity:[objectChanges count]*3];
    for (CDEObjectChange *change in objectChanges) {
        [globalIdStrings addObject:change.globalIdentifier.globalIdentifier];
        
        NSArray *propertyChangeValues = change.propertyChangeValues;
        for (CDEPropertyChangeValue *value in propertyChangeValues) {
            if (value.relatedIdentifier) [globalIdStrings addObject:value.relatedIdentifier];
            if (value.addedIdentifiers) [globalIdStrings unionSet:value.addedIdentifiers];
            if (value.removedIdentifiers) [globalIdStrings unionSet:value.removedIdentifiers];
            if (value.movedIdentifiersByIndex) [globalIdStrings addObjectsFromArray:value.movedIdentifiersByIndex.allValues];
        }
    }
    return globalIdStrings;
}

- (NSDictionary *)entityGroupedGlobalIdentifiersForIdentifiers:(NSArray *)globalIds
{
    NSMutableDictionary *globalIdsByEntityName = [NSMutableDictionary dictionaryWithCapacity:globalIds.count];
    for (CDEGlobalIdentifier *globalId in globalIds) {
        NSMutableSet *idsForEntity = globalIdsByEntityName[globalId.nameOfEntity];
        if (!idsForEntity) {
            idsForEntity = [NSMutableSet set];
            globalIdsByEntityName[globalId.nameOfEntity] = idsForEntity;
        }
        [idsForEntity addObject:globalId];
    }
    return globalIdsByEntityName;
}


#pragma mark Committing

// Called on background queue
- (BOOL)commitWithMergeEventBuilder:(CDEEventBuilder *)eventBuilder error:(NSError * __autoreleasing *)error
{
    __block BOOL saved = [self saveContext:error];
    if (!saved) {
        if ((*error).code != NSManagedObjectMergeError && failedSaveBlock) {
            NSManagedObjectContext *userMergeContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
            
            __block BOOL needExtraSave = NO;
            [userMergeContext performBlockAndWait:^{
                BOOL retry;
                userMergeContext.parentContext = managedObjectContext;
                retry = failedSaveBlock(userMergeContext, *error);
            
                if (retry && userMergeContext.hasChanges) {
                    BOOL success = [eventBuilder addChangesForUnsavedManagedObjectContext:userMergeContext error:error];
                    success = success && [self saveUserMergeContext:userMergeContext error:error];
                    if (success) needExtraSave = YES;
                }
            }];
            
            if (needExtraSave) saved = [self saveContext:error];
        }
    }
    return saved;
}

// Call from any queue
- (BOOL)saveContext:(NSError * __autoreleasing *)error
{
    __block BOOL saved = NO;
    [managedObjectContext performBlockAndWait:^{
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(mergeChangesFromContextDidSaveNotification:) name:NSManagedObjectContextDidSaveNotification object:managedObjectContext];
        saved = [managedObjectContext save:error];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:NSManagedObjectContextDidSaveNotification object:managedObjectContext];
    }];
    return saved;
}

- (void)mergeChangesFromContextDidSaveNotification:(NSNotification *)notif
{
    saveInfoDictionary = notif.userInfo;
}

@end
