//
//  CDERevisionManagerTests.m
//  Ensembles
//
//  Created by Drew McCormack on 25/08/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "CDEEventStoreTestCase.h"
#import "CDERevisionManager.h"
#import "CDEStoreModificationEvent.h"
#import "CDERevisionSet.h"
#import "CDEEventRevision.h"
#import "CDERevision.h"

@interface CDERevisionManagerTests : CDEEventStoreTestCase

@end

@implementation CDERevisionManagerTests {
    CDERevisionManager *revisionManager;
    CDEStoreModificationEvent *modEvent;
}

- (void)setUp
{
    [super setUp];
    
    revisionManager = [[CDERevisionManager alloc] initWithEventStore:(id)self.eventStore];
    revisionManager.managedObjectModelURL = self.testModelURL;
    
    NSManagedObjectContext *moc = self.eventStore.managedObjectContext;
    [moc performBlockAndWait:^{
        modEvent = [self addModEventForStore:@"store1" revision:0 globalCount:99 timestamp:124];
    }];
}

- (void)testMaximumGlobalCount
{
    XCTAssertEqual(revisionManager.maximumGlobalCount, (CDEGlobalCount)99, @"Wrong count");
}

- (void)testMaximumGlobalCountForMultipleEvents
{
    NSManagedObjectContext *moc = self.eventStore.managedObjectContext;
    [moc performBlockAndWait:^{
        modEvent = [self addModEventForStore:@"store2" revision:0 globalCount:150 timestamp:124];
    }];
    XCTAssertEqual(revisionManager.maximumGlobalCount, (CDEGlobalCount)150, @"Wrong count");
}

- (void)testMaximumGlobalCountForEmptyStore
{
    NSManagedObjectContext *moc = self.eventStore.managedObjectContext;
    [moc performBlockAndWait:^{
        [moc deleteObject:modEvent];
    }];
    
    XCTAssertEqual(revisionManager.maximumGlobalCount, (CDEGlobalCount)-1, @"Wrong count");
}

- (void)testMaximumGlobalCountForStoreWithBaseline
{
    NSManagedObjectContext *moc = self.eventStore.managedObjectContext;
    [moc performBlockAndWait:^{
        [moc deleteObject:modEvent];
        modEvent = [self addModEventForStore:@"store1" revision:5 globalCount:78 timestamp:124];
        modEvent.type = CDEStoreModificationEventTypeBaseline;
    }];
    
    XCTAssertEqual(revisionManager.maximumGlobalCount, (CDEGlobalCount)78, @"Wrong count");
}

- (void)testRecentRevisionsWithNoEvents
{
    NSManagedObjectContext *moc = self.eventStore.managedObjectContext;
    [moc performBlockAndWait:^{
        [moc deleteObject:modEvent];
    }];
    
    CDERevisionSet *result = [revisionManager revisionSetOfMostRecentEvents];
    XCTAssertEqual(result.numberOfRevisions, (NSUInteger)0, @"No events should give empty set");
}

- (void)testRecentRevisionsForSingleEvent
{
    NSManagedObjectContext *moc = self.eventStore.managedObjectContext;
    [moc performBlockAndWait:^{
        CDEEventRevision *eventRevision = [CDEEventRevision makeEventRevisionForPersistentStoreIdentifier:@"1234" revisionNumber:1 inManagedObjectContext:moc];
        modEvent.eventRevision = eventRevision;
        [moc processPendingChanges];
    }];
        
    CDERevisionSet *set = [revisionManager revisionSetOfMostRecentEvents];
    XCTAssertEqual(set.numberOfRevisions, (NSUInteger)1, @"Wrong number of revisions");
    
    CDERevision *revision = [set revisionForPersistentStoreIdentifier:@"1234"];
    XCTAssertEqual(revision.revisionNumber, (CDERevisionNumber)1, @"Wrong revision number");
}

- (void)testFetchingUncommittedEventsWithOnlyCurrentStoreEvent
{
    NSArray *events = [revisionManager fetchUncommittedStoreModificationEvents:NULL];
    XCTAssertNotNil(events, @"Failed to fetch uncommitted events");
    XCTAssertEqual(events.count, (NSUInteger)1, @"Wrong event count");
}

- (void)testFetchingUncommittedEventsWithOtherStoreEvent
{
    NSManagedObjectContext *moc = self.eventStore.managedObjectContext;
    [moc performBlockAndWait:^{
        [self addModEventForStore:@"otherstore" revision:0 timestamp:1234];
    }];
    
    NSArray *events = [revisionManager fetchUncommittedStoreModificationEvents:NULL];
    XCTAssertEqual(events.count, (NSUInteger)2, @"Wrong event count");
}

- (void)testFetchingUncommittedEventsWithOtherStoreEvents
{
    NSManagedObjectContext *moc = self.eventStore.managedObjectContext;
    [moc performBlockAndWait:^{
        [self addModEventForStore:@"otherstore" revision:0 timestamp:1234];
        [self addModEventForStore:@"otherstore" revision:1 timestamp:1234];
    }];

    NSArray *events = [revisionManager fetchUncommittedStoreModificationEvents:NULL];
    XCTAssertEqual(events.count, (NSUInteger)3, @"Wrong event count");
}

- (void)testFetchingUncommittedEventsWithPreviousMerge
{
    NSManagedObjectContext *moc = self.eventStore.managedObjectContext;
    [moc performBlockAndWait:^{
        [self addModEventForStore:@"otherstore" revision:0 timestamp:1234];
        [self addModEventForStore:@"otherstore" revision:1 timestamp:1234];
    }];
    
    self.eventStore.lastMergeRevisionSaved = 0;
    NSArray *events = [revisionManager fetchUncommittedStoreModificationEvents:NULL];
    XCTAssertEqual(events.count, (NSUInteger)2, @"Wrong event count for merge revision 0");
}

- (void)testFetchingNoUncommittedEventsWithBaseline
{
    NSManagedObjectContext *moc = self.eventStore.managedObjectContext;
    [moc performBlockAndWait:^{
        CDEStoreModificationEvent *baseline = [self addModEventForStore:@"otherstore" revision:5 timestamp:1234];
        baseline.type = CDEStoreModificationEventTypeBaseline;
        baseline.eventRevisionsOfOtherStores = [NSSet setWithObject:[self addEventRevisionForStore:@"store1" revision:4]];
    }];
    
    self.eventStore.lastMergeRevisionSaved = -1;
    NSArray *events = [revisionManager fetchUncommittedStoreModificationEvents:NULL];
    XCTAssertEqual(events.count, (NSUInteger)0, @"Should be no events since baseline");
}

- (void)testFetchingUncommittedEventsWithBaseline
{
    NSManagedObjectContext *moc = self.eventStore.managedObjectContext;
    [moc performBlockAndWait:^{
        modEvent.eventRevision.revisionNumber = 5;
        CDEStoreModificationEvent *baseline = [self addModEventForStore:@"otherstore" revision:5 timestamp:1234];
        baseline.type = CDEStoreModificationEventTypeBaseline;
        baseline.eventRevisionsOfOtherStores = [NSSet setWithObject:[self addEventRevisionForStore:@"store1" revision:4]];
    }];
    
    self.eventStore.lastMergeRevisionSaved = -1;
    NSArray *events = [revisionManager fetchUncommittedStoreModificationEvents:NULL];
    XCTAssertEqual(events.count, (NSUInteger)1, @"Should be an event");
}

- (void)testFetchingUncommittedEventsWithBaselineAndLastMerge
{
    NSManagedObjectContext *moc = self.eventStore.managedObjectContext;
    
    __block CDEStoreModificationEvent *merge;
    [moc performBlockAndWait:^{
        modEvent.eventRevision.revisionNumber = 4;
        
        merge = [self addModEventForStore:@"store1" revision:5 timestamp:1234];
        merge.type = CDEStoreModificationEventTypeMerge;
        
        CDEStoreModificationEvent *baseline = [self addModEventForStore:@"otherstore" revision:5 timestamp:1234];
        baseline.type = CDEStoreModificationEventTypeBaseline;
        baseline.eventRevisionsOfOtherStores = [NSSet setWithObject:[self addEventRevisionForStore:@"store1" revision:2]];
    }];
    
    self.eventStore.lastMergeRevisionSaved = 5;
    NSArray *events = [revisionManager fetchUncommittedStoreModificationEvents:NULL];
    XCTAssertEqual(events.count, (NSUInteger)0, @"Should be no event");
    
    [moc performBlockAndWait:^{
        merge.eventRevision.revisionNumber = 3;
    }];
    self.eventStore.lastMergeRevisionSaved = 3;
    events = [revisionManager fetchUncommittedStoreModificationEvents:NULL];
    XCTAssertEqual(events.count, (NSUInteger)1, @"Should be an event");
}


- (void)testFetchingConcurrentEventsForSingleEvent
{
    CDEStoreModificationEvent *event = [[revisionManager fetchUncommittedStoreModificationEvents:NULL] lastObject];
    NSArray *events = [revisionManager fetchStoreModificationEventsConcurrentWithEvents:@[event] error:NULL];
    XCTAssertEqual(events.count, (NSUInteger)1, @"Should only have the event itself");
}

- (void)testFetchingConcurrentEventsForMultipleEvents
{
    CDEStoreModificationEvent *event = [[revisionManager fetchUncommittedStoreModificationEvents:NULL] lastObject];

    NSManagedObjectContext *moc = self.eventStore.managedObjectContext;
    [moc performBlockAndWait:^{
        [self addModEventForStore:@"otherstore" revision:0 timestamp:1234];
        [self addModEventForStore:@"otherstore" revision:1 timestamp:1234];
    }];
    
    NSArray *events = [revisionManager fetchStoreModificationEventsConcurrentWithEvents:@[event] error:NULL];
    XCTAssertEqual(events.count, (NSUInteger)3, @"Should be concurrent with all other events");
}

- (void)testSortingOfEvents
{
    NSManagedObjectContext *moc = self.eventStore.managedObjectContext;
    [moc performBlockAndWait:^{
        [self addModEventForStore:@"otherstore" revision:1 globalCount:110 timestamp:1200.0];
        [self addModEventForStore:@"thirdstore" revision:0 globalCount:100 timestamp:1234.0];
    }];
    
    self.eventStore.lastMergeRevisionSaved = 0;
    NSArray *events = [revisionManager fetchUncommittedStoreModificationEvents:NULL];
    
    XCTAssertEqual([events[0] globalCount], (CDEGlobalCount)100, @"Global count of first wrong in uncommitted");
    XCTAssertEqual([events[1] globalCount], (CDEGlobalCount)110, @"Global count of second wrong in uncommitted");
    
    events = [CDERevisionManager sortStoreModificationEvents:events];
    
    XCTAssertEqual([events[0] globalCount], (CDEGlobalCount)100, @"Global count of first wrong");
    XCTAssertEqual([events[1] globalCount], (CDEGlobalCount)110, @"Global count of second wrong");
}

- (void)testPrerequisitesWithNoOtherEvents
{
    NSManagedObjectContext *moc = self.eventStore.managedObjectContext;
    __block NSArray *events;
    [moc performBlockAndWait:^{
        events = [revisionManager fetchUncommittedStoreModificationEvents:NULL];
        BOOL passedCheck = [revisionManager checkAllDependenciesExistForStoreModificationEvents:events];
        XCTAssertTrue(passedCheck, @"Should not be any dependencies for one event");
    }];
    
    BOOL passedCheck = [revisionManager checkIntegrationPrequisitesForEvents:events error:NULL];
    XCTAssertTrue(passedCheck, @"Integration prerequisites should pass");
}

- (void)testPrerequisitesWithDependencies
{
    NSManagedObjectContext *moc = self.eventStore.managedObjectContext;
    [moc performBlockAndWait:^{
        [self addModEventForStore:@"store1" revision:1 globalCount:110 timestamp:1200.0];
        [self addModEventForStore:@"other" revision:0 globalCount:100 timestamp:1234.0];
    }];
    
    NSArray *events = [revisionManager fetchUncommittedStoreModificationEvents:NULL];
    XCTAssertEqual(events.count, (NSUInteger)3, @"Wrong number of events uncommitted");

    BOOL passedCheck = [revisionManager checkAllDependenciesExistForStoreModificationEvents:events];
    XCTAssertTrue(passedCheck, @"Should not be any dependencies for one event");
    
    events = [revisionManager fetchStoreModificationEventsConcurrentWithEvents:events error:NULL];
    passedCheck = [revisionManager checkContinuityOfStoreModificationEvents:events];
    XCTAssertTrue(passedCheck, @"Continuity should pass");
    
    passedCheck = [revisionManager checkIntegrationPrequisitesForEvents:events error:NULL];
    XCTAssertTrue(passedCheck, @"Integration prerequisites should pass");
}

- (void)testPrerequisitesPassingDependenciesWithBaseline
{
    NSManagedObjectContext *moc = self.eventStore.managedObjectContext;
    __block NSArray *events;
    [moc performBlockAndWait:^{
        [moc deleteObject:modEvent];
        [self addModEventForStore:@"store1" revision:3 globalCount:112 timestamp:1210.0];
        CDEStoreModificationEvent *event = [self addModEventForStore:@"other" revision:4 globalCount:100 timestamp:1234.0];
        event.eventRevisionsOfOtherStores = [NSSet setWithObject:[self addEventRevisionForStore:@"store1" revision:2]];
        events = [CDEStoreModificationEvent fetchNonBaselineEventsInManagedObjectContext:moc];
    }];
    
    BOOL passedCheck = [revisionManager checkIntegrationPrequisitesForEvents:events error:NULL];
    XCTAssertFalse(passedCheck, @"Should fail check with no baseline in place, due to missing event");

    [moc performBlockAndWait:^{
        CDEStoreModificationEvent *baseline = [self addModEventForStore:@"other" revision:3 timestamp:1234];
        baseline.type = CDEStoreModificationEventTypeBaseline;
        baseline.eventRevisionsOfOtherStores = [NSSet setWithObject:[self addEventRevisionForStore:@"store1" revision:2]];
    }];
    
    events = [revisionManager fetchUncommittedStoreModificationEvents:NULL];
    XCTAssertEqual(events.count, (NSUInteger)2, @"Wrong number of events uncommitted");
    
    passedCheck = [revisionManager checkAllDependenciesExistForStoreModificationEvents:events];
    XCTAssertTrue(passedCheck, @"Should pass due to baseline");
    
    events = [revisionManager fetchStoreModificationEventsConcurrentWithEvents:events error:NULL];
    passedCheck = [revisionManager checkContinuityOfStoreModificationEvents:events];
    XCTAssertTrue(passedCheck, @"Continuity should pass");
    
    passedCheck = [revisionManager checkIntegrationPrequisitesForEvents:events error:NULL];
    XCTAssertTrue(passedCheck, @"Integration prerequisites should pass");
}

- (void)testPrerequisitesWithPreviousMerge
{
    NSManagedObjectContext *moc = self.eventStore.managedObjectContext;
    [moc performBlockAndWait:^{
        [self addModEventForStore:@"store1" revision:1 globalCount:110 timestamp:1200.0];
        [self addModEventForStore:@"other" revision:0 globalCount:100 timestamp:1234.0];
    }];
    
    self.eventStore.lastMergeRevisionSaved = 0;
    NSArray *events = [revisionManager fetchUncommittedStoreModificationEvents:NULL];
    XCTAssertEqual(events.count, (NSUInteger)2, @"Wrong number of events uncommitted");
    
    BOOL passedCheck = [revisionManager checkAllDependenciesExistForStoreModificationEvents:events];
    XCTAssertTrue(passedCheck, @"Should not be any dependencies for one event");
    
    events = [revisionManager fetchStoreModificationEventsConcurrentWithEvents:events error:NULL];
    passedCheck = [revisionManager checkContinuityOfStoreModificationEvents:events];
    XCTAssertTrue(passedCheck, @"Continuity should pass");
    
    passedCheck = [revisionManager checkIntegrationPrequisitesForEvents:events error:NULL];
    XCTAssertTrue(passedCheck, @"Integration prerequisites should pass");
}

- (void)testPrerequisitesWithDiscontinuityInRevisions
{
    NSManagedObjectContext *moc = self.eventStore.managedObjectContext;
    [moc performBlockAndWait:^{
        [self addModEventForStore:@"store1" revision:1 globalCount:110 timestamp:1200.0];
        [self addModEventForStore:@"other" revision:0 globalCount:100 timestamp:1234.0];
        [self addModEventForStore:@"other" revision:2 globalCount:100 timestamp:1234.0];
    }];
    
    NSArray *events = [revisionManager fetchUncommittedStoreModificationEvents:NULL];
    XCTAssertEqual(events.count, (NSUInteger)4, @"Wrong number of events uncommitted");
    
    BOOL passedCheck = [revisionManager checkAllDependenciesExistForStoreModificationEvents:events];
    XCTAssertTrue(passedCheck, @"Should pass dependencies");
    
    events = [revisionManager fetchStoreModificationEventsConcurrentWithEvents:events error:NULL];
    passedCheck = [revisionManager checkContinuityOfStoreModificationEvents:events];
    XCTAssertFalse(passedCheck, @"Continuity should fail");
    
    NSError *error;
    passedCheck = [revisionManager checkIntegrationPrequisitesForEvents:events error:&error];
    XCTAssertFalse(passedCheck, @"Integration prerequisites should fail");
    XCTAssertEqual(error.code, CDEErrorCodeDiscontinuousRevisions, @"Wrong error code");
}

- (void)testPrerequisitesWithMissingDependency
{
    NSManagedObjectContext *moc = self.eventStore.managedObjectContext;
    [moc performBlockAndWait:^{
        [self addModEventForStore:@"store1" revision:1 globalCount:110 timestamp:1200.0];
        
        CDEStoreModificationEvent *event = [self addModEventForStore:@"other" revision:0 globalCount:100 timestamp:1234.0];
        CDEEventRevision *rev = [self addEventRevisionForStore:@"other2" revision:0];
        event.eventRevisionsOfOtherStores = [NSSet setWithObject:rev];
    }];
    
    NSArray *events = [revisionManager fetchUncommittedStoreModificationEvents:NULL];
    BOOL passedCheck = [revisionManager checkAllDependenciesExistForStoreModificationEvents:events];
    XCTAssertFalse(passedCheck, @"Should not pass dependencies");
    
    NSError *error;
    passedCheck = [revisionManager checkIntegrationPrequisitesForEvents:events error:&error];
    XCTAssertFalse(passedCheck, @"Integration prerequisites should fail");
    XCTAssertEqual(error.code, CDEErrorCodeMissingDependencies, @"Wrong error code");
}

- (void)testPrerequisitesWithUnknownModelVersion
{
    NSManagedObjectContext *moc = self.eventStore.managedObjectContext;
    [moc performBlockAndWait:^{
        CDEStoreModificationEvent *event = [self addModEventForStore:@"other" revision:0 globalCount:0 timestamp:1234.0];
        event.modelVersion =
            @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
            @"<!DOCTYPE plist PUBLIC \"-//Apple Computer//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">"
            @"<plist version=\"1.0\">"
            @"  <dict>"
            @"      <key>Child</key>"
            @"      <string>4567</string>"
            @"  </dict>"
            @"</plist>";
    }];
    
    NSArray *events = [revisionManager fetchUncommittedStoreModificationEvents:NULL];
    BOOL passedCheck = [revisionManager checkModelVersionsOfStoreModificationEvents:events];
    XCTAssertFalse(passedCheck, @"Integration prerequisites should fail");
    
    NSError *error;
    passedCheck = [revisionManager checkIntegrationPrequisitesForEvents:events error:&error];
    XCTAssertEqual(error.code, CDEErrorCodeUnknownModelVersion, @"Wrong error code");
}

@end
