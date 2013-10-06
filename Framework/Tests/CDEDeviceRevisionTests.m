//
//  CDERevisionTests.m
//  Ensembles
//
//  Created by Drew McCormack on 11/08/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "CDERevision.h"

@interface CDERevisionTests : XCTestCase

@end

@implementation CDERevisionTests {
    CDERevision *revision;
    CDERevision *revision1;
    NSManagedObjectContext *moc;
}

- (void)setUp
{
    [super setUp];
    revision = [[CDERevision alloc] initWithPersistentStoreIdentifier:@"1234" revisionNumber:3];
    revision1 = [[CDERevision alloc] initWithPersistentStoreIdentifier:@"1234" revisionNumber:1];
}

- (void)testCompareOfEqualRevisions
{
    CDERevision *revision2 = [[CDERevision alloc] initWithPersistentStoreIdentifier:@"1234" revisionNumber:1];
    XCTAssertTrue([revision1 compare:revision2] == NSOrderedSame, @"Should be equal");
}

- (void)testCompareOfUnequalRevisions
{
    CDERevision *revision2 = [[CDERevision alloc] initWithPersistentStoreIdentifier:@"1234" revisionNumber:2];
    XCTAssertTrue([revision1 compare:revision2] == NSOrderedAscending, @"Should be ascending");
    XCTAssertTrue([revision2 compare:revision1] == NSOrderedDescending, @"Should be descending");
}

- (void)testIsEqualForEqualRevisions
{
    CDERevision *revision2 = [[CDERevision alloc] initWithPersistentStoreIdentifier:@"1234" revisionNumber:1];
    XCTAssertTrue([revision1 isEqual:revision2], @"Should be equal");
}

- (void)testIsEqualForUnequalRevisions
{
    CDERevision *revision2 = [[CDERevision alloc] initWithPersistentStoreIdentifier:@"1234" revisionNumber:2];
    XCTAssertFalse([revision isEqual:revision2], @"Should not be equal");
    XCTAssertFalse([revision isEqual:nil], @"Should not equal nil");
}

@end
