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

- (void)testEmptyEventStoreNeedsRebasing
{
    XCTAssertTrue([rebaser shouldRebase], @"Empty store should be rebased to give it a baseline");
}

- (void)testEventStoreWithNoBaselineNeedsRebasing
{
    [self addEventsForType:CDEStoreModificationEventTypeMerge storeId:@"123" globalCounts:@[@0] revisions:@[@0]];
    XCTAssertTrue([rebaser shouldRebase], @"Store with events, but no baseline, should need a new baseline");
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
    
    XCTAssertFalse([rebaser shouldRebase], @"Store with only a few events should not rebase, even if baseline is small");
}

- (void)testBaselineMissingADeviceNeedsRebasing
{
    [self addEventsForType:CDEStoreModificationEventTypeBaseline storeId:@"store1" globalCounts:@[@0] revisions:@[@0]];
    [self addEventsForType:CDEStoreModificationEventTypeMerge storeId:@"123" globalCounts:@[@1, @2] revisions:@[@1, @2]];
    XCTAssertTrue([rebaser shouldRebase], @"If baseline misses a device, it should rebase");
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
