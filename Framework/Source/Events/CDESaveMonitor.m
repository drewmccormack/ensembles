//
//  CDEManagedObjectContextSaveMonitor.m
//  Test App iOS
//
//  Created by Drew McCormack on 4/16/13.
//  Copyright (c) 2013 The Mental Faculty B.V. All rights reserved.
//

#import "CDESaveMonitor.h"
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
        
        changedValuesByContext = [NSMapTable weakToStrongObjectsMapTable];
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
        if ([store.URL isEqual:monitoredStoreURL]) {
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
        NSManagedObjectID *objectID = object.objectID;
        changedValuesByObjectID[objectID] = propertyChanges;
    }];
    
    NSManagedObjectContext *context = [objects.anyObject managedObjectContext];
    [changedValuesByContext setObject:changedValuesByObjectID forKey:context];
}


#pragma mark Storing Changes

- (void)saveEventStore
{
    NSManagedObjectContext *eventContext = self.eventStore.managedObjectContext;
    [eventContext performBlock:^{
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
    
    CDELog(CDELoggingLevelVerbose, @"Store changes post-save");
    
    // Store changes
    [self storeChangesForContext:context changedObjectsDictionary:notif.userInfo];
    
    // Notification
    NSDictionary *userInfo = self.ensemble ? @{@"persistentStoreEnsemble" : self.ensemble} : nil;
    [[NSNotificationCenter defaultCenter] postNotificationName:CDEMonitoredManagedObjectContextDidSaveNotification object:context userInfo:userInfo];
}

- (void)storeChangesForContext:(NSManagedObjectContext *)context changedObjectsDictionary:(NSDictionary *)changedObjectsDictionary
{
    NSSet *insertedObjects = [changedObjectsDictionary objectForKey:NSInsertedObjectsKey];
    NSSet *deletedObjects = [changedObjectsDictionary objectForKey:NSDeletedObjectsKey];
    NSSet *updatedObjects = [changedObjectsDictionary objectForKey:NSUpdatedObjectsKey];
    if (insertedObjects.count + deletedObjects.count + updatedObjects.count == 0) return;
    
    // Lock event store to make new event atomically
    [self.eventStore lock];
    
    // Add a store mod event
    CDEEventBuilder *eventBuilder = [[CDEEventBuilder alloc] initWithEventStore:self.eventStore];
    eventBuilder.ensemble = self.ensemble;
    [eventBuilder makeNewEventOfType:CDEStoreModificationEventTypeSave];
    
    // Register event, so if there is a crash, we can detect it and clean up
    [self.eventStore registerIncompleteEventIdentifier:eventBuilder.event.uniqueIdentifier isMandatory:YES];
    
    // Inserted Objects. Do inserts before updates to make sure each object has a global identifier.
    insertedObjects = [self monitoredManagedObjectsInSet:insertedObjects];
    [eventBuilder addChangesForInsertedObjects:insertedObjects objectsAreSaved:YES inManagedObjectContext:context];
    [self saveEventStore];
    
    // Deleted Objects
    deletedObjects = [self monitoredManagedObjectsInSet:deletedObjects];
    [eventBuilder addChangesForDeletedObjects:deletedObjects inManagedObjectContext:context];
    [self saveEventStore];
    
    // Updated Objects
    updatedObjects = [self monitoredManagedObjectsInSet:updatedObjects];
    NSDictionary *changedValuesByObjectID = [changedValuesByContext objectForKey:context];
    [eventBuilder addChangesForUpdatedObjects:updatedObjects inManagedObjectContext:context options:CDEUpdateStoreOptionSavedValue propertyChangeValuesByObjectID:changedValuesByObjectID];
    [self saveEventStore];
    
    // Deregister event, and clean up
    [self.eventStore deregisterIncompleteEventIdentifier:eventBuilder.event.uniqueIdentifier];
    [changedValuesByContext removeObjectForKey:context];
    
    [self.eventStore unlock];
}

@end
