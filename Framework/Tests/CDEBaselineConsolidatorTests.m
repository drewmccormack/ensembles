//
//  CDEBaselineConsolidatorTests.m
//  Ensembles Mac
//
//  Created by Drew McCormack on 04/12/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "CDEEventStoreTestCase.h"
#import "CDEBaselineConsolidator.h"
#import "CDEStoreModificationEvent.h"
#import "CDEEventRevision.h"
#import "CDERevisionSet.h"
#import "CDERevision.h"

@interface CDEBaselineConsolidatorTests : CDEEventStoreTestCase

@end

@implementation CDEBaselineConsolidatorTests {
    NSManagedObjectContext *context;
    CDEBaselineConsolidator *consolidator;
}

- (void)setUp
{
    [super setUp];
    context = self.eventStore.managedObjectContext;
    consolidator = [[CDEBaselineConsolidator alloc] initWithEventStore:(id)self.eventStore];
}

- (void)testConsolidationNotNeededForNoBaselines
{
    XCTAssertFalse([consolidator baselineNeedsConsolidation], @"Should not need to consolidate empty store");
}

- (void)testConsolidationNotNeededForOneBaseline
{
    [context performBlockAndWait:^{
        CDEStoreModificationEvent *event = [NSEntityDescription insertNewObjectForEntityForName:@"CDEStoreModificationEvent" inManagedObjectContext:context];
        event.type = CDEStoreModificationEventTypeBaseline;
        [context save:NULL];
    }];
    XCTAssertFalse([consolidator baselineNeedsConsolidation], @"Should not need to consolidate one baseline");
}

- (void)testConsolidationIsNeededForTwoBaselines
{
    [context performBlockAndWait:^{
        CDEStoreModificationEvent *event = [NSEntityDescription insertNewObjectForEntityForName:@"CDEStoreModificationEvent" inManagedObjectContext:context];
        event.type = CDEStoreModificationEventTypeBaseline;
        
        event = [NSEntityDescription insertNewObjectForEntityForName:@"CDEStoreModificationEvent" inManagedObjectContext:context];
        event.type = CDEStoreModificationEventTypeBaseline;
        
        [context save:NULL];
    }];
    XCTAssertTrue([consolidator baselineNeedsConsolidation], @"Should need to consolidate two baselines");
}

- (void)testConsolidatingMultipleBaselinesLeavesMostRecent
{
    [self addBaselineEventsForStoreId:@"123" globalCounts:@[@(2), @(0), @(1)] revisions:@[@(2), @(0), @(1)]];
    
    [consolidator consolidateBaselineWithCompletion:^(NSError *error) {
        [context performBlock:^{
            NSArray *events = [self storeModEvents];
            XCTAssertEqual(events.count, (NSUInteger)1, @"Should only be one baseline left");
            
            CDEStoreModificationEvent *event = events.lastObject;
            XCTAssertEqual(event.globalCount, (int64_t)2, @"Wrong event was kept");
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [self stopAsyncOp];
            });
        }];
    }];
    [self waitForAsyncOpToFinish];
}

- (void)testConsolidatingMultipleBaselinesOnWithVariousStoresLeavesMostRecent
{
    [self addBaselineEventsForStoreId:@"123" globalCounts:@[@(2), @(0), @(1)] revisions:@[@(2), @(0), @(1)]];
    [self addBaselineEventsForStoreId:@"234" globalCounts:@[@(3)] revisions:@[@(0)]];

    [consolidator consolidateBaselineWithCompletion:^(NSError *error) {
        [context performBlock:^{
            NSArray *events = [self storeModEvents];
            XCTAssertEqual(events.count, (NSUInteger)1, @"Should only be one baseline left");
            
            CDEStoreModificationEvent *event = events.lastObject;
            XCTAssertEqual(event.globalCount, (int64_t)3, @"Wrong event was kept");
            XCTAssertEqualObjects(event.eventRevision.persistentStoreIdentifier, @"store1", @"Store id should be the event store id");

            dispatch_async(dispatch_get_main_queue(), ^{
                [self stopAsyncOp];
            });
        }];
    }];
    [self waitForAsyncOpToFinish];
}

- (void)addBaselineEventsForStoreId:(NSString *)storeId globalCounts:(NSArray *)globalCounts revisions:(NSArray *)revisions
{
    [context performBlockAndWait:^{
        for (NSUInteger i = 0; i < globalCounts.count; i++) {
            CDEStoreModificationEvent *event = [NSEntityDescription insertNewObjectForEntityForName:@"CDEStoreModificationEvent" inManagedObjectContext:context];
            event.type = CDEStoreModificationEventTypeBaseline;
            event.globalCount = [globalCounts[i] integerValue];
            event.timestamp = 10.0;
            
            CDEEventRevision *rev;
            rev = [CDEEventRevision makeEventRevisionForPersistentStoreIdentifier:storeId revisionNumber:[revisions[i] integerValue] inManagedObjectContext:context];
            event.eventRevision = rev;
        }
        
        [context save:NULL];
    }];
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

@end
