//
//  CDERevisionTests.m
//  Ensembles
//
//  Created by Drew McCormack on 14/07/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "CDEEventStoreTestCase.h"
#import "CDEEventRevision.h"
#import "CDERevisionSet.h"
#import "CDERevision.h"

@interface CDEEventRevisionTests : CDEEventStoreTestCase

@end

@implementation CDEEventRevisionTests {
    CDEEventRevision *eventRevision;
    CDEEventRevision *eventRevision1;
    NSManagedObjectContext *moc;
}

- (void)setUp
{
    [super setUp];
    moc = self.eventStore.managedObjectContext;
    [moc performBlockAndWait:^{
        eventRevision = [CDEEventRevision makeEventRevisionForPersistentStoreIdentifier:@"1234" revisionNumber:3 inManagedObjectContext:moc];
        eventRevision1 = [CDEEventRevision makeEventRevisionForPersistentStoreIdentifier:@"1234" revisionNumber:1 inManagedObjectContext:moc];
    }];
}

- (void)tearDown
{
    [super tearDown];
}

- (void)testCreateValidObject
{
    [moc performBlockAndWait:^{
        XCTAssertEqual(eventRevision.revisionNumber, (CDERevisionNumber)3, @"Wrong revision number");
        XCTAssertEqualObjects(eventRevision.persistentStoreIdentifier, @"1234", @"Wrong store id");
    }];
}

- (void)testSavingValidObject
{
    [moc performBlockAndWait:^{
        XCTAssertTrue([moc save:NULL], @"Could not save valid object");
    }];
}

- (void)testNilPersistentStoreIdentifier
{
    [moc performBlockAndWait:^{
        XCTAssertThrows([CDEEventRevision makeEventRevisionForPersistentStoreIdentifier:nil revisionNumber:0 inManagedObjectContext:moc], @"Should throw for nil store id");
    }];
}

- (void)testNilContext
{
    [moc performBlockAndWait:^{
        XCTAssertThrows([CDEEventRevision makeEventRevisionForPersistentStoreIdentifier:@"124" revisionNumber:0 inManagedObjectContext:nil], @"Should throw for nil context");
    }];
}

@end
