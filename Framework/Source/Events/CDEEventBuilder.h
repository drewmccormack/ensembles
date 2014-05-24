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
@class CDERevision;

typedef NS_ENUM(uint16_t, CDEUpdateStoreOption) {
    CDEUpdateStoreOptionNone = 0,
    CDEUpdateStoreOptionPreSaveInfo = 1 << 1,
    CDEUpdateStoreOptionUnsavedValue = 1 << 2,
    CDEUpdateStoreOptionSavedValue = 1 << 3
};

@interface CDEEventBuilder : NSObject

@property (nonatomic, strong, readonly) CDEEventStore *eventStore;
@property (nonatomic, strong, readonly) NSManagedObjectContext *eventManagedObjectContext;
@property (nonatomic, strong, readonly) CDEStoreModificationEvent *event;
@property (nonatomic, weak, readwrite) CDEPersistentStoreEnsemble *ensemble;
@property (nonatomic, assign, readonly) CDEStoreModificationEventType eventType;

- (id)initWithEventStore:(CDEEventStore *)eventStore;
- (id)initWithEventStore:(CDEEventStore *)eventStore eventManagedObjectContext:(NSManagedObjectContext *)context;

- (CDERevision *)makeNewEventOfType:(CDEStoreModificationEventType)type uniqueIdentifier:(NSString *)uniqueIdOrNil;
- (void)finalizeNewEvent;

- (void)performBlockAndWait:(CDECodeBlock)block; // Executes in eventManagedObjectContext queue

// These are call from thread of synced-store context
- (void)addChangesForInsertedObjects:(NSSet *)insertedObjects objectsAreSaved:(BOOL)saved inManagedObjectContext:(NSManagedObjectContext *)context;
- (NSDictionary *)changesDataForInsertedObjects:(NSSet *)insertedObjects objectsAreSaved:(BOOL)saved inManagedObjectContext:(NSManagedObjectContext *)context;
- (void)addInsertChangesForChangesData:(NSDictionary *)changesData;
- (NSArray *)addGlobalIdentifiersForInsertChangesData:(NSDictionary *)changesData;

- (void)addChangesForDeletedObjects:(NSSet *)deleted inManagedObjectContext:(NSManagedObjectContext *)context;
- (NSDictionary *)changesDataForDeletedObjects:(NSSet *)deletedObjects inManagedObjectContext:(NSManagedObjectContext *)context;
- (void)addDeleteChangesForChangesData:(NSDictionary *)changesData;

- (void)addChangesForUpdatedObjects:(NSSet *)updated inManagedObjectContext:(NSManagedObjectContext *)context options:(CDEUpdateStoreOption)options propertyChangeValuesByObjectID:(NSDictionary *)changedValuesByObjectID;
- (NSDictionary *)changesDataForUpdatedObjects:(NSSet *)updatedObjects inManagedObjectContext:(NSManagedObjectContext *)context options:(CDEUpdateStoreOption)options propertyChangeValuesByObjectID:(NSDictionary *)propertyChangeValuesByObjectID;
- (void)addUpdateChangesForChangesData:(NSDictionary *)changesData;

- (BOOL)addChangesForUnsavedManagedObjectContext:(NSManagedObjectContext *)contextWithChanges error:(NSError * __autoreleasing *)error;

@end
