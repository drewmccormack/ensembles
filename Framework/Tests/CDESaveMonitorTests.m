//
//  CDEManagedObjectContextSaveMonitorTests.m
//  Ensembles
//
//  Created by Drew McCormack on 10/07/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "CDEEventStoreTestCase.h"
#import "CDESaveMonitor.h"
#import "CDEStoreModificationEvent.h"
#import "CDEObjectChange.h"
#import "CDEEventRevision.h"
#import "CDEGlobalIdentifier.h"
#import "CDEPropertyChangeValue.h"

@interface CDESaveMonitorTests : CDEEventStoreTestCase

@end

@implementation CDESaveMonitorTests {
    CDESaveMonitor *saveMonitor;
    NSPersistentStore *persistentStore;
    NSManagedObject *parent;
    NSManagedObjectContext *eventMOC;
}

+ (void)setUp
{
    [super setUp];
    [self setUseDiskStore:YES];
}

- (void)setUp
{
    [super setUp];
    
    persistentStore = self.testManagedObjectContext.persistentStoreCoordinator.persistentStores[0];
    
    saveMonitor = [[CDESaveMonitor alloc] init];
    saveMonitor.eventStore = (id)self.eventStore;
    saveMonitor.storePath = persistentStore.URL.path;
    
    eventMOC = self.eventStore.managedObjectContext;
    parent = [NSEntityDescription insertNewObjectForEntityForName:@"Parent" inManagedObjectContext:self.testManagedObjectContext];
    NSDate *date = [NSDate dateWithTimeIntervalSinceReferenceDate:0.0];
    [parent setValue:@"bob" forKey:@"name"];
    [parent setValue:date forKey:@"date"];
}

- (void)tearDown
{
    [saveMonitor stopMonitoring];
    saveMonitor = nil;
    persistentStore = nil;
    [super tearDown];
}

- (void)saveContext
{
    XCTAssertTrue([self.testManagedObjectContext save:NULL], @"Save failed");
    
    // This ensures the async created save event is in the event store
    [eventMOC performBlockAndWait:^{
        [self.eventStore updateRevisionsForSave];
    }];
}

- (void)testNoSaveTriggersNoEventCreation
{
    [eventMOC performBlockAndWait:^{
        NSError *error = nil;
        NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"CDEStoreModificationEvent"];
        XCTAssertEqual([eventMOC countForFetchRequest:fetch error:&error], (NSUInteger)0, @"Should be no events before save");
        XCTAssertNil(error, @"Error occurred in fetch");
    }];
}

- (void)testIfSaveTriggersEventCreation
{
    [self saveContext];
    [eventMOC performBlockAndWait:^{
        NSError *error = nil;
        NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"CDEStoreModificationEvent"];
        XCTAssertEqual([eventMOC countForFetchRequest:fetch error:&error], (NSUInteger)1, @"Should be one event after save");
        XCTAssertNil(error, @"Error occurred in fetch");
    }];
}

- (NSArray *)fetchModEvents
{
    NSError *error = nil;
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"CDEStoreModificationEvent"];
    fetch.sortDescriptors = @[
        [NSSortDescriptor sortDescriptorWithKey:@"eventRevision.persistentStoreIdentifier" ascending:YES],
        [NSSortDescriptor sortDescriptorWithKey:@"eventRevision.revisionNumber" ascending:YES]
    ];
    NSArray *modEvents = [eventMOC executeFetchRequest:fetch error:&error];
    return modEvents;
}

- (void)testInsertGeneratesObjectChange
{
    [self saveContext];
    [eventMOC performBlockAndWait:^{
        NSArray *modEvents = [self fetchModEvents];
        XCTAssertNotNil(modEvents, @"Fetch failed");
        XCTAssertEqual(modEvents.count, (NSUInteger)1, @"Wrong number of events");
    }];
}

- (void)testInsertStoreModificationEventTypeIsCorrect
{
    XCTAssertTrue([self.testManagedObjectContext save:NULL], @"Save failed");
    [eventMOC performBlockAndWait:^{
        NSArray *modEvents = [self fetchModEvents];
        CDEStoreModificationEvent *modEvent = modEvents.lastObject;
        XCTAssertEqual(modEvent.type, CDEStoreModificationEventTypeSave, @"Wrong mod event type");
    }];
}

- (void)testObjectChangeCountForInsert
{
    XCTAssertTrue([self.testManagedObjectContext save:NULL], @"Save failed");
    [eventMOC performBlockAndWait:^{
        NSArray *modEvents = [self fetchModEvents];
        CDEStoreModificationEvent *modEvent = modEvents.lastObject;
        NSSet *objectChanges = modEvent.objectChanges;
        XCTAssertEqual(objectChanges.count, (NSUInteger)1, @"Wrong number of object changes");
    }];
}

- (void)testObjectChangeTypeForInsert
{
    [self saveContext];
    [eventMOC performBlockAndWait:^{
        NSArray *modEvents = [self fetchModEvents];
        CDEStoreModificationEvent *modEvent = modEvents.lastObject;
        NSSet *objectChanges = modEvent.objectChanges;
        CDEObjectChange *change = objectChanges.anyObject;
        XCTAssertEqual(change.type, CDEObjectChangeTypeInsert, @"Change was not insert");
    }];
}

- (void)testGlobalIdentifierIsGeneratedForInsert
{
    XCTAssertTrue([self.testManagedObjectContext save:NULL], @"Save failed");
    [eventMOC performBlockAndWait:^{
        NSArray *modEvents = [self fetchModEvents];
        CDEStoreModificationEvent *modEvent = modEvents.lastObject;
        NSSet *objectChanges = modEvent.objectChanges;
        CDEObjectChange *change = objectChanges.anyObject;
        XCTAssertNotNil(change.globalIdentifier, @"Global identifier was nil");
        XCTAssertNotNil(change.globalIdentifier.globalIdentifier, @"Global identifier was nil");
        XCTAssertNotNil(change.globalIdentifier.storeURI, @"Global identifier was nil");
    }];
}

- (void)testGlobalCountForOneSave
{
    XCTAssertTrue([self.testManagedObjectContext save:NULL], @"Save failed");
    [eventMOC performBlockAndWait:^{
        NSArray *modEvents = [self fetchModEvents];
        CDEStoreModificationEvent *modEvent = modEvents.lastObject;
        XCTAssertEqual(modEvent.globalCount, (CDEGlobalCount)0, @"Wrong global count. Should be 1, because there is a store import event.");
    }];
}

- (void)testGlobalCountForTwoSaves
{
    [self saveContext];
    
    NSDate *newDate = [NSDate dateWithTimeIntervalSinceReferenceDate:0.1];
    [parent setValue:newDate forKey:@"date"];
    [self saveContext];
    
    [eventMOC performBlockAndWait:^{
        NSArray *modEvents = [self fetchModEvents];
        CDEStoreModificationEvent *modEvent = modEvents.lastObject;
        XCTAssertEqual(modEvent.globalCount, (CDEGlobalCount)1, @"Wrong global count.");
    }];
}

- (void)testUpdateGeneratesModEvent
{
    XCTAssertTrue([self.testManagedObjectContext save:NULL], @"Save failed");
    
    NSDate *newDate = [NSDate dateWithTimeIntervalSinceReferenceDate:0.1];
    [parent setValue:newDate forKey:@"date"];
    XCTAssertTrue([self.testManagedObjectContext save:NULL], @"Second save failed");
    
    [eventMOC performBlockAndWait:^{
        NSArray *modEvents = [self fetchModEvents];
        XCTAssertNotNil(modEvents, @"Fetch failed");
        XCTAssertEqual(modEvents.count, (NSUInteger)2, @"Wrong number of events");
    }];
}

- (void)testUpdateWithNilValue
{
    [self saveContext];

    [parent setValue:nil forKey:@"name"];
    XCTAssertTrue([self.testManagedObjectContext save:NULL], @"Second save failed");
    [self.eventStore updateRevisionsForSave];

    [eventMOC performBlockAndWait:^{
        NSArray *modEvents = [self fetchModEvents];
        CDEStoreModificationEvent *modEvent = modEvents.lastObject;
        NSSet *objectChanges = modEvent.objectChanges;
        CDEObjectChange *change = objectChanges.anyObject;
        XCTAssertEqual(change.propertyChangeValues.count, (NSUInteger)1, @"Wrong number of changes");
        
        CDEPropertyChangeValue *newValue = change.propertyChangeValues.lastObject;
        XCTAssertNil(newValue.value, @"Non-nil value");
        XCTAssertEqual(newValue.type, CDEPropertyChangeTypeAttribute, @"Wrong type");
    }];
}

- (void)testSaveRevisionNumbers
{
    [self saveContext];
    
    NSDate *newDate = [NSDate dateWithTimeIntervalSinceReferenceDate:0.1];
    [parent setValue:newDate forKey:@"date"];
    [self saveContext];

    [eventMOC performBlockAndWait:^{
        NSArray *modEvents = [self fetchModEvents];
        CDEStoreModificationEvent *firstEvent = modEvents[0];
        CDEStoreModificationEvent *secondEvent = modEvents[1];
        CDEEventRevision *firstEventRevision = firstEvent.eventRevision;
        CDEEventRevision *secondEventRevision = secondEvent.eventRevision;
        XCTAssertEqual(firstEventRevision.revisionNumber, (CDERevisionNumber)0, @"Wrong revision for first event");
        XCTAssertEqual(secondEventRevision.revisionNumber, (CDERevisionNumber)1, @"Wrong revision for second event");
    }];
}

- (void)testRevisionNumbersOfOtherStoresForASingleStore
{
    [self saveContext];
    [eventMOC performBlockAndWait:^{
        NSArray *modEvents = [self fetchModEvents];
        CDEStoreModificationEvent *firstEvent = modEvents[0];
        XCTAssertNotNil(firstEvent.eventRevisionsOfOtherStores, @"eventRevisionsOfOtherStores should not be nil");
        XCTAssertEqual(firstEvent.eventRevisionsOfOtherStores.count, (NSUInteger)0, @"Should have no revisions when only one store");
    }];
}

- (void)addEventForRevision:(CDERevisionNumber)revision store:(NSString *)store
{
    [eventMOC performBlockAndWait:^{
        CDEStoreModificationEvent *otherStoreEvent = [NSEntityDescription insertNewObjectForEntityForName:@"CDEStoreModificationEvent" inManagedObjectContext:eventMOC];
        CDEEventRevision *eventRevision = [NSEntityDescription insertNewObjectForEntityForName:@"CDEEventRevision" inManagedObjectContext:eventMOC];
        eventRevision.persistentStoreIdentifier = store;
        eventRevision.revisionNumber = revision;
        otherStoreEvent.eventRevision = eventRevision;
        otherStoreEvent.timestamp = 10.0;
    }];
}

- (void)testRevisionNumbersOfOtherStoresForTwoStoresWithNoPreviousMerge
{
    [self addEventForRevision:4 store:@"store0"];
    
    [self saveContext];
    
    [eventMOC performBlockAndWait:^{
        NSArray *modEvents = [self fetchModEvents];
        XCTAssertEqual(modEvents.count, (NSUInteger)2, @"Should have two mod events");
        
        CDEStoreModificationEvent *event = modEvents[modEvents.count-1];
        XCTAssertNotNil(event.eventRevisionsOfOtherStores, @"eventRevisionsOfOtherStores should not be nil");
        XCTAssertEqual(event.eventRevisionsOfOtherStores.count, (NSUInteger)0, @"Should have zero other stores, because no merges have occurred");
    }];
}

- (void)addMergeEventForOtherStoreIds:(NSArray *)otherStoreIds
{
    [self.eventStore updateRevisionsForMerge];
    [eventMOC performBlockAndWait:^{
        CDEStoreModificationEvent *mergeEvent = [NSEntityDescription insertNewObjectForEntityForName:@"CDEStoreModificationEvent" inManagedObjectContext:eventMOC];
        mergeEvent.type = CDEStoreModificationEventTypeMerge;
        mergeEvent.timestamp = 10.0;
        mergeEvent.eventRevision = [CDEEventRevision makeEventRevisionForPersistentStoreIdentifier:@"store1" revisionNumber:self.eventStore.lastMergeRevisionSaved inManagedObjectContext:eventMOC];
        
        NSMutableSet *revs = [[NSMutableSet alloc] init];
        for (NSString *otherStoreId in otherStoreIds) {
            CDEEventRevision *otherRev = [CDEEventRevision makeEventRevisionForPersistentStoreIdentifier:otherStoreId revisionNumber:4 inManagedObjectContext:eventMOC];
            [revs addObject:otherRev];
        }
        mergeEvent.eventRevisionsOfOtherStores = revs;

        [eventMOC save:NULL];
    }];
}

- (void)testRevisionNumbersOfOtherStoresForTwoStoresPostMerge
{
    [self addEventForRevision:4 store:@"store0"];
    [self addMergeEventForOtherStoreIds:@[@"store0"]];

    [self saveContext];

    [eventMOC performBlockAndWait:^{
        NSArray *modEvents = [self fetchModEvents];
        CDEStoreModificationEvent *event = modEvents[modEvents.count-1];
        XCTAssertNotNil(event.eventRevisionsOfOtherStores, @"eventRevisionsOfOtherStores should not be nil");
        XCTAssertEqual(event.eventRevisionsOfOtherStores.count, (NSUInteger)1, @"Should have one other store");
        
        CDEEventRevision *otherRevision = event.eventRevisionsOfOtherStores.anyObject;
        XCTAssertEqualObjects(otherRevision.persistentStoreIdentifier, @"store0", @"Wrong store id");
        XCTAssertEqual(otherRevision.revisionNumber, (CDERevisionNumber)4, @"Wrong revision number for other store");
    }];
}

- (void)testRevisionNumbersOfOtherStoresForTwoStoresWithMultipleExistingRevisions
{
    [self addEventForRevision:2 store:@"store0"];
    [self addEventForRevision:4 store:@"store0"];
    [self addMergeEventForOtherStoreIds:@[@"store0"]];

    [self saveContext];
    
    [eventMOC performBlockAndWait:^{
        NSArray *modEvents = [self fetchModEvents];
        XCTAssertEqual(modEvents.count, (NSUInteger)4, @"Wrong number of mod events");
        
        CDEStoreModificationEvent *event = modEvents[modEvents.count-1];
        XCTAssertNotNil(event.eventRevisionsOfOtherStores, @"eventRevisionsOfOtherStores should not be nil");
        XCTAssertEqual(event.eventRevisionsOfOtherStores.count, (NSUInteger)1, @"Should have one other store");
        
        CDEEventRevision *otherRevision = event.eventRevisionsOfOtherStores.anyObject;
        XCTAssertEqualObjects(otherRevision.persistentStoreIdentifier, @"store0", @"Wrong store id");
        XCTAssertEqual(otherRevision.revisionNumber, (CDERevisionNumber)4, @"Wrong revision number for other store");
    }];
}

- (void)testRevisionNumbersOfOtherStoresForThreeStores
{
    [self addEventForRevision:4 store:@"store0"];
    [self addEventForRevision:0 store:@"aaastore"];
    [self addMergeEventForOtherStoreIds:@[@"store0", @"aaastore"]];

    XCTAssertTrue([self.testManagedObjectContext save:NULL], @"Save failed");
    
    [eventMOC performBlockAndWait:^{
        NSArray *modEvents = [self fetchModEvents];
        XCTAssertEqual(modEvents.count, (NSUInteger)4, @"Should have 4 mod events");
        
        CDEStoreModificationEvent *event = modEvents[modEvents.count-1];
        XCTAssertNotNil(event.eventRevisionsOfOtherStores, @"eventRevisionsOfOtherStores should not be nil");
        XCTAssertEqual(event.eventRevisionsOfOtherStores.count, (NSUInteger)2, @"Should have two other stores");
    }];
}

- (void)testUpdateGeneratesObjectChanges
{
    [self saveContext];
    
    NSDate *newDate = [NSDate dateWithTimeIntervalSinceReferenceDate:0.1];
    [parent setValue:newDate forKey:@"date"];
    [self saveContext];
    
    [eventMOC performBlockAndWait:^{
        NSArray *modEvents = [self fetchModEvents];
        CDEStoreModificationEvent *modEvent = modEvents.lastObject;
        NSSet *objectChanges = modEvent.objectChanges;
        XCTAssertEqual(objectChanges.count, (NSUInteger)1, @"Wrong number of object changes");
        
        CDEObjectChange *change = objectChanges.anyObject;
        XCTAssertEqual(change.type, CDEObjectChangeTypeUpdate, @"Change was not update");
        
        NSArray *propertyChanges = change.propertyChangeValues;
        XCTAssertEqual(propertyChanges.count, (NSUInteger)1, @"Wrong number of property changes");
    }];
}

- (void)testDeletionGeneratesObjectChange
{
    [self saveContext];

    [self.testManagedObjectContext deleteObject:parent];
    
    XCTAssertTrue([self.testManagedObjectContext save:NULL], @"Second save failed");
    [self.eventStore updateRevisionsForSave];

    [eventMOC performBlockAndWait:^{
        NSArray *modEvents = [self fetchModEvents];
        XCTAssertNotNil(modEvents, @"Fetch failed");
        XCTAssertEqual(modEvents.count, (NSUInteger)2, @"Wrong number of events");
        
        CDEStoreModificationEvent *modEvent = modEvents.lastObject;
        NSSet *objectChanges = modEvent.objectChanges;
        XCTAssertEqual(objectChanges.count, (NSUInteger)1, @"Wrong number of object changes");

        CDEObjectChange *change = objectChanges.anyObject;
        XCTAssertEqual(change.type, CDEObjectChangeTypeDelete, @"Wrong change type");
    }];
}

@end
