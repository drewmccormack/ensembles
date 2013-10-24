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

- (void)migrateLocalEventWithRevision:(CDERevisionNumber)revisionNumber toFile:(NSString *)path completion:(CDECompletionBlock)completion
{
    [eventStore.managedObjectContext performBlock:^{
        NSError *error = nil;
        CDEStoreModificationEvent *event = nil;
        event = [self localEventWithRevisionNumber:revisionNumber error:&error];
        if (!event) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(error);
            });
        }
        else {
            [self migrateStoreModificationEvents:@[event] toFile:path completion:completion];
        }
    }];
}

- (void)migrateLocalEventsSinceRevision:(CDERevisionNumber)revision toFile:(NSString *)path completion:(CDECompletionBlock)completion
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
    __block NSError *error = nil;
    __block NSPersistentStore *fileStore = nil;
    NSPersistentStoreCoordinator *persistentStoreCoordinator = eventStore.managedObjectContext.persistentStoreCoordinator;
    @try {
        NSURL *fileURL = [NSURL fileURLWithPath:path];
        
        [persistentStoreCoordinator lock];
        fileStore = [persistentStoreCoordinator addPersistentStoreWithType:self.storeTypeForNewFiles configuration:nil URL:fileURL options:nil error:&error];
        [persistentStoreCoordinator unlock];
        if (!fileStore) @throw [[NSException alloc] initWithName:CDEException reason:@"" userInfo:nil];
        
        if (!events) @throw [[NSException alloc] initWithName:CDEException reason:@"" userInfo:nil];
        [CDEStoreModificationEvent prefetchRelatedObjectsForStoreModificationEvents:events];
        
        NSMapTable *toStoreObjectsByFromStoreObject = [NSMapTable strongToStrongObjectsMapTable];
        for (CDEStoreModificationEvent *event in events) {
            [self migrateObject:event andRelatedObjectsToStore:fileStore withMigratedObjectsMap:toStoreObjectsByFromStoreObject];
        }
        
        BOOL success = [eventStore.managedObjectContext save:&error];
        if (!success) @throw [[NSException alloc] initWithName:CDEException reason:@"" userInfo:nil];
        
        [persistentStoreCoordinator lock];
        success = [persistentStoreCoordinator removePersistentStore:fileStore error:&error];
        [persistentStoreCoordinator unlock];
        fileStore = nil;
        if (!success) @throw [[NSException alloc] initWithName:CDEException reason:@"" userInfo:nil];
    }
    @catch (NSException *exception) {
        if (!error) error = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeUnknown userInfo:@{NSLocalizedDescriptionKey: exception.description}];
        CDELog(CDELoggingLevelError, @"Failed to migrate modification events out to file: %@", error);
        if (fileStore) {
            [persistentStoreCoordinator lock];
            [persistentStoreCoordinator removePersistentStore:fileStore error:NULL];
            [persistentStoreCoordinator unlock];
        }
    }
    @finally {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(error);
        });
    }
}

- (void)migrateEventsInFromFiles:(NSArray *)paths completion:(CDECompletionBlock)completion
{    
    NSManagedObjectContext *importContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    
    __block NSError *error = nil;
    __block NSPersistentStore *fileStore = nil;
    [importContext performBlock:^{
        importContext.parentContext = eventStore.managedObjectContext;
        NSPersistentStore *mainPersistentStore = importContext.persistentStoreCoordinator.persistentStores.lastObject;
        @try {
            for (NSString *path in paths) {
                @autoreleasepool {
                    NSURL *fileURL = [NSURL fileURLWithPath:path];
                    
                    NSDictionary *metadata = [NSPersistentStoreCoordinator metadataForPersistentStoreOfType:nil URL:fileURL error:&error];
                    NSString *storeType = metadata[NSStoreTypeKey];
                    if (!storeType) @throw [[NSException alloc] initWithName:CDEException reason:@"" userInfo:nil];
                    
                    [importContext.persistentStoreCoordinator lock];
                    NSDictionary *options = @{NSMigratePersistentStoresAutomaticallyOption: @YES, NSInferMappingModelAutomaticallyOption: @YES};
                    fileStore = [importContext.persistentStoreCoordinator addPersistentStoreWithType:storeType configuration:nil URL:fileURL options:options error:&error];
                    [importContext.persistentStoreCoordinator unlock];
                    if (!fileStore) @throw [[NSException alloc] initWithName:CDEException reason:@"" userInfo:nil];
                    
                    BOOL success = [self migrateObjectsInContext:importContext fromStore:fileStore toStore:mainPersistentStore error:&error];
                    if (!success) @throw [[NSException alloc] initWithName:CDEException reason:@"" userInfo:nil];
                    
                    [importContext.persistentStoreCoordinator lock];
                    success = [importContext.persistentStoreCoordinator removePersistentStore:fileStore error:&error];
                    [importContext.persistentStoreCoordinator unlock];
                    fileStore = nil;
                    if (!success) @throw [[NSException alloc] initWithName:CDEException reason:@"" userInfo:nil];
                    
                    success = [importContext save:&error];
                    [importContext reset];
                    if (!success) @throw [[NSException alloc] initWithName:CDEException reason:@"" userInfo:nil];
                }
            }
        }
        @catch (NSException *exception) {
            if (!error) error = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeUnknown userInfo:@{NSLocalizedDescriptionKey: exception.description}];
            CDELog(CDELoggingLevelError, @"Failed to migrate modification events: %@", error);
            if (fileStore) {
                [importContext.persistentStoreCoordinator lock];
                [importContext.persistentStoreCoordinator removePersistentStore:fileStore error:NULL];
                [importContext.persistentStoreCoordinator unlock];
            }
        }
        @finally {
            [importContext reset];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(error);
            });
        }
    }];
}

- (BOOL)migrateObjectsInContext:(NSManagedObjectContext *)context fromStore:(NSPersistentStore *)fromStore toStore:(NSPersistentStore *)toStore error:(NSError * __autoreleasing *)error
{
    // Migrate global identifiers. Enforce uniqueness.
    NSMapTable *toStoreIdsByFromStoreId = [self migrateEntity:@"CDEGlobalIdentifier" inManagedObjectContext:context fromStore:fromStore toStore:toStore enforceUniquenessForAttribute:@"globalIdentifier" error:error];
    if (!toStoreIdsByFromStoreId) return NO;
    
    // Retrieve modification events
    NSArray *storeModEventsToMigrate = [self storeModificationEventsRequiringMigrationInManagedObjectContext:context fromStore:fromStore toStore:toStore error:error];
    if (!storeModEventsToMigrate) return NO;
    
    // Prefetch relevant objects
    [CDEStoreModificationEvent prefetchRelatedObjectsForStoreModificationEvents:storeModEventsToMigrate];
    
    // Migrate mod events
    NSMapTable *toStoreObjectsByFromStoreObject = [NSMapTable strongToStrongObjectsMapTable];
    [toStoreObjectsByFromStoreObject cde_addEntriesFromMapTable:toStoreIdsByFromStoreId];
    @try {
        for (CDEStoreModificationEvent *fromStoreModEvent in storeModEventsToMigrate) {
            [self.eventStore registerIncompleteEventIdentifier:fromStoreModEvent.uniqueIdentifier isMandatory:NO];
            [self migrateObject:fromStoreModEvent andRelatedObjectsToStore:toStore withMigratedObjectsMap:toStoreObjectsByFromStoreObject];
            [self.eventStore deregisterIncompleteEventIdentifier:fromStoreModEvent.uniqueIdentifier];
        }
    }
    @catch (NSException *exception) {
        *error = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeUnknown userInfo:@{NSLocalizedFailureReasonErrorKey:exception.reason}];
        return NO;
    }
    
    return YES;
}

- (NSManagedObject *)migrateObject:(NSManagedObject *)fromStoreObject andRelatedObjectsToStore:(NSPersistentStore *)toStore withMigratedObjectsMap:(NSMapTable *)toStoreObjectsByFromStoreObject
{
    if (fromStoreObject == nil) return nil;
    
    NSManagedObject *migratedObject = [toStoreObjectsByFromStoreObject objectForKey:fromStoreObject];
    if (migratedObject) return migratedObject;
    
    // Migrated object doesn't exist, so create it
    NSManagedObjectContext *context = fromStoreObject.managedObjectContext;
    NSString *entityName = fromStoreObject.entity.name;
    migratedObject = [NSEntityDescription insertNewObjectForEntityForName:entityName inManagedObjectContext:context];
    [context assignObject:migratedObject toPersistentStore:toStore];
    [self copyAttributesFromObject:fromStoreObject toObject:migratedObject];
    
    // Add object to map
    [toStoreObjectsByFromStoreObject setObject:migratedObject forKey:fromStoreObject];
    
    // Migrate related objects recursively
    NSDictionary *relationships = fromStoreObject.entity.relationshipsByName;
    for (NSRelationshipDescription *relationship in relationships.allValues) {
        if (relationship.isTransient) continue;
        if (relationship.isToMany) {
            // To-many relationship
            id fromStoreRelatives = [fromStoreObject valueForKey:relationship.name];
            for (NSManagedObject *fromRelative in fromStoreRelatives) {
                NSManagedObject *toStoreRelative = [self migrateObject:fromRelative andRelatedObjectsToStore:toStore withMigratedObjectsMap:toStoreObjectsByFromStoreObject];
                if (relationship.isOrdered)
                    [[migratedObject mutableOrderedSetValueForKey:relationship.name] addObject:toStoreRelative];
                else
                    [[migratedObject mutableSetValueForKey:relationship.name] addObject:toStoreRelative];
            }
        }
        else {
            // To-one relationship
            NSManagedObject *fromStoreRelative = [fromStoreObject valueForKey:relationship.name];
            NSManagedObject *toStoreRelative = [self migrateObject:fromStoreRelative andRelatedObjectsToStore:toStore withMigratedObjectsMap:toStoreObjectsByFromStoreObject];
            [migratedObject setValue:toStoreRelative forKey:relationship.name];
        }
    }
    
    return migratedObject;
}

- (CDEStoreModificationEvent *)localEventWithRevisionNumber:(CDERevisionNumber)revisionNumber error:(NSError * __autoreleasing *)error
{
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"CDEStoreModificationEvent"];
    fetch.predicate = [NSPredicate predicateWithFormat:@"eventRevision.revisionNumber = %lld AND eventRevision.persistentStoreIdentifier = %@", revisionNumber, eventStore.persistentStoreIdentifier];
    NSArray *storeModEvents = [eventStore.managedObjectContext executeFetchRequest:fetch error:error];
    return [storeModEvents lastObject];
}

- (NSArray *)storeModificationEventsCreatedLocallySinceRevisionNumber:(CDERevisionNumber)revisionNumber error:(NSError * __autoreleasing *)error
{
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"CDEStoreModificationEvent"];
    fetch.predicate = [NSPredicate predicateWithFormat:@"eventRevision.revisionNumber > %lld AND eventRevision.persistentStoreIdentifier = %@", revisionNumber, eventStore.persistentStoreIdentifier];
    NSArray *storeModEvents = [eventStore.managedObjectContext executeFetchRequest:fetch error:error];
    return storeModEvents;
}

- (NSArray *)storeModificationEventsRequiringMigrationInManagedObjectContext:(NSManagedObjectContext *)context fromStore:(NSPersistentStore *)fromStore toStore:(NSPersistentStore *)toStore error:(NSError * __autoreleasing *)error
{
    NSParameterAssert(context != nil);
    NSParameterAssert(fromStore != nil);
    NSParameterAssert(toStore != nil);
    
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"CDEStoreModificationEvent"];
    fetch.affectedStores = @[fromStore];
    NSArray *fromStoreObjects = [context executeFetchRequest:fetch error:error];
    if (!fromStoreObjects) return nil;
    
    NSFetchRequest *toStoreFetch = [NSFetchRequest fetchRequestWithEntityName:@"CDEStoreModificationEvent"];
    toStoreFetch.affectedStores = @[toStore];
    NSArray *toStoreObjects = [context executeFetchRequest:toStoreFetch error:error];
    if (!toStoreObjects) return nil;
    
    // Make sure there are no duplicates. Enforce uniqueness on revision.
    NSArray *keys = [toStoreObjects valueForKeyPath:@"eventRevision.revision.uniqueIdentifier"];
    NSDictionary *toStoreObjectsByRevisionId = [[NSDictionary alloc] initWithObjects:toStoreObjects forKeys:keys];
    NSMutableArray *objectsToMigrate = [NSMutableArray arrayWithCapacity:fromStoreObjects.count];
    for (CDEStoreModificationEvent *event in fromStoreObjects) {
        id <NSCopying> key = event.eventRevision.revision.uniqueIdentifier;
        CDEStoreModificationEvent *existingObject = toStoreObjectsByRevisionId[key];
        if (existingObject) continue;
        [objectsToMigrate addObject:event];
    }
    
    return objectsToMigrate;
}

- (NSMapTable *)migrateEntity:(NSString *)entityName inManagedObjectContext:(NSManagedObjectContext *)context fromStore:(NSPersistentStore *)fromStore toStore:(NSPersistentStore *)toStore enforceUniquenessForAttribute:(NSString *)uniqueAttribute error:(NSError * __autoreleasing *)error
{
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:entityName];
    fetch.affectedStores = @[fromStore];
    NSArray *fromStoreObjects = [context executeFetchRequest:fetch error:error];
    if (!fromStoreObjects) return nil;
    
    NSFetchRequest *toStoreFetch = [NSFetchRequest fetchRequestWithEntityName:entityName];
    toStoreFetch.affectedStores = @[toStore];
    NSArray *toStoreObjects = [context executeFetchRequest:toStoreFetch error:error];
    if (!toStoreObjects) return nil;
    
    NSDictionary *toStoreObjectsByUniqueValue = [[NSDictionary alloc] initWithObjects:toStoreObjects forKeys:[toStoreObjects valueForKeyPath:uniqueAttribute]];
    NSDictionary *fromStoreObjectsByUniqueValue = [[NSDictionary alloc] initWithObjects:fromStoreObjects forKeys:[fromStoreObjects valueForKeyPath:uniqueAttribute]];
    
    NSMapTable *toObjectByFromObject = [NSMapTable strongToStrongObjectsMapTable];
    for (id uniqueValue in fromStoreObjectsByUniqueValue) {
        CDEGlobalIdentifier *toStoreObject = toStoreObjectsByUniqueValue[uniqueValue];
        CDEGlobalIdentifier *fromStoreObject = fromStoreObjectsByUniqueValue[uniqueValue];
        
        if (toStoreObject) {
            [toObjectByFromObject setObject:toStoreObject forKey:fromStoreObject];
            continue;
        }
        
        toStoreObject = [NSEntityDescription insertNewObjectForEntityForName:fromStoreObject.entity.name inManagedObjectContext:context];
        [context assignObject:toStoreObject toPersistentStore:toStore];
        [self copyAttributesFromObject:fromStoreObject toObject:toStoreObject];
        
        [toObjectByFromObject setObject:toStoreObject forKey:fromStoreObject];
    }
    
    return toObjectByFromObject;
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
