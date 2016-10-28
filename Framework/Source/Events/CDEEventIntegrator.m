//
//  CDEEventIntegrator.m
//  Test App iOS
//
//  Created by Drew McCormack on 4/23/13.
//  Copyright (c) 2013 The Mental Faculty B.V. All rights reserved.
//

#import "CDEEventIntegrator.h"
#import "CDEFoundationAdditions.h"
#import "CDEEventBuilder.h"
#import "CDEPersistentStoreEnsemble.h"
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
    NSDictionary *saveInfoDictionary;
    dispatch_queue_t queue;
    id eventStoreChildContextSaveObserver;
    NSString *newEventUniqueId;
    BOOL saveOccurredDuringMerge;
}

@synthesize storeURL = storeURL;
@synthesize managedObjectContext = managedObjectContext;
@synthesize managedObjectModel = managedObjectModel;
@synthesize eventStore = eventStore;
@synthesize shouldSaveBlock = shouldSaveBlock;
@synthesize didSaveBlock = didSaveBlock;
@synthesize failedSaveBlock = failedSaveBlock;
@synthesize persistentStoreOptions = persistentStoreOptions;


#pragma mark Initialization

- (instancetype)initWithStoreURL:(NSURL *)newStoreURL managedObjectModel:(NSManagedObjectModel *)model eventStore:(CDEEventStore *)newEventStore
{
    self = [super init];
    if (self) {
        storeURL = [newStoreURL copy];
        managedObjectModel = model;
        eventStore = newEventStore;
        shouldSaveBlock = NULL;
        didSaveBlock = NULL;
        failedSaveBlock = NULL;
        persistentStoreOptions = nil;
        queue = dispatch_queue_create("com.mentalfaculty.ensembles.eventintegrator", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:eventStoreChildContextSaveObserver];
    [self stopMonitoringSaves];
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


#pragma mark Observing Saves

- (void)startMonitoringSaves
{
    [self stopMonitoringSaves];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(contextSaving:) name:NSManagedObjectContextWillSaveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(contextSaving:) name:NSManagedObjectContextDidSaveNotification object:nil];
}

- (void)stopMonitoringSaves
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSManagedObjectContextWillSaveNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSManagedObjectContextDidSaveNotification object:nil];
    saveOccurredDuringMerge = NO;
}

- (void)contextSaving:(NSNotification *)notif
{
    NSManagedObjectContext *context = notif.object;
    if (self.managedObjectContext == context) return;
    if (context.parentContext) return; // Only handle contexts saving directly to store
    
    NSArray *stores = context.persistentStoreCoordinator.persistentStores;
    for (NSPersistentStore *store in stores) {
        NSURL *url1 = [self.storeURL URLByStandardizingPath];
        NSURL *url2 = [store.URL URLByStandardizingPath];
        if ([url1 isEqual:url2]) {
            saveOccurredDuringMerge = YES;
            break;
        }
    }
}


#pragma mark Merging Store Modification Events

- (void)mergeEventsWithCompletion:(CDECompletionBlock)completion
{
    NSAssert([NSThread isMainThread], @"mergeEvents... called off main thread");
    
    newEventUniqueId = nil;
    
    // Setup a context for accessing the main store
    NSError *error = nil;
    NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:managedObjectModel];
    NSPersistentStore *persistentStore = [coordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:self.persistentStoreOptions error:&error];
    if (!persistentStore) {
        [self failWithCompletion:completion error:error];
        return;
    }
    
    self.managedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    [self.managedObjectContext performBlockAndWait:^{
        self.managedObjectContext.persistentStoreCoordinator = coordinator;
        self.managedObjectContext.undoManager = nil;
    }];
    
    NSManagedObjectContext *eventStoreContext = self.eventStore.managedObjectContext;
    
    // Integrate on background queue
    dispatch_async(queue,^{
        @try {
            __block NSError *error = nil;
            
            // Apply changes
            BOOL integrationSucceeded = [self integrate:&error];
            if (!integrationSucceeded) {
                [self failWithCompletion:completion error:error];
                return;
            }
            
            // If no changes, complete
            __block BOOL hasChanges;
            [managedObjectContext performBlockAndWait:^{
                hasChanges = managedObjectContext.hasChanges;
            }];
            if (!hasChanges) {
                [self completeSuccessfullyWithCompletion:completion];
                return;
            }
            
            // Create id of new event
            // Register event in case of crashes
            newEventUniqueId = [[NSProcessInfo processInfo] globallyUniqueString];
            [self.eventStore registerIncompleteEventIdentifier:newEventUniqueId isMandatory:NO];
            
            // Create a merge event
            CDEEventBuilder *eventBuilder = [[CDEEventBuilder alloc] initWithEventStore:self.eventStore];
            eventBuilder.ensemble = self.ensemble;
            CDERevision *revision = [eventBuilder makeNewEventOfType:CDEStoreModificationEventTypeMerge uniqueIdentifier:newEventUniqueId];
        
            // Repair inconsistencies caused by integration
            BOOL repairSucceeded = [self repairWithMergeEventBuilder:eventBuilder error:&error];
            if (!repairSucceeded) {
                [self failWithCompletion:completion error:error];
                return;
            }
            
            // Commit (save) the changes
            BOOL commitSucceeded = [self commitWithMergeEventBuilder:eventBuilder error:&error];
            if (!commitSucceeded) {
                [self failWithCompletion:completion error:error];
                return;
            }
            
            // Save changes event context
            __block BOOL eventSaveSucceeded = NO;
            [eventStoreContext performBlockAndWait:^{
                NSError *blockError = nil;
                BOOL isUnique = [self checkUniquenessOfEventWithRevision:revision];
                if (isUnique) {
                    [eventBuilder finalizeNewEvent];
                    eventSaveSucceeded = [eventStoreContext save:&blockError];
                }
                else {
                    blockError = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeSaveOccurredDuringMerge userInfo:nil];
                }
                [eventStoreContext reset];
                error = blockError;
            }];
            if (!eventSaveSucceeded) {
                [self failWithCompletion:completion error:error];
                return;
            }

            // Notify of save
            [self.managedObjectContext performBlockAndWait:^{
                if (didSaveBlock) didSaveBlock(managedObjectContext, saveInfoDictionary);
            }];
            saveInfoDictionary = nil;
            
            // Complete
            [self completeSuccessfullyWithCompletion:completion];
        }
        @catch (NSException *exception) {
            NSDictionary *info = @{NSLocalizedFailureReasonErrorKey:exception.reason};
            NSError *error = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeUnknown userInfo:info];
            [self failWithCompletion:completion error:error];
        }
    });
}

- (BOOL)checkUniquenessOfEventWithRevision:(CDERevision *)revision
{
    __block NSUInteger count = 0;
    [self.eventStore.managedObjectContext performBlockAndWait:^{
        NSFetchRequest *fetch = [[NSFetchRequest alloc] initWithEntityName:@"CDEStoreModificationEvent"];
        fetch.predicate = [NSPredicate predicateWithFormat:@"eventRevision.persistentStoreIdentifier = %@ && eventRevision.revisionNumber = %lld && type != %d", self.eventStore.persistentStoreIdentifier, revision.revisionNumber, CDEStoreModificationEventTypeBaseline];
        NSError *error = nil;
        count = [self.eventStore.managedObjectContext countForFetchRequest:fetch error:&error];
        if (count == NSNotFound) CDELog(CDELoggingLevelError, @"Could not get count of revisions: %@", error);
    }];
    return count == 1;
}


#pragma mark Completing Merge

- (void)failWithCompletion:(CDECompletionBlock)completion error:(NSError *)error
{
    NSManagedObjectContext *eventContext = self.eventStore.managedObjectContext;
    if (newEventUniqueId) {
        [eventContext performBlockAndWait:^{
            NSError *innerError = nil;
            CDEStoreModificationEvent *event = [CDEStoreModificationEvent fetchStoreModificationEventWithUniqueIdentifier:newEventUniqueId inManagedObjectContext:eventContext];
            if (event) {
                [eventContext deleteObject:event];
                if (![eventContext save:&innerError]) {
                    CDELog(CDELoggingLevelError, @"Could not save after deleting partially merged event from a failed merge. Will reset context: %@", innerError);
                    [eventContext reset];
                }
            }
        }];
    }
    if (newEventUniqueId) [self.eventStore deregisterIncompleteEventIdentifier:newEventUniqueId];
    newEventUniqueId = nil;
    managedObjectContext = nil;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (completion) completion(error);
    });
}

- (void)completeSuccessfullyWithCompletion:(CDECompletionBlock)completion
{
    if (newEventUniqueId) [self.eventStore deregisterIncompleteEventIdentifier:newEventUniqueId];
    newEventUniqueId = nil;
    managedObjectContext = nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (completion) completion(nil);
    });
}


#pragma mark Integrating Changes

- (BOOL)needsFullIntegration
{
    // Determine if we need to do a full integration of all data.
    // First case is if the baseline identity has changed.
    NSString *storeBaselineId = self.eventStore.identifierOfBaselineUsedToConstructStore;
    NSString *currentBaselineId = self.eventStore.currentBaselineIdentifier;
    if (!storeBaselineId || ![storeBaselineId isEqualToString:currentBaselineId]) return YES;
    
    // Determine if a full integration is needed due to abandonment during rebasing
    // This is the case if no events exist that are newer than the baseline.
    CDERevisionManager *revisionManager = [[CDERevisionManager alloc] initWithEventStore:self.eventStore];
    NSError *error = nil;
    BOOL passed = [revisionManager checkThatLocalPersistentStoreHasNotBeenAbandoned:&error];
    if (error) CDELog(CDELoggingLevelError, @"Error determining if store is abandoned: %@", error);
    if (!passed) return YES;
    
    return NO;
}

// Called on background queue.
- (BOOL)integrate:(NSError * __autoreleasing *)error
{
    CDELog(CDELoggingLevelVerbose, @"Integrating new events into main context");

    CDERevisionManager *revisionManager = [[CDERevisionManager alloc] initWithEventStore:self.eventStore];
    revisionManager.managedObjectModelURL = self.ensemble.managedObjectModelURL;
    
    // Move to the event store queue
    __block BOOL success = YES;
    BOOL needFullIntegration = [self needsFullIntegration];
    NSManagedObjectContext *eventStoreContext = self.eventStore.managedObjectContext;
    __block NSError *methodError = nil;
    [eventStoreContext performBlockAndWait:^{
        // Get events
        NSArray *storeModEvents = nil;
        NSError *blockError = nil;
        if (needFullIntegration) {
            // All events, including baseline
            NSMutableArray *events = [[CDEStoreModificationEvent fetchNonBaselineEventsInManagedObjectContext:eventStoreContext] mutableCopy];
            CDEStoreModificationEvent *baseline = [CDEStoreModificationEvent fetchMostRecentBaselineStoreModificationEventInManagedObjectContext:eventStoreContext];
            if (baseline) [events insertObject:baseline atIndex:0];
            storeModEvents = events;
            CDELog(CDELoggingLevelVerbose, @"Baseline has changed. Will carry out full integration of the persistent store.");
        }
        else {
            // Get all modification events added since the last merge
            storeModEvents = [revisionManager fetchUncommittedStoreModificationEvents:&blockError];
            if (!storeModEvents) {
                methodError = blockError;
                success = NO;
                return;
            }
            if (storeModEvents.count == 0) return;
            
            // Add any modification events concurrent with the new events. Results are ordered.
            // We repeat this until there is no change in the set. This will be when there are
            // no events existing outside the set that are concurrent with the events in the set.
            storeModEvents = [revisionManager recursivelyFetchStoreModificationEventsConcurrentWithEvents:storeModEvents error:&blockError];
        }
        if (storeModEvents == nil) {
            success = NO;
            methodError = blockError;
        }
        if (storeModEvents.count == 0) return;
        
        // Check prerequisites
        BOOL canIntegrate = [revisionManager checkIntegrationPrequisitesForEvents:storeModEvents error:&blockError];
        if (!canIntegrate) {
            methodError = blockError;
            success = NO;
            return;
        }
        
        // If all events are from this device, don't merge
        NSArray *storeIds = [storeModEvents valueForKeyPath:@"@distinctUnionOfObjects.eventRevision.persistentStoreIdentifier"];
        if (!needFullIntegration && storeIds.count == 1 && [storeIds.lastObject isEqualToString:self.eventStore.persistentStoreIdentifier]) return;
        
        // If there are no object changes, don't merge
        NSUInteger numberOfChanges = [[storeModEvents valueForKeyPath:@"@sum.objectChanges.@count"] unsignedIntegerValue];
        if (numberOfChanges == 0) return;
        
        // Apply changes in the events, in order.
        NSMutableDictionary *insertedObjectIDsByEntity = needFullIntegration ? [[NSMutableDictionary alloc] init] : nil;
        @try {
            for (CDEStoreModificationEvent *storeModEvent in storeModEvents) {
                @autoreleasepool {
                    // Determine which entities have changes
                    NSSet *changedEntityNames = [storeModEvent.objectChanges valueForKeyPath:@"nameOfEntity"];
                    NSMutableArray *changedEntities = [[changedEntityNames.allObjects cde_arrayByTransformingObjectsWithBlock:^(NSString *name) {
                        return managedObjectModel.entitiesByName[name];
                    }] mutableCopy];
                    [changedEntities removeObject:[NSNull null]];
                    
                    // Insertions are split into two parts: first, we perform an insert without applying property changes,
                    // and later, we do an update to set the properties.
                    // This is because the object inserts must be carried out before trying to set relationships,
                    // otherwise related objects may not exist. So we create objects first, and only
                    // set relationships in the next phase.
                    NSMutableDictionary *appliedInsertsByEntity = [NSMutableDictionary dictionary];
                    NSError *innerPoolError = nil;
                    for (NSEntityDescription *entity in changedEntities) {
                        NSArray *appliedInsertChanges = [self insertObjectsForStoreModificationEvents:@[storeModEvent] entity:entity error:&innerPoolError];
                        if (!appliedInsertChanges) {
                            blockError = innerPoolError;
                            @throw [NSException exceptionWithName:CDEException reason:@"" userInfo:nil];
                        }
                        appliedInsertsByEntity[entity.name] = appliedInsertChanges;
                        
                        // If full integration, track all inserted object ids, so we can delete unreferenced objects
                        if (needFullIntegration) [self updateObjectIDsByEntity:insertedObjectIDsByEntity forEntity:entity insertChanges:appliedInsertChanges];
                    }
                    
                    // Now that all objects exist, we can apply property changes.
                    // We treat insertions on a par with updates here.
                    for (NSEntityDescription *entity in changedEntities) {
                        NSArray *inserts = appliedInsertsByEntity[entity.name];
                        success = [self updateObjectsForStoreModificationEvents:@[storeModEvent] entity:entity includingInsertedObjects:inserts error:&innerPoolError];
                        if (!success) {
                            blockError = innerPoolError;
                            @throw [NSException exceptionWithName:CDEException reason:@"" userInfo:nil];
                        }
                    }
                    
                    // Finally deletions
                    for (NSEntityDescription *entity in changedEntities) {
                        success = [self deleteObjectsForStoreModificationEvents:@[storeModEvent] entity:entity error:&innerPoolError];
                        if (!success) {
                            blockError = innerPoolError;
                            @throw [NSException exceptionWithName:CDEException reason:@"" userInfo:nil];
                        }
                    }
                }
            }
        }
        @catch (NSException *e) {
            success = NO;
            methodError = blockError;
        }
        
        // In a full integration, remove any objects that didn't get inserted
        if (success && needFullIntegration) [self deleteUnreferencedObjectsInObjectIDsByEntity:insertedObjectIDsByEntity];
    }];
    
    if (error) *error = methodError;
    
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


#pragma mark Tracking Deletions of Unreferenced Objects in Full Integrations

- (void)updateObjectIDsByEntity:(NSMutableDictionary *)objectIDsByEntity forEntity:(NSEntityDescription *)entity insertChanges:(NSArray *)changes
{
    NSMutableSet *objectIDs = objectIDsByEntity[entity.name];
    if (!objectIDs) objectIDs = [NSMutableSet set];
    NSArray *storeURIs = [changes valueForKeyPath:@"globalIdentifier.storeURI"];
    [managedObjectContext performBlockAndWait:^{
        for (NSString *uri in storeURIs) {
            NSURL *url = [NSURL URLWithString:uri];
            NSManagedObjectID *objectID = [managedObjectContext.persistentStoreCoordinator managedObjectIDForURIRepresentation:url];
            if (objectID) [objectIDs addObject:objectID];
        }
    }];
    objectIDsByEntity[entity.name] = objectIDs;
}

- (void)deleteUnreferencedObjectsInObjectIDsByEntity:(NSDictionary *)objectIDsByEntity
{
    [managedObjectContext performBlockAndWait:^{
        [objectIDsByEntity enumerateKeysAndObjectsUsingBlock:^(NSString *entityName, NSSet *objectIDs, BOOL *stop) {
            NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:entityName];
            fetch.includesSubentities = NO;
            fetch.predicate = [NSPredicate predicateWithFormat:@"NOT (SELF IN %@)", objectIDs];
            NSError *error;
            NSArray *unreferencedObjects = [managedObjectContext executeFetchRequest:fetch error:&error];
            for (NSManagedObject *object in unreferencedObjects) {
                [self nullifyRelationshipsAndDeleteObject:object];
            }
        }];
    }];
}


#pragma mark Applying Insertions

// Called on event context queue
- (BOOL)insertObjectsForEntity:(NSEntityDescription *)entity objectChanges:(NSArray *)insertChanges error:(NSError * __autoreleasing *)error
{
    // Determine which insertions actually need new objects. Some may already have
    // objects due to insertions on other devices.
    NSMutableArray *urisForInsertChanges = [[NSMutableArray alloc] initWithCapacity:insertChanges.count];
    for (CDEObjectChange *change in insertChanges) {
        NSURL *url = nil;
        if (change.globalIdentifier.storeURI) url = [[NSURL alloc] initWithString:change.globalIdentifier.storeURI];
        [urisForInsertChanges addObject:CDENilToNSNull(url)];
    }
    
    NSMutableArray *indexesNeedingNewObjects = [[NSMutableArray alloc] initWithCapacity:insertChanges.count];
    [managedObjectContext performBlockAndWait:^{
        [urisForInsertChanges enumerateObjectsUsingBlock:^(NSURL *url, NSUInteger i, BOOL *stop) {
            BOOL objectNeedsCreating = NO;
            if (url == (id)[NSNull null]) {
                objectNeedsCreating = YES;
            }
            else {
                NSManagedObjectID *objectID = [managedObjectContext.persistentStoreCoordinator managedObjectIDForURIRepresentation:url];
                NSManagedObject *object = objectID ? [managedObjectContext existingObjectWithID:objectID error:NULL] : nil;
                objectNeedsCreating = !object || object.isDeleted || nil == object.managedObjectContext;
            }
            if (objectNeedsCreating) [indexesNeedingNewObjects addObject:@(i)];
        }];
    }];
    
    NSArray *changesNeedingNewObjects = [indexesNeedingNewObjects cde_arrayByTransformingObjectsWithBlock:^id(NSNumber *index) {
        return insertChanges[index.unsignedIntegerValue];
    }];
    
    // Only now actually create objects, on the main context queue
    NSMutableArray *newObjects = [[NSMutableArray alloc] initWithCapacity:changesNeedingNewObjects.count];
    __block BOOL success = YES;
    __block NSError *methodError = nil;
    NSUInteger numberOfNewObjects = changesNeedingNewObjects.count;
    [managedObjectContext performBlockAndWait:^{
        for (NSUInteger i = 0; i < numberOfNewObjects; i++) {
            id newObject = [NSEntityDescription insertNewObjectForEntityForName:entity.name inManagedObjectContext:managedObjectContext];
            if (!newObject) {
                NSError *localError = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeUnknown userInfo:nil];
                methodError = localError;
                success = NO;
                return;
            }
            [newObjects addObject:newObject];
        }
    }];
    if (error) *error = methodError;
    if (!success) return NO;
    
    // Get permanent store object ids, and then URIs
    __block NSArray *uris;
    [managedObjectContext performBlockAndWait:^{
        NSError *localError = nil;
        success = [managedObjectContext obtainPermanentIDsForObjects:newObjects error:&localError];
        if (!success) {
            methodError = localError;
            return;
        }
        
        uris = [newObjects valueForKeyPath:@"objectID.URIRepresentation.absoluteString"];
    }];
    if (error) *error = methodError;
    if (!success) return NO;
    
    // Update the global ids with the store object ids
    NSArray *globalIds = [changesNeedingNewObjects valueForKeyPath:@"globalIdentifier"];
    [globalIds enumerateObjectsUsingBlock:^(CDEGlobalIdentifier *globalId, NSUInteger i, BOOL *stop) {
        NSString *uri = uris[i];
        globalId.storeURI = uri;
    }];
    
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

        [managedObjectContext performBlockAndWait:^{
            [self nullifyRelationshipsAndDeleteObject:object];
        }];
    }
    
    return YES;
}

// Called on managedObjectContext thread
- (void)nullifyRelationshipsAndDeleteObject:(NSManagedObject *)object
{
    if (!object) return;
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
}


#pragma mark Applying Property Changes

// Called on event child context queue
- (BOOL)applyObjectPropertyChanges:(NSArray *)changes error:(NSError * __autoreleasing *)error
{
    if (changes.count == 0) return YES;
    
    NSMapTable *objectsByGlobalId = [self fetchObjectsByGlobalIdentifierForObjectChanges:changes error:error];
    if (!objectsByGlobalId) return NO;
    
    NSMapTable *globalIdsByObject = [NSMapTable cde_strongToStrongObjectsMapTable];
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
        if (error) *error = [[NSError alloc] initWithDomain:CDEErrorDomain code:CDEErrorCodeUnknown userInfo:@{NSLocalizedFailureReasonErrorKey:exception.reason}];
        return NO;
    }
    
    return YES;
}

// Called on main context queue
- (void)applyAttributeChanges:(NSArray *)properyChangeValues toObject:(NSManagedObject *)object
{
    NSEntityDescription *entity = object.entity;
    for (CDEPropertyChangeValue *changeValue in properyChangeValues) {
        NSAttributeDescription *attribute = entity.attributesByName[changeValue.propertyName];
        if (!attribute) {
            // Likely attribute removed from model since change
            CDELog(CDELoggingLevelWarning, @"Attribute from change value not in model: %@", changeValue.propertyName);
            continue;
        }
        
        changeValue.eventStore = self.eventStore; // Needed to retrieve data files
        id newValue = [changeValue attributeValueForAttributeDescription:attribute];
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
            if (removedObject) [relatedObjects removeObject:removedObject];
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
        NSMapTable *finalIndexesByObject = [NSMapTable cde_strongToStrongObjectsMapTable];
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
            if (removedObject) [relatedObjects removeObject:removedObject];
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
    CDELog(CDELoggingLevelVerbose, @"Repairing context after integrating changes");

    // Give opportunity to merge/repair changes in a child context.
    // We can then retrieve the changes and generate a new store mod event to represent the merge.
    __block BOOL merged = YES;
    __block BOOL contextHasChanges = NO;
    __block NSError *methodError;
    
    [managedObjectContext performBlockAndWait:^{
        contextHasChanges = managedObjectContext.hasChanges;
    }];
    
    if (contextHasChanges && shouldSaveBlock) {
        // Setup a context to store repairs
        NSManagedObjectContext *reparationContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
        [reparationContext performBlockAndWait:^{
            reparationContext.parentContext = managedObjectContext;
        }];
        
        // Call block on the saving context queue
        BOOL shouldSave = shouldSaveBlock(managedObjectContext, reparationContext);
        if (!shouldSave) {
            if (error) *error = [[NSError alloc] initWithDomain:CDEErrorDomain code:CDEErrorCodeCancelled userInfo:nil];
            return NO;
        }
        
        // Capture changes in the reparation context in the merge event.
        // Save any changes made in the reparation context.
        [reparationContext performBlockAndWait:^{
            if (reparationContext.hasChanges) {
                NSError *localError = nil;
                BOOL success = [eventBuilder addChangesForUnsavedManagedObjectContext:reparationContext error:&localError];
                if (!success) {
                    methodError = localError;
                    merged = NO;
                    return;
                }

                merged = [reparationContext save:&localError];
                methodError = localError;
                if (!merged) CDELog(CDELoggingLevelError, @"Saving merge context after willSave changes failed: %@", *error);
            }
        }];
    }
    
    if (error) *error = methodError;
    
    return merged;
}

// Call on event context queue
- (NSArray *)fetchObjectChangesOfType:(CDEObjectChangeType)type fromStoreModificationEvents:(id <NSFastEnumeration>)events forEntity:(NSEntityDescription *)entity error:(NSError * __autoreleasing *)error;
{
    NSArray *result = nil;
    NSError *methodError = nil;
    @autoreleasepool {
        NSError *localError = nil;
        NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"CDEObjectChange"];
        fetch.predicate = [NSPredicate predicateWithFormat:@"nameOfEntity = %@ && type = %d && storeModificationEvent in %@", entity.name, type, events];
        fetch.sortDescriptors = [self objectChangeSortDescriptors];
        fetch.relationshipKeyPathsForPrefetching = @[@"globalIdentifier"];
        result = [self.eventStore.managedObjectContext executeFetchRequest:fetch error:&localError];
        methodError = localError;
    }
    if (error) *error = methodError;
    return result;
}


#pragma mark Fetching from Synced Store

- (NSMapTable *)fetchObjectsByGlobalIdentifierForEntityName:(NSString *)entityName globalIdentifiers:(id)globalIdentifiers error:(NSError * __autoreleasing *)error
{
    // Setup mappings between types of identifiers
    NSPersistentStoreCoordinator *coordinator = managedObjectContext.persistentStoreCoordinator;
    NSMutableSet *objectIDs = [[NSMutableSet alloc] initWithCapacity:[globalIdentifiers count]];
    NSMapTable *objectIDByGlobalId = [NSMapTable cde_strongToStrongObjectsMapTable];
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
    __block NSError *methodError = nil;
    [managedObjectContext performBlockAndWait:^{
        NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:entityName];
        fetch.predicate = [NSPredicate predicateWithFormat:@"SELF IN %@", objectIDs];
        fetch.includesSubentities = NO;
        NSError *localError = nil;
        objects = [managedObjectContext executeFetchRequest:fetch error:&localError];
        objectIDsOfFetched = [objects valueForKeyPath:@"objectID"];
        methodError = localError;
    }];
    if (error) *error = methodError;
    if (!objects) return nil;
    
    // ObjectID to object mapping
    NSDictionary *objectByObjectID = [[NSDictionary alloc] initWithObjects:objects forKeys:objectIDsOfFetched];
    
    // Prepare results
    NSMapTable *result = [NSMapTable cde_strongToStrongObjectsMapTable];
    for (CDEGlobalIdentifier *globalId in globalIdentifiers) {
        NSManagedObjectID *objectID = [objectIDByGlobalId objectForKey:globalId];
        [result setObject:objectByObjectID[objectID] forKey:globalId];
    }
    
    return result;
}

// Called on event store context
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
    
    NSMapTable *result = [NSMapTable cde_strongToStrongObjectsMapTable];
    [result cde_addEntriesFromMapTable:changeObjectsByIdString];
    [result cde_addEntriesFromMapTable:relatedOrderedObjectsByIdString];
    
    return result;
}

- (NSMapTable *)fetchObjectsByIdStringForRelatedObjectsInOrderedRelationshipsOfObjectChanges:(id)objectChanges
{
    NSMapTable *changedOrderedPropertiesByGlobalId = [NSMapTable cde_strongToStrongObjectsMapTable];
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
    NSArray *globalIds = [CDEGlobalIdentifier fetchGlobalIdentifiersForObjectIDs:objectIDs inManagedObjectContext:self.eventStore.managedObjectContext];

    NSMapTable *relatedObjectsByGlobalId = [NSMapTable cde_strongToStrongObjectsMapTable];
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
    NSMapTable *results = [NSMapTable cde_strongToStrongObjectsMapTable];
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
    NSArray *globalIds = [self.eventStore.managedObjectContext executeFetchRequest:fetch error:&error];
    if (!globalIds) CDELog(CDELoggingLevelError, @"Error fetching ids: %@", error);
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
    CDELog(CDELoggingLevelVerbose, @"Committing merge changes to store");

    __block BOOL saved = [self saveContext:error];
    __block NSError *methodError = nil;
    if (!saved && !saveOccurredDuringMerge) {
        if ((*error).code != NSManagedObjectMergeError && failedSaveBlock) {
            // Setup a child reparation context
            NSManagedObjectContext *reparationContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
            [reparationContext performBlockAndWait:^{
                reparationContext.parentContext = managedObjectContext;
            }];
            
            // Inform of failure, and give chance to repair
            BOOL retry = failedSaveBlock(managedObjectContext, *error, reparationContext);
            
            // If repairs were carried out, add changes to the merge event, and save
            // reparation context
            __block BOOL needExtraSave = NO;
            __block BOOL success = YES;
            [reparationContext performBlockAndWait:^{
                if (retry && reparationContext.hasChanges) {
                    NSError *localError = nil;
                    success = [eventBuilder addChangesForUnsavedManagedObjectContext:reparationContext error:&localError];
                    success = success && [reparationContext save:&localError];
                    methodError = localError;
                    if (success) needExtraSave = YES;
                }
            }];
            
            // Retry save if necessary
            if (success) {
                NSError *localError = nil;
                if (needExtraSave) saved = [self saveContext:&localError];
                methodError = localError;
            }
        }
    }
    
    if (error) *error = methodError;
    
    return saved;
}

// Call from any queue
- (BOOL)saveContext:(NSError * __autoreleasing *)error
{
    __block BOOL saved = NO;
    __block NSError *localError;
    
    [managedObjectContext performBlockAndWait:^{
        NSError *blockError;
        if (saveOccurredDuringMerge) {
            blockError = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeSaveOccurredDuringMerge userInfo:nil];
            localError = blockError;
            return;
        }
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(storeChangesFromContextDidSaveNotification:) name:NSManagedObjectContextDidSaveNotification object:managedObjectContext];
        saved = [managedObjectContext save:&blockError];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:NSManagedObjectContextDidSaveNotification object:managedObjectContext];
        
        if (!saved) {
            localError = blockError;
        }
    }];
    
    if (error) *error = localError;
    
    return saved;
}


- (void)storeChangesFromContextDidSaveNotification:(NSNotification *)notif
{
    saveInfoDictionary = notif.userInfo;
}

@end
