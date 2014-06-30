//
//  CDEPersistentStoreImporter.m
//  Ensembles
//
//  Created by Drew McCormack on 21/09/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import "CDEPersistentStoreImporter.h"
#import "CDEStoreModificationEvent.h"
#import "CDEEventStore.h"
#import "CDEEventBuilder.h"
#import "CDEEventRevision.h"

@implementation CDEPersistentStoreImporter

@synthesize persistentStorePath = persistentStorePath;
@synthesize eventStore = eventStore;
@synthesize managedObjectModel = managedObjectModel;
@synthesize persistentStoreOptions = persistentStoreOptions;

- (id)initWithPersistentStoreAtPath:(NSString *)newPath managedObjectModel:(NSManagedObjectModel *)newModel eventStore:(CDEEventStore *)newEventStore;
{
    self = [super init];
    if (self) {
        persistentStorePath = [newPath copy];
        eventStore = newEventStore;
        managedObjectModel = newModel;
        persistentStoreOptions = nil;
    }
    return self;
}

- (void)importWithCompletion:(CDECompletionBlock)completion
{
    CDELog(CDELoggingLevelVerbose, @"Importing persistent store");

    __block NSError *error = nil;
    
    NSManagedObjectContext *context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    [context performBlockAndWait:^{
        NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:managedObjectModel];
        context.persistentStoreCoordinator = coordinator;
        context.undoManager = nil;
        
        NSURL *storeURL = [NSURL fileURLWithPath:persistentStorePath];
        NSDictionary *options = self.persistentStoreOptions;
        if (!options) options = @{NSMigratePersistentStoresAutomaticallyOption: @YES, NSInferMappingModelAutomaticallyOption: @YES};
        [coordinator lock];
        [coordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:options error:&error];
        [coordinator unlock];
    }];
    
    if (error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(error);
        });
        return;
    }
    
    NSManagedObjectContext *eventContext = eventStore.managedObjectContext;
    CDEEventBuilder *eventBuilder = [[CDEEventBuilder alloc] initWithEventStore:self.eventStore];
    eventBuilder.ensemble = self.ensemble;
    [eventBuilder makeNewEventOfType:CDEStoreModificationEventTypeBaseline uniqueIdentifier:nil];
    [eventBuilder performBlockAndWait:^{
        // Use distant past for the time, so the leeched data gets less
        // priority than existing data.
        eventBuilder.event.globalCount = 0;
        eventBuilder.event.timestamp = [[NSDate distantPast] timeIntervalSinceReferenceDate];
    }];
    
    NSMutableSet *allObjects = [[NSMutableSet alloc] initWithCapacity:1000];
    [context performBlock:^{
        for (NSEntityDescription *entity in managedObjectModel) {
            NSFetchRequest *fetch = [[NSFetchRequest alloc] initWithEntityName:entity.name];
            fetch.fetchBatchSize = 100;
            fetch.includesSubentities = NO;
            
            NSArray *objects = [context executeFetchRequest:fetch error:&error];
            if (!objects) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completion) completion(error);
                });
                return;
            }
            [allObjects addObjectsFromArray:objects];
        }
        
        [eventBuilder addChangesForInsertedObjects:allObjects objectsAreSaved:YES inManagedObjectContext:context];
        
        [eventContext performBlock:^{
            [eventBuilder finalizeNewEvent];
            [eventContext save:&error];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(error);
            });
        }];
    }];
}

@end
