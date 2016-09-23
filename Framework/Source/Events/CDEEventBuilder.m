//
//  CDEEventFactory.m
//  Ensembles
//
//  Created by Drew McCormack on 22/09/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import "CDEEventBuilder.h"
#import "NSManagedObjectModel+CDEAdditions.h"
#import "CDEPersistentStoreEnsemble.h"
#import "CDEEventStore.h"
#import "CDEStoreModificationEvent.h"
#import "CDEDefines.h"
#import "CDEFoundationAdditions.h"
#import "CDEPropertyChangeValue.h"
#import "CDEGlobalIdentifier.h"
#import "CDEObjectChange.h"
#import "CDEEventRevision.h"
#import "CDERevisionSet.h"
#import "CDERevision.h"
#import "CDERevisionManager.h"

@implementation CDEEventBuilder 

@synthesize event = event;
@synthesize eventStore = eventStore;
@synthesize eventManagedObjectContext = eventManagedObjectContext;
@synthesize eventType = eventType;

#pragma mark - Initialization

- (id)initWithEventStore:(CDEEventStore *)newStore eventManagedObjectContext:(NSManagedObjectContext *)newContext
{
    self = [super init];
    if (self) {
        eventStore = newStore;
        eventManagedObjectContext = newContext;
        eventType = CDEStoreModificationEventTypeIncomplete;
    }
    return self;
}

- (id)initWithEventStore:(CDEEventStore *)newStore
{
    return [self initWithEventStore:newStore eventManagedObjectContext:newStore.managedObjectContext];
}

#pragma mark - Making New Events

- (CDERevision *)makeNewEventOfType:(CDEStoreModificationEventType)type uniqueIdentifier:(NSString *)uniqueIdOrNil
{
    __block CDERevision *returnRevision = nil;
    [eventManagedObjectContext performBlockAndWait:^{
        eventType = type;
        
        CDERevisionNumber lastRevision = eventStore.lastRevisionSaved;
        NSString *persistentStoreId = self.eventStore.persistentStoreIdentifier;

        CDERevisionManager *revisionManager = [[CDERevisionManager alloc] initWithEventStore:eventStore];
        revisionManager.managedObjectModelURL = self.ensemble.managedObjectModelURL;
        CDEGlobalCount globalCountBeforeMakingEvent = [revisionManager maximumGlobalCount];

        event = [NSEntityDescription insertNewObjectForEntityForName:@"CDEStoreModificationEvent" inManagedObjectContext:eventManagedObjectContext];
        
        event.type = CDEStoreModificationEventTypeIncomplete;
        event.timestamp = [NSDate timeIntervalSinceReferenceDate];
        event.globalCount = globalCountBeforeMakingEvent+1;
        event.modelVersion = [self.ensemble.managedObjectModel cde_entityHashesPropertyList];
        if (uniqueIdOrNil) event.uniqueIdentifier = uniqueIdOrNil;
        
        CDEEventRevision *revision = [NSEntityDescription insertNewObjectForEntityForName:@"CDEEventRevision" inManagedObjectContext:eventManagedObjectContext];
        revision.persistentStoreIdentifier = persistentStoreId;
        revision.revisionNumber = lastRevision+1;
        revision.storeModificationEvent = event;
        
        // Set the state of other stores
        if (eventType == CDEStoreModificationEventTypeSave) {
            CDERevisionSet *newRevisionSet = [revisionManager revisionSetForLastMergeOrBaseline];
            [newRevisionSet removeRevisionForPersistentStoreIdentifier:persistentStoreId];
            event.revisionSetOfOtherStoresAtCreation = newRevisionSet;
        }
        else if (eventType == CDEStoreModificationEventTypeMerge) {
            CDERevisionSet *mostRecentSet = [revisionManager revisionSetOfMostRecentEvents];
            [mostRecentSet removeRevisionForPersistentStoreIdentifier:persistentStoreId];
            event.revisionSetOfOtherStoresAtCreation = mostRecentSet;
        }
        
        [eventManagedObjectContext processPendingChanges];
        if (persistentStoreId) returnRevision = [event.revisionSet revisionForPersistentStoreIdentifier:persistentStoreId];
    }];
    
    return returnRevision;
}

- (void)finalizeNewEvent
{
    [eventManagedObjectContext performBlockAndWait:^{
        event.type = eventType;
    }];
}

#pragma mark - Modifying Events

- (void)performBlockAndWait:(CDECodeBlock)block
{
    [eventManagedObjectContext performBlockAndWait:block];
}

#pragma mark - Insertion Object Changes

- (void)addChangesForInsertedObjects:(NSSet *)insertedObjects objectsAreSaved:(BOOL)saved inManagedObjectContext:(NSManagedObjectContext *)context
{
    if (insertedObjects.count == 0) return;
    
    // This method must be called on context thread
    NSMutableDictionary *changesData = [[self changesDataForInsertedObjects:insertedObjects objectsAreSaved:saved inManagedObjectContext:context] mutableCopy];
    NSArray *globalIds = [self addGlobalIdentifiersForInsertChangesData:changesData];
    changesData[@"globalIds"] = globalIds;

    // Add changes
    [self addInsertChangesForChangesData:changesData];
}

- (NSDictionary *)changesDataForInsertedObjects:(NSSet *)insertedObjects objectsAreSaved:(BOOL)saved inManagedObjectContext:(NSManagedObjectContext *)context
{
    // Created property value change objects from the inserted objects
    __block NSMutableArray *changeArrays = nil;
    __block NSMutableArray *entityNames = nil;
    __block NSArray *globalIdStrings = nil;
    
    // Create block to make property change values from the objects
    CDECodeBlock block = ^{
        @autoreleasepool {
            changeArrays = [NSMutableArray arrayWithCapacity:insertedObjects.count];
            entityNames = [NSMutableArray array];
            
            NSArray *orderedInsertedObjects = insertedObjects.allObjects;
            [orderedInsertedObjects cde_enumerateObjectsDrainingEveryIterations:50 usingBlock:^(NSManagedObject *object, NSUInteger index, BOOL *stop) {
                NSArray *propertyChanges = [CDEPropertyChangeValue propertyChangesForObject:object eventStore:self.eventStore propertyNames:object.entity.propertiesByName.allKeys isPreSave:!saved storeValues:YES];
                if (!propertyChanges) return;
                
                [changeArrays addObject:propertyChanges];
                [entityNames addObject:object.entity.name];
            }];
            
            // Get global id strings on context thread
            globalIdStrings = [[self.ensemble globalIdentifiersForManagedObjects:orderedInsertedObjects] copy];
        }
    };
    
    // Execute the block on the context's thread
    if (context.concurrencyType != NSConfinementConcurrencyType)
        [context performBlockAndWait:block];
    else
        block();
    
    // Make global ids for all objects before creating object changes.
    // We need all global ids to exist before trying to store relationships which utilize global ids.
    NSDictionary *changesData = @{@"changeArrays" : changeArrays, @"entityNames" : entityNames, @"globalIdStrings" : (globalIdStrings ? : [NSNull null])};
    return changesData;
}

- (void)addInsertChangesForChangesData:(NSDictionary *)changesData
{
    // Build the event from the property changes on the event store thread
    [eventManagedObjectContext performBlockAndWait:^{
        NSArray *changeArrays = changesData[@"changeArrays"];
        NSArray *entityNames = changesData[@"entityNames"];
        NSArray *globalIds = changesData[@"globalIds"];
        
        // Now that all global ids exist, create object changes
        __block NSUInteger i = 0;
        [changeArrays cde_enumerateObjectsDrainingEveryIterations:50 usingBlock:^(NSArray *propertyChanges, NSUInteger index, BOOL *stop) {
            CDEGlobalIdentifier *newGlobalId = globalIds[i];
            NSString *entityName = entityNames[i];
            [self addObjectChangeOfType:CDEObjectChangeTypeInsert forGlobalIdentifier:newGlobalId entityName:entityName propertyChanges:propertyChanges];
            i++;
        }];
    }];
}

- (NSArray *)addGlobalIdentifiersForInsertChangesData:(NSDictionary *)changesData
{
    __block NSArray *returnArray = nil;
    [eventManagedObjectContext performBlockAndWait:^{
        NSArray *changeArrays = changesData[@"changeArrays"];
        NSArray *entityNames = changesData[@"entityNames"];
        NSArray *globalIdStrings = CDENSNullToNil(changesData[@"globalIdStrings"]);
        
        // Retrieve existing global identifiers
        NSArray *existingGlobalIdentifiers = nil;
        if (globalIdStrings) {
            existingGlobalIdentifiers = [CDEGlobalIdentifier fetchGlobalIdentifiersForIdentifierStrings:globalIdStrings withEntityNames:entityNames inManagedObjectContext:eventManagedObjectContext];
        }
        
        NSMutableArray *globalIds = [[NSMutableArray alloc] init];
        __block NSUInteger i = 0;
        [changeArrays cde_enumerateObjectsDrainingEveryIterations:50 usingBlock:^(NSArray *propertyChanges, NSUInteger index, BOOL *stop) {
            NSString *entityName = entityNames[i];
            NSString *globalIdString = CDENSNullToNil(globalIdStrings[i]);
            CDEGlobalIdentifier *existingGlobalIdentifier = CDENSNullToNil(existingGlobalIdentifiers[i]);
            i++;
            
            CDEGlobalIdentifier *newGlobalId = existingGlobalIdentifier;
            if (!newGlobalId) {
                newGlobalId = [NSEntityDescription insertNewObjectForEntityForName:@"CDEGlobalIdentifier" inManagedObjectContext:eventManagedObjectContext];
                newGlobalId.nameOfEntity = entityName;
                if (globalIdString) newGlobalId.globalIdentifier = globalIdString;
            }
            
            CDEPropertyChangeValue *propertyChange = propertyChanges.lastObject;
            newGlobalId.storeURI = propertyChange.objectID.URIRepresentation.absoluteString;
            
            [globalIds addObject:newGlobalId];
        }];
        
        returnArray = globalIds;
        
        NSError *error;
        if (![eventManagedObjectContext save:&error]) CDELog(CDELoggingLevelError, @"Error saving event store: %@", error);
    }];
    return returnArray;
}

#pragma mark - Deletion Object Changes

- (void)addChangesForDeletedObjects:(NSSet *)deletedObjects inManagedObjectContext:(NSManagedObjectContext *)context
{
    if (deletedObjects.count == 0) return;
    
    NSDictionary *changesData = [self changesDataForDeletedObjects:deletedObjects inManagedObjectContext:context];
    [self addDeleteChangesForChangesData:changesData];
}

- (NSDictionary *)changesDataForDeletedObjects:(NSSet *)deletedObjects inManagedObjectContext:(NSManagedObjectContext *)context
{
    __block NSArray *orderedObjectIDs = nil;
    
    CDECodeBlock block = ^{
        NSSet *deletedObjectIds = [deletedObjects valueForKeyPath:@"objectID"];
        orderedObjectIDs = deletedObjectIds.allObjects;
    };
    
    // Execute the block on the context's thread
    if (context.concurrencyType != NSConfinementConcurrencyType)
        [context performBlockAndWait:block];
    else
        block();
    
    return @{@"orderedObjectIDs": orderedObjectIDs};
}

- (void)addDeleteChangesForChangesData:(NSDictionary *)changesData
{
    [eventManagedObjectContext performBlockAndWait:^{
        NSArray *orderedObjectIDs = changesData[@"orderedObjectIDs"];
        NSArray *globalIds = [CDEGlobalIdentifier fetchGlobalIdentifiersForObjectIDs:orderedObjectIDs inManagedObjectContext:eventManagedObjectContext];
        [globalIds enumerateObjectsUsingBlock:^(CDEGlobalIdentifier *globalId, NSUInteger i, BOOL *stop) {
            NSManagedObjectID *objectID = orderedObjectIDs[i];
            
            if (globalId == (id)[NSNull null]) {
                CDELog(CDELoggingLevelError, @"Deleted object with no global identifier. This can be due to creating and deleting two separate objects with the same global id in a single save operation. ObjectID: %@", objectID);
                return;
            }
            
            CDEObjectChange *change = [NSEntityDescription insertNewObjectForEntityForName:@"CDEObjectChange" inManagedObjectContext:eventManagedObjectContext];
            change.storeModificationEvent = self.event;
            change.type = CDEObjectChangeTypeDelete;
            change.nameOfEntity = objectID.entity.name;
            change.globalIdentifier = globalId;
        }];
    }];
}

#pragma mark - Update Object Changes

- (void)addChangesForUpdatedObjects:(NSSet *)updatedObjects inManagedObjectContext:(NSManagedObjectContext *)context options:(CDEUpdateStoreOption)options propertyChangeValuesByObjectID:(NSDictionary *)propertyChangeValuesByObjectID
{
    if (updatedObjects.count == 0) return;
    
    NSDictionary *changesData = [self changesDataForUpdatedObjects:updatedObjects inManagedObjectContext:context options:options propertyChangeValuesByObjectID:propertyChangeValuesByObjectID];
    [self addUpdateChangesForChangesData:changesData];
}

- (NSDictionary *)changesDataForUpdatedObjects:(NSSet *)updatedObjects inManagedObjectContext:(NSManagedObjectContext *)context options:(CDEUpdateStoreOption)options propertyChangeValuesByObjectID:(NSDictionary *)propertyChangeValuesByObjectID
{
    // Determine what needs to be stored
    BOOL storePreSaveInfo = (CDEUpdateStoreOptionPreSaveInfo & options);
    BOOL storeUnsavedValues = (CDEUpdateStoreOptionUnsavedValue & options);
    BOOL storeSavedValues = (CDEUpdateStoreOptionSavedValue & options);
    NSAssert(!(storePreSaveInfo && storeSavedValues), @"Cannot store pre-save info and saved values");
    NSAssert(!(storeUnsavedValues && storeSavedValues), @"Cannot store unsaved values and saved values");
    
    // Can't access objects in background, so just pass ids
    __block NSArray *objectIDs = nil;
    CDECodeBlock block = ^{
        NSArray *objects = [updatedObjects allObjects];
        
        // Update property changes with saved values
        BOOL isPreSave = storePreSaveInfo || storeUnsavedValues;
        BOOL storeValues = storeUnsavedValues || storeSavedValues;
        NSMutableArray *newObjectIDs = [[NSMutableArray alloc] initWithCapacity:objects.count];
        for (NSManagedObject *object in objects) {
            NSManagedObjectID *objectID = object.objectID;
            NSArray *propertyChanges = propertyChangeValuesByObjectID[objectID];
            if(propertyChanges.count > 0) {
                [newObjectIDs addObject:objectID];
                for (CDEPropertyChangeValue *propertyChangeValue in propertyChanges) {
                    [propertyChangeValue updateWithObject:object isPreSave:isPreSave storeValues:storeValues];
                }
            }
        }
        objectIDs = newObjectIDs;
    };
    
    if (context.concurrencyType != NSConfinementConcurrencyType)
        [context performBlockAndWait:block];
    else
        block();
    
    return @{@"objectIDs" : objectIDs, @"persistentStoreCoordinator" : context.persistentStoreCoordinator, @"propertyChangeValuesByObjectID" : (propertyChangeValuesByObjectID ? : [NSNull null])};
}

- (void)addUpdateChangesForChangesData:(NSDictionary *)changesData
{
    [eventManagedObjectContext performBlockAndWait:^{
        NSArray *objectIDs = changesData[@"objectIDs"];
        NSPersistentStoreCoordinator *coordinator = changesData[@"persistentStoreCoordinator"];
        NSDictionary *propertyChangeValuesByObjectID = CDENSNullToNil(changesData[@"propertyChangeValuesByObjectID"]);
        
        [(id)coordinator lock];
        
        NSArray *globalIds = [CDEGlobalIdentifier fetchGlobalIdentifiersForObjectIDs:objectIDs inManagedObjectContext:eventManagedObjectContext];
        [globalIds cde_enumerateObjectsDrainingEveryIterations:50 usingBlock:^(CDEGlobalIdentifier *globalId, NSUInteger index, BOOL *stop) {
            if ((id)globalId == [NSNull null]) {
                CDELog(CDELoggingLevelWarning, @"Tried to store updates for object with no global identifier. Skipping.");
                return;
            }
            
            NSURL *uri = [NSURL URLWithString:globalId.storeURI];
            NSManagedObjectID *objectID = [coordinator managedObjectIDForURIRepresentation:uri];
            NSArray *propertyChanges = [propertyChangeValuesByObjectID objectForKey:objectID];
            if (!propertyChanges) return;
            
            [self addObjectChangeOfType:CDEObjectChangeTypeUpdate forGlobalIdentifier:globalId entityName:objectID.entity.name propertyChanges:propertyChanges];
        }];
        
        [(id)coordinator unlock];
    }];
}

- (void)addChangesForUnsavedUpdatedObjects:(NSSet *)updatedObjects inManagedObjectContext:(NSManagedObjectContext *)context
{
    if (updatedObjects.count == 0) return;
    
    __block NSMutableDictionary *changedValuesByObjectID = nil;
    NSManagedObjectContext *updatedObjectsContext = context;
    [updatedObjectsContext performBlockAndWait:^{
        changedValuesByObjectID = [NSMutableDictionary dictionaryWithCapacity:updatedObjects.count];
        [updatedObjects.allObjects cde_enumerateObjectsDrainingEveryIterations:50 usingBlock:^(NSManagedObject *object, NSUInteger index, BOOL *stop) {
            NSArray *propertyChanges = [CDEPropertyChangeValue propertyChangesForObject:object eventStore:self.eventStore propertyNames:object.changedValues.allKeys isPreSave:YES storeValues:YES];
            NSManagedObjectID *objectID = object.objectID;
            changedValuesByObjectID[objectID] = propertyChanges;
        }];
    }];
    
    [self addChangesForUpdatedObjects:updatedObjects inManagedObjectContext:context options:(CDEUpdateStoreOptionPreSaveInfo | CDEUpdateStoreOptionUnsavedValue) propertyChangeValuesByObjectID:changedValuesByObjectID];
}

- (BOOL)addChangesForUnsavedManagedObjectContext:(NSManagedObjectContext *)contextWithChanges error:(NSError * __autoreleasing *)error
{
    __block BOOL success = NO;
    success = [contextWithChanges obtainPermanentIDsForObjects:contextWithChanges.insertedObjects.allObjects error:error];
    if (!success) return NO;

    [self addChangesForInsertedObjects:contextWithChanges.insertedObjects objectsAreSaved:NO inManagedObjectContext:contextWithChanges];
    [self addChangesForDeletedObjects:contextWithChanges.deletedObjects inManagedObjectContext:contextWithChanges];
    [self addChangesForUnsavedUpdatedObjects:contextWithChanges.updatedObjects inManagedObjectContext:contextWithChanges];
    
    return YES;
}

#pragma mark Converting property changes for storage in event store

- (void)addObjectChangeOfType:(CDEObjectChangeType)type forGlobalIdentifier:(CDEGlobalIdentifier *)globalId entityName:(NSString *)entityName propertyChanges:(NSArray *)propertyChanges
{
    NSParameterAssert(type == CDEObjectChangeTypeInsert || type == CDEObjectChangeTypeUpdate);
    NSParameterAssert(globalId != nil);
    NSParameterAssert(entityName != nil);
    NSParameterAssert(propertyChanges != nil);
    NSAssert(self.event, @"No event created. Call makeNewEvent first.");
    
    CDEObjectChange *objectChange = [NSEntityDescription insertNewObjectForEntityForName:@"CDEObjectChange" inManagedObjectContext:eventManagedObjectContext];
    objectChange.storeModificationEvent = self.event;
    objectChange.type = type;
    objectChange.nameOfEntity = entityName;
    objectChange.globalIdentifier = globalId;
    
    // Fetch the needed global ids 
    NSMutableSet *objectIDs = [[NSMutableSet alloc] initWithCapacity:propertyChanges.count];
    for (CDEPropertyChangeValue *propertyChange in propertyChanges) {
        if (propertyChange.relatedIdentifier) [objectIDs addObject:propertyChange.relatedIdentifier];
        if (propertyChange.addedIdentifiers) [objectIDs unionSet:propertyChange.addedIdentifiers];
        if (propertyChange.removedIdentifiers) [objectIDs unionSet:propertyChange.removedIdentifiers];
        if (propertyChange.movedIdentifiersByIndex) [objectIDs addObjectsFromArray:propertyChange.movedIdentifiersByIndex.allValues];
    }
    [objectIDs removeObject:[NSNull null]];
    NSArray *orderedObjectIDs = objectIDs.allObjects;
    NSArray *globalIds = [CDEGlobalIdentifier fetchGlobalIdentifiersForObjectIDs:orderedObjectIDs inManagedObjectContext:globalId.managedObjectContext];
    NSDictionary *globalIdentifiersByObjectID = [NSDictionary dictionaryWithObjects:globalIds forKeys:orderedObjectIDs];
    
    for (CDEPropertyChangeValue *propertyChange in propertyChanges) {
        [self convertRelationshipValuesToGlobalIdentifiersInPropertyChangeValue:propertyChange withGlobalIdentifiersByObjectID:globalIdentifiersByObjectID];
    }
    
    objectChange.propertyChangeValues = propertyChanges;
}

- (void)convertRelationshipValuesToGlobalIdentifiersInPropertyChangeValue:(CDEPropertyChangeValue *)propertyChange withGlobalIdentifiersByObjectID:(NSDictionary *)globalIdentifiersByObjectID
{
    switch (propertyChange.type) {
        case CDEPropertyChangeTypeToOneRelationship:
            [self convertToOneRelationshipValuesToGlobalIdentifiersInPropertyChangeValue:propertyChange withGlobalIdentifiersByObjectID:globalIdentifiersByObjectID];
            break;
            
        case CDEPropertyChangeTypeOrderedToManyRelationship:
        case CDEPropertyChangeTypeToManyRelationship:
            [self convertToManyRelationshipValuesToGlobalIdentifiersInPropertyChangeValue:propertyChange withGlobalIdentifiersByObjectID:globalIdentifiersByObjectID];
            break;
            
        case CDEPropertyChangeTypeAttribute:
        default:
            break;
    }
}

- (void)convertToOneRelationshipValuesToGlobalIdentifiersInPropertyChangeValue:(CDEPropertyChangeValue *)propertyChange withGlobalIdentifiersByObjectID:(NSDictionary *)globalIdentifiersByObjectID
{
    CDEGlobalIdentifier *globalId = nil;
    globalId = globalIdentifiersByObjectID[propertyChange.relatedIdentifier];
    if (propertyChange.relatedIdentifier && !globalId) {
        CDELog(CDELoggingLevelError, @"No global id found for to-one relationship with target objectID: %@", propertyChange.relatedIdentifier);
    }
    propertyChange.relatedIdentifier = globalId.globalIdentifier;
}

- (void)convertToManyRelationshipValuesToGlobalIdentifiersInPropertyChangeValue:(CDEPropertyChangeValue *)propertyChange withGlobalIdentifiersByObjectID:(NSDictionary *)globalIdentifiersByObjectID
{
    static NSPredicate *notNullPredicate = nil;
    static NSString *globalIdIsNullErrorMessage = @"Missing global ids for added ids in a to-many relationship. This is usually caused by saving multiple objects with the same global id at once.";
    if (!notNullPredicate) notNullPredicate = [NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
        return evaluatedObject != [NSNull null];
    }];
    
    NSArray *addedGlobalIdentifiers = [globalIdentifiersByObjectID objectsForKeys:propertyChange.addedIdentifiers.allObjects notFoundMarker:[NSNull null]];
    BOOL containsNull = [addedGlobalIdentifiers containsObject:[NSNull null]];
    if (containsNull) {
        addedGlobalIdentifiers = [addedGlobalIdentifiers filteredArrayUsingPredicate:notNullPredicate];
        CDELog(CDELoggingLevelError, @"%@", globalIdIsNullErrorMessage);
    }
    
    NSArray *removedGlobalIdentifiers = [globalIdentifiersByObjectID objectsForKeys:propertyChange.removedIdentifiers.allObjects notFoundMarker:[NSNull null]];
    containsNull = [removedGlobalIdentifiers containsObject:[NSNull null]];
    if (containsNull) {
        removedGlobalIdentifiers = [removedGlobalIdentifiers filteredArrayUsingPredicate:notNullPredicate];
        CDELog(CDELoggingLevelError, @"%@", globalIdIsNullErrorMessage);
    }
    
    propertyChange.addedIdentifiers = [NSSet setWithArray:[addedGlobalIdentifiers valueForKeyPath:@"globalIdentifier"]];
    propertyChange.removedIdentifiers = [NSSet setWithArray:[removedGlobalIdentifiers valueForKeyPath:@"globalIdentifier"]];
    
    if (propertyChange.type != CDEPropertyChangeTypeOrderedToManyRelationship) return;
    
    NSMutableDictionary *newMovedIdentifiers = [[NSMutableDictionary alloc] initWithCapacity:propertyChange.movedIdentifiersByIndex.count];
    for (NSNumber *index in propertyChange.movedIdentifiersByIndex.allKeys) {
        id objectID = propertyChange.movedIdentifiersByIndex[index];
        id globalIdentifier = [[globalIdentifiersByObjectID objectForKey:objectID] globalIdentifier];
        if (!globalIdentifier) {
            CDELog(CDELoggingLevelWarning, @"Missing global id for moved object with objectID: %@", objectID);
            continue;
        }
        newMovedIdentifiers[index] = globalIdentifier;
    }
    propertyChange.movedIdentifiersByIndex = newMovedIdentifiers;
}

@end
