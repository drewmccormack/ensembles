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
