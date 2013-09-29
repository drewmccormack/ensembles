//
//  CDEEventFactory.h
//  Ensembles
//
//  Created by Drew McCormack on 22/09/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#import "CDEDefines.h"
#import "CDEStoreModificationEvent.h"

@class CDEStoreModificationEvent;
@class CDEEventStore;
@class CDEEventBuilder;
@class CDEPersistentStoreEnsemble;

@interface CDEEventBuilder : NSObject

@property (nonatomic, readonly) CDEEventStore *eventStore;
@property (nonatomic, readonly) NSManagedObjectContext *eventManagedObjectContext;
@property (nonatomic, readonly) CDEStoreModificationEvent *event;
@property (nonatomic, readwrite, weak) CDEPersistentStoreEnsemble *ensemble;

- (id)initWithEventStore:(CDEEventStore *)eventStore;
- (id)initWithEventStore:(CDEEventStore *)eventStore eventManagedObjectContext:(NSManagedObjectContext *)context;

- (void)makeNewEventOfType:(CDEStoreModificationEventType)type;

- (void)performBlockAndWait:(CDECodeBlock)block; // Executes in eventManagedObjectContext queue

// These are call from thread of synced-store context
- (void)addChangesForInsertedObjects:(NSSet *)inserted inManagedObjectContext:(NSManagedObjectContext *)context;
- (void)addChangesForDeletedObjects:(NSSet *)deleted inManagedObjectContext:(NSManagedObjectContext *)context;
- (void)addChangesForUpdatedObjects:(NSSet *)updated inManagedObjectContext:(NSManagedObjectContext *)context changedValuesByObjectID:(NSDictionary *)changedValuesByObjectID;
- (void)addChangesForUnsavedUpdatedObjects:(NSSet *)updated inManagedObjectContext:(NSManagedObjectContext *)context; // Only use pre-save. Requires changedValues to be available.

- (BOOL)addChangesForUnsavedManagedObjectContext:(NSManagedObjectContext *)contextWithChanges error:(NSError * __autoreleasing *)error;

@end
