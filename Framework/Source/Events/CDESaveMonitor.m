//
//  CDEManagedObjectContextSaveMonitor.m
//  Test App iOS
//
//  Created by Drew McCormack on 4/16/13.
//  Copyright (c) 2013 The Mental Faculty B.V. All rights reserved.
//

#import "CDESaveMonitor.h"
#import "NSMapTable+CDEAdditions.h"
#import "CDEPersistentStoreEnsemble.h"
#import "CDEEventBuilder.h"
#import "CDEEventIntegrator.h"
#import "CDEDefines.h"
#import "CDEEventRevision.h"
#import "CDERevision.h"
#import "CDERevisionSet.h"
#import "CDEFoundationAdditions.h"
#import "CDEEventStore.h"
#import "CDEStoreModificationEvent.h"
#import "CDEPropertyChangeValue.h"


@implementation CDESaveMonitor {
    NSMapTable *changedValuesByContext;
}

- (instancetype)initWithStorePath:(NSString *)newPath
{
    self = [super init];
    if (self) {
        self.storePath = [newPath copy];
        
        changedValuesByContext = [NSMapTable cde_weakToStrongObjectsMapTable];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(contextDidSave:) name:NSManagedObjectContextDidSaveNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(contextWillSave:) name:NSManagedObjectContextWillSaveNotification object:nil];
    }
    return self;
}

- (instancetype) init
{
    return [self initWithStorePath:nil];
}

- (void)dealloc
{
    [self stopMonitoring];
}


#pragma mark Stopping Monitoring

- (void)stopMonitoring
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}


#pragma mark Determining which contexts to monitor

- (NSPersistentStore *)monitoredPersistentStoreInManagedObjectContext:(NSManagedObjectContext *)context
{
    if (context.parentContext) return nil;
    
    // Check if this context includes the monitored store
    NSPersistentStoreCoordinator *psc = context.persistentStoreCoordinator;
    NSArray *stores = psc.persistentStores;
    NSURL *monitoredStoreURL = [NSURL fileURLWithPath:self.storePath];
    NSPersistentStore *monitoredStore = nil;
    for (NSPersistentStore *store in stores) {
        NSURL *url1 = [store.URL URLByStandardizingPath];
        NSURL *url2 = [monitoredStoreURL URLByStandardizingPath];
        if ([url1 isEqual:url2]) {
            monitoredStore = store;
            break;
        }
    }
    
    return monitoredStore;
}


#pragma mark Monitored Objects

- (NSSet *)monitoredManagedObjectsInSet:(NSSet *)objectsSet
{
    if (objectsSet.count == 0) return [NSSet set];
    
    NSManagedObjectContext *monitoredContext = [objectsSet.anyObject managedObjectContext];
    NSPersistentStore *monitoredStore = [self monitoredPersistentStoreInManagedObjectContext:monitoredContext];
    
    NSMutableSet *returned = [[NSMutableSet alloc] initWithCapacity:objectsSet.count];
    for (NSManagedObject *object in objectsSet) {
        NSManagedObjectID *objectID = object.objectID;
        if (objectID.persistentStore != monitoredStore) continue;
        [returned addObject:object];
    }
    
    return returned;
}


#pragma mark Object Updates

- (void)contextWillSave:(NSNotification *)notif
{    
    NSManagedObjectContext *context = notif.object;
    if (!self.eventStore.containsEventData) return;
    
    // Check if this context includes the monitored store
    NSPersistentStore *monitoredStore = [self monitoredPersistentStoreInManagedObjectContext:context];
    if (!monitoredStore) return;
    
    // Give user code chance to make changes before preparing
    NSDictionary *userInfo = self.ensemble ? @{@"persistentStoreEnsemble" : self.ensemble} : nil;
    [[NSNotificationCenter defaultCenter] postNotificationName:CDEMonitoredManagedObjectContextWillSaveNotification object:context userInfo:userInfo];
    
    // Store changed values for updates, because they aren't accessible after the save
    [self storePreSaveChangesFromUpdatedObjects:context.updatedObjects];
}

- (void)storePreSaveChangesFromUpdatedObjects:(NSSet *)objects
{
    if (objects.count == 0) return;
    
    CDELog(CDELoggingLevelVerbose, @"Storing pre-save changes from updated objects");
    
    NSSet *monitoredObjects = [self monitoredManagedObjectsInSet:objects];
    
    NSMutableDictionary *changedValuesByObjectID = [NSMutableDictionary dictionaryWithCapacity:monitoredObjects.count];
    [monitoredObjects.allObjects cde_enumerateObjectsDrainingEveryIterations:50 usingBlock:^(NSManagedObject *object, NSUInteger index, BOOL *stop) {
        NSArray *propertyChanges = [CDEPropertyChangeValue propertyChangesForObject:object eventStore:self.eventStore propertyNames:object.changedValues.allKeys isPreSave:YES storeValues:NO];
        
        // don't store updated objects with empty changes (transient, etc.)
        if(propertyChanges.count > 0)
        {
            NSManagedObjectID *objectID = object.objectID;
            changedValuesByObjectID[objectID] = propertyChanges;
        }
    }];

    NSManagedObjectContext *context = [objects.anyObject managedObjectContext];
    [changedValuesByContext setObject:changedValuesByObjectID forKey:context];
}


#pragma mark Storing Changes

- (void)saveEventStore
{
    NSManagedObjectContext *eventContext = self.eventStore.managedObjectContext;
    [eventContext performBlockAndWait:^{
        NSError *error;
        if (![eventContext save:&error]) CDELog(CDELoggingLevelError, @"Error saving event store: %@", error);
    }];
}

- (void)contextDidSave:(NSNotification *)notif
{
    NSManagedObjectContext *context = notif.object;
    if (!self.eventStore.containsEventData) return;
    if (context == self.eventIntegrator.managedObjectContext) return;
    
    // Check if this context includes the monitored store
    NSPersistentStore *monitoredStore = [self monitoredPersistentStoreInManagedObjectContext:context];
    if (!monitoredStore) return;
    
    CDELog(CDELoggingLevelVerbose, @"Storing changes post-save");
    
    // Store changes
    [self asynchronouslyStoreChangesForContext:context changedObjectsDictionary:notif.userInfo];
    
    // Notification
    NSDictionary *userInfo = self.ensemble ? @{@"persistentStoreEnsemble" : self.ensemble} : nil;
    [[NSNotificationCenter defaultCenter] postNotificationName:CDEMonitoredManagedObjectContextDidSaveNotification object:context userInfo:userInfo];
}

- (void)asynchronouslyStoreChangesForContext:(NSManagedObjectContext *)context changedObjectsDictionary:(NSDictionary *)changedObjectsDictionary
{
    // Get the changed objects
    NSSet *insertedObjects = [changedObjectsDictionary objectForKey:NSInsertedObjectsKey];
    NSSet *deletedObjects = [changedObjectsDictionary objectForKey:NSDeletedObjectsKey];
    NSSet *updatedObjects = [changedObjectsDictionary objectForKey:NSUpdatedObjectsKey];
    if (insertedObjects.count + deletedObjects.count + updatedObjects.count == 0) return;
    
    // Register event, so if there is a crash, we can detect it and clean up
    NSString *newUniqueId = [[NSProcessInfo processInfo] globallyUniqueString];
    [self.eventStore registerIncompleteEventIdentifier:newUniqueId isMandatory:YES];
    
    // Reduce to just the objects belonging to the store
    insertedObjects = [self monitoredManagedObjectsInSet:insertedObjects];
    deletedObjects = [self monitoredManagedObjectsInSet:deletedObjects];
    updatedObjects = [self monitoredManagedObjectsInSet:updatedObjects];
    
    // Get change data. Must be called on the context thread, not the event store thread.
    CDEEventBuilder *eventBuilder = [[CDEEventBuilder alloc] initWithEventStore:self.eventStore];
    eventBuilder.ensemble = self.ensemble;
    NSDictionary *changedValuesByObjectID = [changedValuesByContext objectForKey:context];
    NSMutableDictionary *insertData = [[eventBuilder changesDataForInsertedObjects:insertedObjects objectsAreSaved:YES inManagedObjectContext:context] mutableCopy];
    NSDictionary *updateData = [eventBuilder changesDataForUpdatedObjects:updatedObjects inManagedObjectContext:context options:CDEUpdateStoreOptionSavedValue propertyChangeValuesByObjectID:changedValuesByObjectID];
    NSDictionary *deleteData = [eventBuilder changesDataForDeletedObjects:deletedObjects inManagedObjectContext:context];
    [changedValuesByContext removeObjectForKey:context];

    // If there are no changes, we bail early and don't create any save event.
    NSUInteger changeCount = [insertData[@"changeArrays"] count];
    NSUInteger updateCount = [updateData[@"objectIDs"] count];
    NSUInteger deleteCount = [deleteData[@"orderedObjectIDs"] count];
    if (changeCount + updateCount + deleteCount == 0) {
        [self.eventStore deregisterIncompleteEventIdentifier:newUniqueId];
        return;
    }
    
    // Make sure the event is saved atomically
    [self.eventStore.managedObjectContext performBlock:^{
        // Global Ids
        NSArray *globalIds = [eventBuilder addGlobalIdentifiersForInsertChangesData:insertData];
        insertData[@"globalIds"] = globalIds;
        
        // Add a store mod event
        [eventBuilder makeNewEventOfType:CDEStoreModificationEventTypeSave uniqueIdentifier:newUniqueId];
    
        // Inserted Objects. Do inserts before updates to make sure each object has a global identifier.
        [eventBuilder addInsertChangesForChangesData:insertData];
        [self saveEventStore];
        
        // Updated Objects
        [eventBuilder addUpdateChangesForChangesData:updateData];
        [self saveEventStore];
        
        // Deleted Objects
        [eventBuilder addDeleteChangesForChangesData:deleteData];
        
        // Finalize
        [eventBuilder finalizeNewEvent];
        [self saveEventStore];
        
        // Deregister event, and clean up
        [self.eventStore deregisterIncompleteEventIdentifier:eventBuilder.event.uniqueIdentifier];
    }];
}

@end
