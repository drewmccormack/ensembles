//
//  CDERebaserTests.m
//  Ensembles Mac
//
//  Created by Drew McCormack on 16/01/14.
//  Copyright (c) 2014 Drew McCormack. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "CDEEventStoreTestCase.h"
#import "CDERebaser.h"
#import "CDEStoreModificationEvent.h"
#import "CDEGlobalIdentifier.h"
#import "CDEEventRevision.h"
#import "CDERevisionSet.h"
#import "CDEPropertyChangeValue.h"
#import "CDERevision.h"

@interface CDERebaser (TestMethods)

- (CDEGlobalCount)globalCountForNewBaseline;

@end

@interface CDERebaserTests : CDEEventStoreTestCase

@end

@implementation CDERebaserTests {
    NSManagedObjectContext *context;
    CDERebaser *rebaser;
}

- (void)setUp
{
    [super setUp];
    context = self.eventStore.managedObjectContext;
    rebaser = [[CDERebaser alloc] initWithEventStore:(id)self.eventStore];
}

- (BOOL)shouldRebase
{
    __block BOOL should = NO;
    [rebaser shouldRebaseWithCompletion:^(BOOL result) {
        should = result;
        [self stopAsyncOp];
    }];
    [self waitForAsyncOpToFinish];
    return should;
}

- (void)testEmptyEventStoreNeedsRebasing
{
    XCTAssertTrue([self shouldRebase], @"Empty store should be rebased to give it a baseline");
}

- (void)testEventStoreWithNoBaselineNeedsRebasing
{
    [self addEventsForType:CDEStoreModificationEventTypeMerge storeId:@"123" globalCounts:@[@0] revisions:@[@0]];
    XCTAssertTrue([self shouldRebase], @"Store with events, but no baseline, should need a new baseline");
}

- (void)testEventStoreWithFewEventsDoesNotNeedRebasing
{
    NSArray *baselines = [self addEventsForType:CDEStoreModificationEventTypeBaseline storeId:@"store1" globalCounts:@[@0] revisions:@[@0]];
    
    [context performBlockAndWait:^{
        CDEStoreModificationEvent *baseline = baselines.lastObject;
        CDEEventRevision *rev;
        rev = [CDEEventRevision makeEventRevisionForPersistentStoreIdentifier:@"123" revisionNumber:0 inManagedObjectContext:context];
        baseline.eventRevisionsOfOtherStores = [NSSet setWithObject:rev];
        [context save:NULL];
    }];

    [self addEventsForType:CDEStoreModificationEventTypeMerge storeId:@"123" globalCounts:@[@1, @2] revisions:@[@1, @2]];
    
    XCTAssertFalse([self shouldRebase], @"Store with only a few events should not rebase, even if baseline is small");
}

- (void)testBaselineMissingADeviceNeedsRebasing
{
    [self addEventsForType:CDEStoreModificationEventTypeBaseline storeId:@"store1" globalCounts:@[@0] revisions:@[@0]];
    [self addEventsForType:CDEStoreModificationEventTypeMerge storeId:@"123" globalCounts:@[@1, @2] revisions:@[@1, @2]];
    XCTAssertTrue([self shouldRebase], @"If baseline misses a device, it should rebase");
}

- (void)testRebasingEmptyEventStoreGeneratesBaseline
{
    [rebaser rebaseWithCompletion:^(NSError *error) {
        XCTAssertNil(error, @"Rebasing should succeed: %@", error);
        [context performBlock:^{
            NSArray *events = [self storeModEvents];
            CDEStoreModificationEvent *event = events.lastObject;
            XCTAssertNotNil(events, @"Event fetch failed");
            XCTAssertEqual(events.count, (NSUInteger)1, @"Should be a baseline");
            XCTAssertEqual(event.type, CDEStoreModificationEventTypeBaseline, @"Wrong event type for baseline");
            XCTAssertEqual(event.globalCount, (CDEGlobalCount)0, @"Wrong global count for baseline");
            XCTAssertEqual(event.eventRevision.revisionNumber, (CDERevisionNumber)0, @"Wrong revision number for baseline");

            [self performSelectorOnMainThread:@selector(stopAsyncOp) withObject:nil waitUntilDone:NO];
        }];
    }];
    [self waitForAsyncOpToFinish];
}

- (void)testDevicesWhichHaveNoEventsSinceBaselineAreIgnoredInGlobalCountCutoff
{
    NSArray *baselines = [self addEventsForType:CDEStoreModificationEventTypeBaseline storeId:@"store1" globalCounts:@[@0] revisions:@[@0]];
    
    [context performBlockAndWait:^{
        CDEStoreModificationEvent *baseline = baselines.lastObject;
        CDEEventRevision *rev;
        rev = [CDEEventRevision makeEventRevisionForPersistentStoreIdentifier:@"123" revisionNumber:0 inManagedObjectContext:context];
        baseline.eventRevisionsOfOtherStores = [NSSet setWithObject:rev];
        [context save:NULL];
    }];
    
    [self addEventsForType:CDEStoreModificationEventTypeMerge storeId:@"123" globalCounts:@[@1, @2] revisions:@[@1, @2]];
    
    XCTAssertEqual([rebaser globalCountForNewBaseline], (CDEGlobalCount)2, @"Wrong global count");
}

- (void)testRevisionsForRebasingWithStoreNotInBaseline
{
    [self addEventsForType:CDEStoreModificationEventTypeBaseline storeId:@"store1" globalCounts:@[@10] revisions:@[@110]];
    [self addEventsForType:CDEStoreModificationEventTypeSave storeId:@"123" globalCounts:@[@0, @1] revisions:@[@0, @1]];
    [rebaser rebaseWithCompletion:^(NSError *error) {
        XCTAssertNil(error, @"Error was not nil");
        [context performBlockAndWait:^{
            XCTAssertEqual([[self storeModEvents] count], (NSUInteger)1, @"Should only be baseline left");
            
            CDEStoreModificationEvent *baseline = [self fetchBaseline];
            CDERevisionSet *revSet = baseline.revisionSet;
            CDERevision *revForStore1 = [revSet revisionForPersistentStoreIdentifier:@"store1"];
            CDERevision *revFor123 = [revSet revisionForPersistentStoreIdentifier:@"123"];
            CDEGlobalCount baselineGlobalCount = baseline.globalCount;
            XCTAssertEqual(baselineGlobalCount, (CDEGlobalCount)1, @"Wrong global count");
            XCTAssertEqual(revForStore1.revisionNumber, (CDERevisionNumber)110, @"Wrong revision number for store1");
            XCTAssertEqual(revFor123.revisionNumber, (CDERevisionNumber)1, @"Wrong revision number for 123");
        }];
        [self stopAsyncOp];
    }];
    [self waitForAsyncOpToFinish];
}

- (void)testNewBaselineIncludesUpToGlobalCountOfStoreWithLeastRecentEvents
{
    NSArray *baselines = [self addEventsForType:CDEStoreModificationEventTypeBaseline storeId:@"store1" globalCounts:@[@10] revisions:@[@110]];
    [self addEventsForType:CDEStoreModificationEventTypeSave storeId:@"store1" globalCounts:@[@20, @21] revisions:@[@111, @112]];
    
    [context performBlockAndWait:^{
        CDEStoreModificationEvent *baseline = baselines.lastObject;
        CDEEventRevision *rev;
        rev = [CDEEventRevision makeEventRevisionForPersistentStoreIdentifier:@"123" revisionNumber:1 inManagedObjectContext:context];
        baseline.eventRevisionsOfOtherStores = [NSSet setWithObject:rev];
        [context save:NULL];
    }];
    
    [self addEventsForType:CDEStoreModificationEventTypeSave storeId:@"123" globalCounts:@[@16, @30] revisions:@[@2, @3]];
    
    [rebaser rebaseWithCompletion:^(NSError *error) {
        [context performBlockAndWait:^{
            CDEStoreModificationEvent *baseline = [self fetchBaseline];
            CDERevisionSet *revSet = baseline.revisionSet;
            CDERevision *revForStore1 = [revSet revisionForPersistentStoreIdentifier:@"store1"];
            CDERevision *revFor123 = [revSet revisionForPersistentStoreIdentifier:@"123"];
            CDEGlobalCount baselineGlobalCount = baseline.globalCount;
            XCTAssertEqual(baselineGlobalCount, (CDEGlobalCount)21, @"Wrong global count");
            XCTAssertEqual(revForStore1.revisionNumber, (CDERevisionNumber)112, @"Wrong revision number for store1");
            XCTAssertEqual(revFor123.revisionNumber, (CDERevisionNumber)2, @"Wrong revision number for 123");
            XCTAssertEqual([[self storeModEvents] count], (NSUInteger)2, @"Wrong number of events. Should have baseline and 1 other.");
        }];
        [self stopAsyncOp];
    }];
    [self waitForAsyncOpToFinish];
}

- (void)testDeletingRedundantEvents
{
    NSArray *baselines = [self addEventsForType:CDEStoreModificationEventTypeBaseline storeId:@"store1" globalCounts:@[@0] revisions:@[@10]];
    
    [context performBlockAndWait:^{
        CDEStoreModificationEvent *baseline = baselines.lastObject;
        CDEEventRevision *rev;
        rev = [CDEEventRevision makeEventRevisionForPersistentStoreIdentifier:@"123" revisionNumber:5 inManagedObjectContext:context];
        baseline.eventRevisionsOfOtherStores = [NSSet setWithObject:rev];
        [context save:NULL];
    }];
    
    [self addEventsForType:CDEStoreModificationEventTypeSave storeId:@"123" globalCounts:@[@1, @2, @3, @4] revisions:@[@3, @4, @5, @6]];
    [self addEventsForType:CDEStoreModificationEventTypeMerge storeId:@"store1" globalCounts:@[@1, @2, @3, @4] revisions:@[@9, @10, @11, @12]];
    
    [rebaser deleteEventsPreceedingBaselineWithCompletion:^(NSError *error) {
        XCTAssertNil(error, @"Deleting failed");
        [context performBlockAndWait:^{
            NSArray *types = @[@(CDEStoreModificationEventTypeSave), @(CDEStoreModificationEventTypeMerge)];
            NSArray *events123 = [CDEStoreModificationEvent fetchStoreModificationEventsWithTypes:types persistentStoreIdentifier:@"123" inManagedObjectContext:context];
            NSArray *eventsStore1 = [CDEStoreModificationEvent fetchStoreModificationEventsWithTypes:types persistentStoreIdentifier:@"store1" inManagedObjectContext:context];
            XCTAssertEqual(events123.count, (NSUInteger)1, @"Wrong number of events for 123 store");
            XCTAssertEqual(eventsStore1.count, (NSUInteger)2, @"Wrong number of events for store1 store");
        }];
        [self stopAsyncOp];
    }];
    [self waitForAsyncOpToFinish];
}

- (void)testRebasingAttribute
{
    NSArray *baselines = [self addEventsForType:CDEStoreModificationEventTypeBaseline storeId:@"store1" globalCounts:@[@10] revisions:@[@110]];
    CDEStoreModificationEvent *baseline = baselines.lastObject;
    CDEStoreModificationEvent *event = [[self addEventsForType:CDEStoreModificationEventTypeSave storeId:@"store1" globalCounts:@[@20] revisions:@[@111]] lastObject];
    
    [context performBlockAndWait:^{
        // Object change in baseline
        CDEGlobalIdentifier *globalId1 = [NSEntityDescription insertNewObjectForEntityForName:@"CDEGlobalIdentifier" inManagedObjectContext:context];
        globalId1.globalIdentifier = @"unique";
        globalId1.nameOfEntity = @"A";
        
        CDEObjectChange *change1 = [NSEntityDescription insertNewObjectForEntityForName:@"CDEObjectChange" inManagedObjectContext:context];
        change1.storeModificationEvent = baseline;
        change1.type = CDEObjectChangeTypeInsert;
        change1.nameOfEntity = @"A";
        change1.globalIdentifier = globalId1;
        
        CDEPropertyChangeValue *value1 = [[CDEPropertyChangeValue alloc] initWithType:CDEPropertyChangeTypeAttribute propertyName:@"property"];
        value1.value = @(10);
        change1.propertyChangeValues = @[value1];
        
        // Object change outside baseline
        CDEObjectChange *change2 = [NSEntityDescription insertNewObjectForEntityForName:@"CDEObjectChange" inManagedObjectContext:context];
        change2.storeModificationEvent = event;
        change2.type = CDEObjectChangeTypeInsert;
        change2.nameOfEntity = @"A";
        change2.globalIdentifier = globalId1;
        
        CDEPropertyChangeValue *value2 = [[CDEPropertyChangeValue alloc] initWithType:CDEPropertyChangeTypeAttribute propertyName:@"property"];
        value2.value = @(11);
        change2.propertyChangeValues = @[value2];
        
        [context save:NULL];
    }];
    
    [rebaser rebaseWithCompletion:^(NSError *error) {
        [context performBlockAndWait:^{
            CDEStoreModificationEvent *baseline = [self fetchBaseline];
            XCTAssertEqual(baseline.objectChanges.count, (NSUInteger)1, @"Wrong number of object changes");
            
            NSArray *values = [baseline.objectChanges.anyObject propertyChangeValues];
            CDEPropertyChangeValue *value = values.lastObject;
            XCTAssertEqualObjects(value.value, @(11), @"Wrong attribute value");
        }];
        [self stopAsyncOp];
    }];
    [self waitForAsyncOpToFinish];
}

- (void)testRebasingAttributeWithSameGlobalIdButDifferentEntity
{
    NSArray *baselines = [self addEventsForType:CDEStoreModificationEventTypeBaseline storeId:@"store1" globalCounts:@[@10] revisions:@[@110]];
    CDEStoreModificationEvent *baseline = baselines.lastObject;
    CDEStoreModificationEvent *event = [[self addEventsForType:CDEStoreModificationEventTypeSave storeId:@"store1" globalCounts:@[@20] revisions:@[@111]] lastObject];
    
    [context performBlockAndWait:^{
        // Object change in baseline
        CDEGlobalIdentifier *globalId1 = [NSEntityDescription insertNewObjectForEntityForName:@"CDEGlobalIdentifier" inManagedObjectContext:context];
        globalId1.globalIdentifier = @"unique";
        globalId1.nameOfEntity = @"A";
        
        CDEObjectChange *change1 = [NSEntityDescription insertNewObjectForEntityForName:@"CDEObjectChange" inManagedObjectContext:context];
        change1.storeModificationEvent = baseline;
        change1.type = CDEObjectChangeTypeInsert;
        change1.nameOfEntity = @"A";
        change1.globalIdentifier = globalId1;
        
        CDEPropertyChangeValue *value1 = [[CDEPropertyChangeValue alloc] initWithType:CDEPropertyChangeTypeAttribute propertyName:@"property"];
        value1.value = @(10);
        change1.propertyChangeValues = @[value1];
        
        // Object change outside baseline
        CDEGlobalIdentifier *globalId2 = [NSEntityDescription insertNewObjectForEntityForName:@"CDEGlobalIdentifier" inManagedObjectContext:context];
        globalId2.globalIdentifier = @"unique";
        globalId2.nameOfEntity = @"B";
    
        CDEObjectChange *change2 = [NSEntityDescription insertNewObjectForEntityForName:@"CDEObjectChange" inManagedObjectContext:context];
        change2.storeModificationEvent = event;
        change2.type = CDEObjectChangeTypeInsert;
        change2.nameOfEntity = @"B";
        change2.globalIdentifier = globalId2;
        
        CDEPropertyChangeValue *value2 = [[CDEPropertyChangeValue alloc] initWithType:CDEPropertyChangeTypeAttribute propertyName:@"property"];
        value2.value = @(11);
        change2.propertyChangeValues = @[value2];
        
        [context save:NULL];
    }];
    
    [rebaser rebaseWithCompletion:^(NSError *error) {
        [context performBlockAndWait:^{
            CDEStoreModificationEvent *baseline = [self fetchBaseline];
            XCTAssertEqual(baseline.objectChanges.count, (NSUInteger)2, @"Wrong number of object changes");
        }];
        [self stopAsyncOp];
    }];
    [self waitForAsyncOpToFinish];
}

- (void)testRebasingToManyRelationship
{
    NSArray *baselines = [self addEventsForType:CDEStoreModificationEventTypeBaseline storeId:@"store1" globalCounts:@[@10] revisions:@[@110]];
    CDEStoreModificationEvent *baseline = baselines.lastObject;
    CDEStoreModificationEvent *event = [[self addEventsForType:CDEStoreModificationEventTypeSave storeId:@"store1" globalCounts:@[@20] revisions:@[@111]] lastObject];

    [context performBlockAndWait:^{
        // Object change in baseline
        CDEGlobalIdentifier *globalId1 = [NSEntityDescription insertNewObjectForEntityForName:@"CDEGlobalIdentifier" inManagedObjectContext:context];
        globalId1.globalIdentifier = @"unique";
        globalId1.nameOfEntity = @"A";
        
        CDEObjectChange *change1 = [NSEntityDescription insertNewObjectForEntityForName:@"CDEObjectChange" inManagedObjectContext:context];
        change1.storeModificationEvent = baseline;
        change1.type = CDEObjectChangeTypeInsert;
        change1.nameOfEntity = @"A";
        change1.globalIdentifier = globalId1;
        
        CDEPropertyChangeValue *value1 = [[CDEPropertyChangeValue alloc] initWithType:CDEPropertyChangeTypeToManyRelationship propertyName:@"property"];
        value1.addedIdentifiers = [NSSet setWithObjects:@"11", @"12", nil];
        value1.removedIdentifiers = [NSSet set];
        change1.propertyChangeValues = @[value1];
        
        // Object change outside baseline
        CDEObjectChange *change2 = [NSEntityDescription insertNewObjectForEntityForName:@"CDEObjectChange" inManagedObjectContext:context];
        change2.storeModificationEvent = event;
        change2.type = CDEObjectChangeTypeUpdate;
        change2.nameOfEntity = @"A";
        change2.globalIdentifier = globalId1;
        
        CDEPropertyChangeValue *value2 = [[CDEPropertyChangeValue alloc] initWithType:CDEPropertyChangeTypeToManyRelationship propertyName:@"property"];
        value2.addedIdentifiers = [NSSet setWithObjects:@"21", @"13", nil];
        value2.removedIdentifiers = [NSSet setWithObjects:@"11", @"22", nil];
        change2.propertyChangeValues = @[value2];
        
        [context save:NULL];
    }];
    
    [rebaser rebaseWithCompletion:^(NSError *error) {
        [context performBlockAndWait:^{
            CDEStoreModificationEvent *baseline = [self fetchBaseline];
            XCTAssertEqual(baseline.objectChanges.count, (NSUInteger)1, @"Wrong number of object changes");
            
            CDEObjectChange *change = baseline.objectChanges.anyObject;
            XCTAssertEqual(change.propertyChangeValues.count, (NSUInteger)1, @"Wrong number of changes");
            XCTAssertEqual(change.type, CDEObjectChangeTypeInsert, @"Wrong type");
            
            CDEPropertyChangeValue *value = change.propertyChangeValues.lastObject;
            XCTAssertEqual(value.type, CDEPropertyChangeTypeToManyRelationship, @"Wrong value type");
            
            NSSet *added = [NSSet setWithObjects:@"12", @"21", @"13", nil];
            XCTAssertEqualObjects(value.addedIdentifiers, added, @"Wrong added ids");
            XCTAssertEqualObjects(value.removedIdentifiers, [NSSet set], @"Wrong removed ids");
        }];
        [self stopAsyncOp];
    }];
    [self waitForAsyncOpToFinish];
}

- (void)testRebasingOrderedToManyRelationship
{
    NSArray *baselines = [self addEventsForType:CDEStoreModificationEventTypeBaseline storeId:@"store1" globalCounts:@[@10] revisions:@[@110]];
    CDEStoreModificationEvent *baseline = baselines.lastObject;
    CDEStoreModificationEvent *event = [[self addEventsForType:CDEStoreModificationEventTypeSave storeId:@"store1" globalCounts:@[@20] revisions:@[@111]] lastObject];
    
    [context performBlockAndWait:^{
        // Object change in baseline
        CDEGlobalIdentifier *globalId1 = [NSEntityDescription insertNewObjectForEntityForName:@"CDEGlobalIdentifier" inManagedObjectContext:context];
        globalId1.globalIdentifier = @"unique";
        globalId1.nameOfEntity = @"A";
        
        CDEObjectChange *change1 = [NSEntityDescription insertNewObjectForEntityForName:@"CDEObjectChange" inManagedObjectContext:context];
        change1.storeModificationEvent = baseline;
        change1.type = CDEObjectChangeTypeInsert;
        change1.nameOfEntity = @"A";
        change1.globalIdentifier = globalId1;
        
        CDEPropertyChangeValue *value1 = [[CDEPropertyChangeValue alloc] initWithType:CDEPropertyChangeTypeOrderedToManyRelationship propertyName:@"property"];
        value1.addedIdentifiers = [NSSet setWithObjects:@"11", @"12", nil];
        value1.removedIdentifiers = [NSSet set];
        value1.movedIdentifiersByIndex = @{@0 : @"11", @1 : @"12"};
        change1.propertyChangeValues = @[value1];
        
        // Object change outside baseline
        CDEObjectChange *change2 = [NSEntityDescription insertNewObjectForEntityForName:@"CDEObjectChange" inManagedObjectContext:context];
        change2.storeModificationEvent = event;
        change2.type = CDEObjectChangeTypeUpdate;
        change2.nameOfEntity = @"A";
        change2.globalIdentifier = globalId1;
        
        CDEPropertyChangeValue *value2 = [[CDEPropertyChangeValue alloc] initWithType:CDEPropertyChangeTypeOrderedToManyRelationship propertyName:@"property"];
        value2.addedIdentifiers = [NSSet setWithObjects:@"21", @"13", nil];
        value2.removedIdentifiers = [NSSet setWithObjects:@"11", @"22", nil];
        value2.movedIdentifiersByIndex = @{@0 : @"21", @1 : @"13", @2 : @"17", @3 : @"666"};
        change2.propertyChangeValues = @[value2];
        
        [context save:NULL];
    }];
    
    [rebaser rebaseWithCompletion:^(NSError *error) {
        [context performBlockAndWait:^{
            CDEStoreModificationEvent *baseline = [self fetchBaseline];
            XCTAssertEqual(baseline.objectChanges.count, (NSUInteger)1, @"Wrong number of object changes");
            
            CDEObjectChange *change = baseline.objectChanges.anyObject;
            XCTAssertEqual(change.propertyChangeValues.count, (NSUInteger)1, @"Wrong number of changes");
            XCTAssertEqual(change.type, CDEObjectChangeTypeInsert, @"Wrong type");
            
            CDEPropertyChangeValue *value = change.propertyChangeValues.lastObject;
            XCTAssertEqual(value.type, CDEPropertyChangeTypeOrderedToManyRelationship, @"Wrong value type");
            
            NSSet *added = [NSSet setWithObjects:@"12", @"21", @"13", nil];
            XCTAssertEqualObjects(value.addedIdentifiers, added, @"Wrong added ids");
            XCTAssertEqualObjects(value.removedIdentifiers, [NSSet set], @"Wrong removed ids");
            
            NSDictionary *moved = @{@0 : @"21", @1 : @"12", @2 : @"13"};
            XCTAssertEqualObjects(value.movedIdentifiersByIndex, moved, @"Wrong moved ids");
        }];
        [self stopAsyncOp];
    }];
    [self waitForAsyncOpToFinish];
}

- (NSArray *)addEventsForType:(CDEStoreModificationEventType)type storeId:(NSString *)storeId globalCounts:(NSArray *)globalCounts revisions:(NSArray *)revisions
{
    __block NSMutableArray *events = [NSMutableArray array];
    [context performBlockAndWait:^{
        for (NSUInteger i = 0; i < globalCounts.count; i++) {
            CDEStoreModificationEvent *event = [NSEntityDescription insertNewObjectForEntityForName:@"CDEStoreModificationEvent" inManagedObjectContext:context];
            event.type = type;
            event.globalCount = [globalCounts[i] integerValue];
            event.timestamp = 10.0;
            
            CDEEventRevision *rev;
            rev = [CDEEventRevision makeEventRevisionForPersistentStoreIdentifier:storeId revisionNumber:[revisions[i] integerValue] inManagedObjectContext:context];
            event.eventRevision = rev;
            
            [events addObject:event];
        }
        
        [context save:NULL];
    }];
    
    return events;
}

- (void)waitForAsyncOpToFinish
{
    CFRunLoopRun();
}

- (void)stopAsyncOp
{
    CFRunLoopStop(CFRunLoopGetCurrent());
}

- (NSArray *)storeModEvents
{
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"CDEStoreModificationEvent"];
    return [context executeFetchRequest:fetch error:NULL];
}

- (CDEStoreModificationEvent *)fetchBaseline
{
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"CDEStoreModificationEvent"];
    fetch.predicate = [NSPredicate predicateWithFormat:@"type = %d", CDEStoreModificationEventTypeBaseline];
    return [[context executeFetchRequest:fetch error:NULL] lastObject];
}

@end
