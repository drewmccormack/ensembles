//
//  CDEEventMigrator.m
//  Test App iOS
//
//  Created by Drew McCormack on 5/10/13.
//  Copyright (c) 2013 The Mental Faculty B.V. All rights reserved.
//

#import "CDEEventMigrator.h"
#import "CDEDefines.h"
#import "NSMapTable+CDEAdditions.h"
#import "CDEEventStore.h"
#import "CDEGlobalIdentifier.h"
#import "CDEEventRevision.h"
#import "CDERevision.h"
#import "CDEStoreModificationEvent.h"
#import "CDEObjectChange.h"

static NSString *kCDEDefaultStoreType;

@implementation CDEEventMigrator

@synthesize eventStore = eventStore;
@synthesize storeTypeForNewFiles = storeTypeForNewFiles;

+ (void)initialize
{
    if (self == [CDEEventMigrator class]) {
        kCDEDefaultStoreType = NSBinaryStoreType;
    }
}

- (instancetype)initWithEventStore:(CDEEventStore *)newStore
{
    self = [super init];
    if (self) {
        eventStore = newStore;
        storeTypeForNewFiles = kCDEDefaultStoreType;
    }
    return self;
}

- (void)migrateLocalEventWithRevision:(CDERevisionNumber)revisionNumber toFile:(NSString *)path allowedTypes:(NSArray *)types completion:(CDECompletionBlock)completion
{
    [eventStore.managedObjectContext performBlock:^{
        NSError *error = nil;
        CDEStoreModificationEvent *event = nil;
        event = [CDEStoreModificationEvent fetchStoreModificationEventWithAllowedTypes:types persistentStoreIdentifier:eventStore.persistentStoreIdentifier revisionNumber:revisionNumber inManagedObjectContext:eventStore.managedObjectContext];
        if (event) {
            [self migrateStoreModificationEvents:@[event] toFile:path completion:completion];
        }
        else {
            NSDictionary *info = @{NSLocalizedDescriptionKey : @"Failed to fetch local event in migrateLocalEventToTemporaryFilesForRevision..."};
            error = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeUnknown userInfo:info];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(error);
            });
        }
    }];
}

- (void)migrateLocalBaselineWithUniqueIdentifier:(NSString *)uniqueId globalCount:(CDEGlobalCount)count persistentStorePrefix:(NSString *)storePrefix toFile:(NSString *)path completion:(CDECompletionBlock)completion
{
    [eventStore.managedObjectContext performBlock:^{
        NSError *error = nil;
        CDEStoreModificationEvent *baseline = nil;
        baseline = [CDEStoreModificationEvent fetchStoreModificationEventWithUniqueIdentifier:uniqueId globalCount:count persistentStorePrefix:storePrefix inManagedObjectContext:eventStore.managedObjectContext];
        if (baseline) {
            NSAssert(baseline.type == CDEStoreModificationEventTypeBaseline, @"Wrong event type for baseline");
            [self migrateStoreModificationEvents:@[baseline] toFile:path completion:completion];
        }
        else {
            NSDictionary *info = @{NSLocalizedDescriptionKey : @"Failed to fetch local event in migrateLocalBaselineWithUniqueIdentifier..."};
            error = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeUnknown userInfo:info];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(error);
            });
        }
    }];
}

- (void)migrateNonBaselineEventsSinceRevision:(CDERevisionNumber)revision toFile:(NSString *)path completion:(CDECompletionBlock)completion
{
    [eventStore.managedObjectContext performBlock:^{
        NSError *error = nil;
        NSArray *events = [self storeModificationEventsCreatedLocallySinceRevisionNumber:revision error:&error];
        if (!events) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(error);
            });
        }
        else {
            [self migrateStoreModificationEvents:events toFile:path completion:completion];
        }
    }];
}

- (void)migrateStoreModificationEvents:(NSArray *)events toFile:(NSString *)path completion:(CDECompletionBlock)completion
{
    CDELog(CDELoggingLevelVerbose, @"Migrating event store events to file");
    
    NSManagedObjectContext *exportContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSConfinementConcurrencyType];
    NSPersistentStoreCoordinator *mainCoordinator = eventStore.managedObjectContext.persistentStoreCoordinator;
    NSPersistentStoreCoordinator *persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:mainCoordinator.managedObjectModel];
    exportContext.persistentStoreCoordinator = persistentStoreCoordinator;
    exportContext.undoManager = nil;

    NSError *error = nil;
    NSPersistentStore *fileStore = nil;
    @try {
        NSURL *fileURL = [NSURL fileURLWithPath:path];
        
        fileStore = [persistentStoreCoordinator addPersistentStoreWithType:self.storeTypeForNewFiles configuration:nil URL:fileURL options:nil error:&error];
        if (!fileStore) @throw [[NSException alloc] initWithName:CDEException reason:@"" userInfo:nil];
        
        if (!events) @throw [[NSException alloc] initWithName:CDEException reason:@"" userInfo:nil];
        [CDEStoreModificationEvent prefetchRelatedObjectsForStoreModificationEvents:events];
        
        NSMapTable *toStoreObjectsByFromStoreObject = [NSMapTable cde_strongToStrongObjectsMapTable];
        for (CDEStoreModificationEvent *event in events) {
            [self migrateObject:event andRelatedObjectsToManagedObjectContext:exportContext withMigratedObjectsMap:toStoreObjectsByFromStoreObject];
        }
        
        BOOL success = [exportContext save:&error];
        if (!success) @throw [[NSException alloc] initWithName:CDEException reason:@"" userInfo:nil];
    }
    @catch (NSException *exception) {
        if (!error) error = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeUnknown userInfo:@{NSLocalizedDescriptionKey: exception.description}];
        CDELog(CDELoggingLevelError, @"Failed to migrate modification events out to file: %@", error);
    }
    @finally {
        [exportContext reset];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(error);
        });
    }
}

- (void)migrateEventsInFromFiles:(NSArray *)paths completion:(CDECompletionBlock)completion
{
    CDELog(CDELoggingLevelVerbose, @"Migrating file events to event store from paths: %@", paths);
    
    [self.eventStore.managedObjectContext performBlock:^{
        NSManagedObjectContext *importContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSConfinementConcurrencyType];
        NSPersistentStoreCoordinator *mainCoordinator = eventStore.managedObjectContext.persistentStoreCoordinator;
        NSPersistentStoreCoordinator *persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:mainCoordinator.managedObjectModel];
        importContext.persistentStoreCoordinator = persistentStoreCoordinator;
        importContext.undoManager = nil;
        
        NSError *error = nil;
        NSPersistentStore *fileStore = nil;
        @try {
            for (NSString *path in paths) {
                @autoreleasepool {
                    NSURL *fileURL = [NSURL fileURLWithPath:path];
                    
                    NSDictionary *metadata = [NSPersistentStoreCoordinator metadataForPersistentStoreOfType:nil URL:fileURL error:&error];
                    NSString *storeType = metadata[NSStoreTypeKey];
                    if (!storeType) @throw [[NSException alloc] initWithName:CDEException reason:@"" userInfo:nil];
                    
                    NSDictionary *options = @{NSMigratePersistentStoresAutomaticallyOption: @YES, NSInferMappingModelAutomaticallyOption: @YES};
                    fileStore = [importContext.persistentStoreCoordinator addPersistentStoreWithType:storeType configuration:nil URL:fileURL options:options error:&error];
                    if (!fileStore) @throw [[NSException alloc] initWithName:CDEException reason:@"" userInfo:nil];
                    
                    BOOL success = [self migrateObjectsInContext:importContext toContext:self.eventStore.managedObjectContext error:&error];
                    if (!success) @throw [[NSException alloc] initWithName:CDEException reason:@"" userInfo:nil];
                    
                    success = [importContext.persistentStoreCoordinator removePersistentStore:fileStore error:&error];
                    fileStore = nil;
                    if (!success) @throw [[NSException alloc] initWithName:CDEException reason:@"" userInfo:nil];
                    
                    success = [self.eventStore.managedObjectContext save:&error];
                    [importContext reset];
                    if (!success) @throw [[NSException alloc] initWithName:CDEException reason:@"" userInfo:nil];
                }
            }
        }
        @catch (NSException *exception) {
            if (!error) error = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeUnknown userInfo:@{NSLocalizedDescriptionKey: exception.description}];
            CDELog(CDELoggingLevelError, @"Failed to migrate modification events: %@", error);
        }
        @finally {
            [importContext reset];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(error);
            });
        }
    }];
}

- (BOOL)migrateObjectsInContext:(NSManagedObjectContext *)fromContext toContext:(NSManagedObjectContext *)toContext error:(NSError * __autoreleasing *)error
{
    // Migrate global identifiers. Enforce uniqueness.
    NSMapTable *toGlobalIdsByFromGlobalId = [self migrateEntity:@"CDEGlobalIdentifier" inManagedObjectContext:fromContext toContext:toContext enforceUniquenessForAttributes:@[@"nameOfEntity", @"globalIdentifier"] error:error];
    if (!toGlobalIdsByFromGlobalId) return NO;
    
    // Retrieve modification events
    NSArray *storeModEventsToMigrate = [self storeModificationEventsInManagedObjectContext:fromContext requiringMigrationToContext:toContext error:error];
    if (!storeModEventsToMigrate) return NO;
    
    // Prefetch relevant objects
    [CDEStoreModificationEvent prefetchRelatedObjectsForStoreModificationEvents:storeModEventsToMigrate];
    
    // Migrate mod events
    NSMapTable *toObjectsByFromObject = [NSMapTable cde_strongToStrongObjectsMapTable];
    [toObjectsByFromObject cde_addEntriesFromMapTable:toGlobalIdsByFromGlobalId];
    @try {
        for (CDEStoreModificationEvent *fromStoreModEvent in storeModEventsToMigrate) {
            [self.eventStore registerIncompleteEventIdentifier:fromStoreModEvent.uniqueIdentifier isMandatory:NO];
            [self migrateObject:fromStoreModEvent andRelatedObjectsToManagedObjectContext:toContext withMigratedObjectsMap:toObjectsByFromObject];
            [self.eventStore deregisterIncompleteEventIdentifier:fromStoreModEvent.uniqueIdentifier];
        }
    }
    @catch (NSException *exception) {
        if (error) *error = [[NSError alloc] initWithDomain:CDEErrorDomain code:CDEErrorCodeUnknown userInfo:@{NSLocalizedFailureReasonErrorKey:exception.reason}];
        return NO;
    }
    
    return YES;
}

- (NSManagedObject *)migrateObject:(NSManagedObject *)fromStoreObject andRelatedObjectsToManagedObjectContext:(NSManagedObjectContext *)toContext withMigratedObjectsMap:(NSMapTable *)toStoreObjectsByFromStoreObject
{
    if (fromStoreObject == nil) return nil;
    
    NSManagedObject *migratedObject = [toStoreObjectsByFromStoreObject objectForKey:fromStoreObject];
    if (migratedObject) return migratedObject;
    
    // Migrated object doesn't exist, so create it
    NSString *entityName = fromStoreObject.entity.name;
    migratedObject = [NSEntityDescription insertNewObjectForEntityForName:entityName inManagedObjectContext:toContext];
    [self copyAttributesFromObject:fromStoreObject toObject:migratedObject];
    
    // Add object to map
    [toStoreObjectsByFromStoreObject setObject:migratedObject forKey:fromStoreObject];
    
    // Migrate related objects recursively
    NSDictionary *relationships = fromStoreObject.entity.relationshipsByName;
    for (NSRelationshipDescription *relationship in relationships.allValues) {
        if (relationship.isTransient) continue;
        
        NSString *exclude = relationship.userInfo[@"excludeFromMigration"];
        if (exclude && [exclude boolValue]) continue;
        
        if (relationship.isToMany) {
            // To-many relationship
            id fromStoreRelatives = [fromStoreObject valueForKey:relationship.name];
            for (NSManagedObject *fromRelative in fromStoreRelatives) {
                NSManagedObject *toStoreRelative = [self migrateObject:fromRelative andRelatedObjectsToManagedObjectContext:toContext withMigratedObjectsMap:toStoreObjectsByFromStoreObject];
                if (relationship.isOrdered)
                    [[migratedObject mutableOrderedSetValueForKey:relationship.name] addObject:toStoreRelative];
                else
                    [[migratedObject mutableSetValueForKey:relationship.name] addObject:toStoreRelative];
            }
        }
        else {
            // To-one relationship
            NSManagedObject *fromStoreRelative = [fromStoreObject valueForKey:relationship.name];
            NSManagedObject *toStoreRelative = [self migrateObject:fromStoreRelative andRelatedObjectsToManagedObjectContext:toContext withMigratedObjectsMap:toStoreObjectsByFromStoreObject];
            [migratedObject setValue:toStoreRelative forKey:relationship.name];
        }
    }
    
    return migratedObject;
}

- (NSArray *)storeModificationEventsCreatedLocallySinceRevisionNumber:(CDERevisionNumber)revisionNumber error:(NSError * __autoreleasing *)error
{
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"CDEStoreModificationEvent"];
    fetch.predicate = [NSPredicate predicateWithFormat:@"eventRevision.revisionNumber > %lld AND eventRevision.persistentStoreIdentifier = %@ && type != %d && type != %d", revisionNumber, eventStore.persistentStoreIdentifier, CDEStoreModificationEventTypeBaseline, CDEStoreModificationEventTypeIncomplete];
    NSArray *storeModEvents = [eventStore.managedObjectContext executeFetchRequest:fetch error:error];
    return storeModEvents;
}

- (NSArray *)storeModificationEventsInManagedObjectContext:(NSManagedObjectContext *)fromContext requiringMigrationToContext:(NSManagedObjectContext *)toContext error:(NSError * __autoreleasing *)error
{
    NSParameterAssert(fromContext != nil);
    NSParameterAssert(toContext != nil);
    
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"CDEStoreModificationEvent"];
    NSArray *fromContextObjects = [fromContext executeFetchRequest:fetch error:error];
    return fromContextObjects;
}

- (NSMapTable *)migrateEntity:(NSString *)entityName inManagedObjectContext:(NSManagedObjectContext *)fromContext toContext:(NSManagedObjectContext *)toContext enforceUniquenessForAttributes:(NSArray *)uniqueAttributes error:(NSError * __autoreleasing *)error
{
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:entityName];
    NSArray *fromContextObjects = [fromContext executeFetchRequest:fetch error:error];
    if (!fromContextObjects) return nil;
    
    NSFetchRequest *toContextFetch = [NSFetchRequest fetchRequestWithEntityName:entityName];
    NSArray *toContextObjects = [toContext executeFetchRequest:toContextFetch error:error];
    if (!toContextObjects) return nil;
    
    NSArray *toStoreKeys = [self uniqueKeysForObjects:toContextObjects uniqueAttributes:uniqueAttributes];
    NSArray *fromStoreKeys = [self uniqueKeysForObjects:fromContextObjects uniqueAttributes:uniqueAttributes];

    NSDictionary *toStoreObjectsByUniqueValue = [[NSDictionary alloc] initWithObjects:toContextObjects forKeys:toStoreKeys];
    NSDictionary *fromStoreObjectsByUniqueValue = [[NSDictionary alloc] initWithObjects:fromContextObjects forKeys:fromStoreKeys];
    
    NSMapTable *toObjectByFromObject = [NSMapTable cde_strongToStrongObjectsMapTable];
    for (id uniqueValue in fromStoreObjectsByUniqueValue) {
        NSManagedObject *toContextObject = toStoreObjectsByUniqueValue[uniqueValue];
        NSManagedObject *fromContextObject = fromStoreObjectsByUniqueValue[uniqueValue];
        
        if (toContextObject) {
            [toObjectByFromObject setObject:toContextObject forKey:fromContextObject];
            continue;
        }
        
        toContextObject = [NSEntityDescription insertNewObjectForEntityForName:fromContextObject.entity.name inManagedObjectContext:toContext];
        [self copyAttributesFromObject:fromContextObject toObject:toContextObject];
        
        [toObjectByFromObject setObject:toContextObject forKey:fromContextObject];
    }
    
    return toObjectByFromObject;
}

- (NSArray *)uniqueKeysForObjects:(NSArray *)objects uniqueAttributes:(NSArray *)uniqueAttributes
{
    NSMutableArray *keys = [[NSMutableArray alloc] init];
    for (id object in objects) {
        NSMutableString *key = [[NSMutableString alloc] init];
        for (NSString *attribute in uniqueAttributes) {
            [key appendString:[[object valueForKeyPath:attribute] description]];
            [key appendString:@"__"];
        }
        [keys addObject:key];
    }
    return keys;
}

- (void)copyAttributesFromObject:(NSManagedObject *)fromObject toObject:(NSManagedObject *)toObject
{
    for (NSAttributeDescription *attribute in fromObject.entity.attributesByName.allValues) {
        if (attribute.isTransient) continue;
        
        NSString *exclude = attribute.userInfo[@"excludeFromMigration"];
        if (exclude && [exclude boolValue]) continue;
        
        NSString *key = attribute.name;
        [toObject setValue:[fromObject valueForKey:key] forKey:key];
    }
}

@end
