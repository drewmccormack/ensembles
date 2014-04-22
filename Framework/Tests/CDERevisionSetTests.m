//
//  CDERevisionSetTests.m
//  Ensembles
//
//  Created by Drew McCormack on 24/07/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "CDEDefines.h"
#import "CDERevisionSet.h"
#import "CDERevision.h"

@interface CDERevisionMock : NSObject

@property NSString *persistentStoreIdentifier;
@property CDERevisionNumber revisionNumber;
@property CDEGlobalCount globalCount;

@end

@implementation CDERevisionMock

@end


@interface CDERevisionSetTests : XCTestCase {
    id revision1, revision2;
    CDERevisionSet *set;
}

@end

@implementation CDERevisionSetTests

- (void)setUp
{
    [super setUp];
    
    CDERevisionMock *newRevision = [[CDERevisionMock alloc] init];
    newRevision.persistentStoreIdentifier = @"1234";
    newRevision.revisionNumber = 0;
    revision1 = newRevision;
    
    newRevision = [[CDERevisionMock alloc] init];
    newRevision.persistentStoreIdentifier = @"1";
    newRevision.revisionNumber = 2;
    revision2 = newRevision;
    
    set = [[CDERevisionSet alloc] init];
}

- (void)tearDown
{
    [super tearDown];
    revision1 = nil;
    revision2 = nil;
    set = nil;
}

- (void)testCreatingEmptySet
{
    XCTAssertNotNil(set, @"Creation failed");
}

- (void)testAddingStore
{
    XCTAssertNoThrow([set addRevision:revision1], @"Threw when adding revision");
}

- (void)testAddingStoreTwice
{
    XCTAssertNoThrow([set addRevision:revision1], @"Threw when adding revision");
    XCTAssertNoThrow([set addRevision:revision1], @"Should not throw when adding revision for same store");
}

- (void)testRemovingNonExistentStore
{
    XCTAssertThrows([set removeRevision:revision1], @"Should throw when removing revision not in set");
}

- (void)testRemovingExistingStore
{
    [set addRevision:revision1];
    XCTAssertEqual(set.numberOfRevisions, (NSUInteger)1, "Count after adding revision was wrong");
    XCTAssertNoThrow([set removeRevision:revision1], @"Should not throw when removing revision in set");
    XCTAssertEqual(set.numberOfRevisions, (NSUInteger)0, "Count after adding revision was wrong");
}

- (void)testMembershipForNonExistentStore
{
    XCTAssertFalse([set hasRevisionForPersistentStoreIdentifier:@"12"], @"Found revision that should not exist");
}

- (void)testMembershipForExistingStore
{
    [set addRevision:revision1];
    XCTAssertTrue([set hasRevisionForPersistentStoreIdentifier:@"1234"], @"Did not find revision that should exist");
}

- (void)testIncrementingNonExistentStore
{
    [set addRevision:revision1];
    XCTAssertThrows([set incrementRevisionForStoreWithIdentifier:@"12345"], @"Did no throw for non-existent store");
}

- (void)testIncrementingExistingStore
{
    [set addRevision:revision1];
    [set addRevision:revision2];
    XCTAssertNoThrow([set incrementRevisionForStoreWithIdentifier:@"1234"], @"Threw on incrementing");
    
    CDERevisionMock *rev = (id)[set revisionForPersistentStoreIdentifier:@"1234"];
    XCTAssertEqual(rev.revisionNumber, (CDERevisionNumber)1, @"Wrong revision number after increment");
}

- (void)testAccessingRevisions
{
    [set addRevision:revision1];
    [set addRevision:revision2];
    XCTAssertEqual(set.revisions.count, (NSUInteger)2, @"Wrong count");
}

- (void)testStoreWiseMinimumReductionWithEmptySet
{
    CDERevisionSet *other = [[CDERevisionSet alloc] init];
    [set addRevision:revision2];
    CDERevisionSet *result = [set revisionSetByTakingStoreWiseMinimumWithRevisionSet:other];
    XCTAssertEqual(result.numberOfRevisions, (NSUInteger)1, @"Wrong number of store revs");
    
    CDERevision *rev = result.revisions.anyObject;
    XCTAssertEqual(rev.revisionNumber, (CDERevisionNumber)2, @"Wrong rev number");
}

- (void)testStoreWiseMinimumReductionWithDifferentStores
{
    [set addRevision:revision2];

    CDERevisionSet *other = [[CDERevisionSet alloc] init];
    [other addRevision:revision1];
    
    CDERevisionSet *result = [other revisionSetByTakingStoreWiseMinimumWithRevisionSet:set];
    XCTAssertEqual(result.numberOfRevisions, (NSUInteger)2, @"Wrong number of store revs");
    
    CDERevision *rev = [result revisionForPersistentStoreIdentifier:@"1"];
    XCTAssertEqual(rev.revisionNumber, (CDERevisionNumber)2, @"Wrong rev number");
}

- (void)testStoreWiseMinimumReductionWithSameStore
{
    [set addRevision:revision2];
    
    CDERevisionSet *other = [[CDERevisionSet alloc] init];
    CDERevision *newRevision = (id)[[CDERevisionMock alloc] init];
    newRevision.persistentStoreIdentifier = [revision2 persistentStoreIdentifier];
    newRevision.revisionNumber = [revision2 revisionNumber]-1;
    [other addRevision:newRevision];
    
    CDERevisionSet *result = [other revisionSetByTakingStoreWiseMinimumWithRevisionSet:set];
    XCTAssertEqual(result.numberOfRevisions, (NSUInteger)1, @"Wrong number of store revs");
    
    CDERevision *rev = [result revisionForPersistentStoreIdentifier:newRevision.persistentStoreIdentifier];
    XCTAssertEqual(rev.revisionNumber, newRevision.revisionNumber, @"Wrong rev number");
}

- (void)testStoreWiseMaximumReductionWithEmptySet
{
    CDERevisionSet *other = [[CDERevisionSet alloc] init];
    [set addRevision:revision2];
    CDERevisionSet *result = [other revisionSetByTakingStoreWiseMaximumWithRevisionSet:set];
    XCTAssertEqual(result.numberOfRevisions, (NSUInteger)1, @"Wrong number of store revs");
    
    CDERevision *rev = result.revisions.anyObject;
    XCTAssertEqual(rev.revisionNumber, (CDERevisionNumber)2, @"Wrong rev number");
}

- (void)testStoreWiseMaximumReductionWithSameStore
{
    [set addRevision:revision2];
    
    CDERevisionSet *other = [[CDERevisionSet alloc] init];
    CDERevision *newRevision = (id)[[CDERevisionMock alloc] init];
    newRevision.persistentStoreIdentifier = [revision2 persistentStoreIdentifier];
    newRevision.revisionNumber = [revision2 revisionNumber]-1;
    [other addRevision:newRevision];
    
    CDERevisionSet *result = [other revisionSetByTakingStoreWiseMaximumWithRevisionSet:set];
    XCTAssertEqual(result.numberOfRevisions, (NSUInteger)1, @"Wrong number of store revs");
    
    CDERevision *rev = [result revisionForPersistentStoreIdentifier:newRevision.persistentStoreIdentifier];
    XCTAssertEqual(rev.revisionNumber, [revision2 revisionNumber], @"Wrong rev number");
}

- (void)testComparisonOfEqualRevisionSets
{
    [set addRevision:revision2];
    [set addRevision:revision1];
    
    CDERevisionSet *other = [[CDERevisionSet alloc] init];
    [other addRevision:revision2];
    [other addRevision:revision1];
    
    XCTAssertEqual([set compare:other], NSOrderedSame, @"Should be the same");
}

- (void)testComparisonWithSubsetRevisionSet
{
    [set addRevision:revision2];
    [set addRevision:revision1];
    
    CDERevisionSet *other = [[CDERevisionSet alloc] init];
    [other addRevision:revision2];
    
    XCTAssertEqual([set compare:other], NSOrderedDescending, @"Should be descending. Other should be a subset");
    XCTAssertEqual([other compare:set], NSOrderedAscending, @"Should be ascending. Other should be a superset");
}

- (void)testComparisonWithConcurrentRevisionSets
{
    [set addRevision:revision2];
    [set addRevision:revision1];
    
    CDERevisionSet *other = [[CDERevisionSet alloc] init];
    CDERevisionMock *newRevision = [[CDERevisionMock alloc] init];
    newRevision.persistentStoreIdentifier = @"1234";
    newRevision.revisionNumber = 1;
    [other addRevision:(id)newRevision];
    
    newRevision = [[CDERevisionMock alloc] init];
    newRevision.persistentStoreIdentifier = @"1";
    newRevision.revisionNumber = 1;
    [other addRevision:(id)newRevision];
    
    XCTAssertEqual([set compare:other], NSOrderedSame, @"Concurrent revision sets should be ordered the same");
}

- (void)testComparisonWithOneSuperset
{
    [set addRevision:revision2];
    [set addRevision:revision1];
    
    CDERevisionSet *other = [[CDERevisionSet alloc] init];
    CDERevisionMock *newRevision = [[CDERevisionMock alloc] init];
    newRevision.persistentStoreIdentifier = @"1234";
    newRevision.revisionNumber = 0;
    [other addRevision:(id)newRevision];
    
    newRevision = [[CDERevisionMock alloc] init];
    newRevision.persistentStoreIdentifier = @"1";
    newRevision.revisionNumber = 3;
    [other addRevision:(id)newRevision];
    
    XCTAssertEqual([set compare:other], NSOrderedAscending, @"Second is superset, so ascends first");
    XCTAssertEqual([other compare:set], NSOrderedDescending, @"Second is subset, so descends first");
}

@end
