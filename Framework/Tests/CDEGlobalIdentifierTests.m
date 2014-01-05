//
//  CDEGlobalIdentifierTests.m
//  Ensembles
//
//  Created by Drew McCormack on 06/10/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "CDEEventStoreTestCase.h"
#import "CDEGlobalIdentifier.h"

@interface CDEGlobalIdentifierTests : CDEEventStoreTestCase

@end

@implementation CDEGlobalIdentifierTests {
    CDEGlobalIdentifier *globalId1, *globalId2, *globalId3;
}

- (void)setUp
{
    [super setUp];
    
    globalId1 = [NSEntityDescription insertNewObjectForEntityForName:@"CDEGlobalIdentifier" inManagedObjectContext:self.eventStore.managedObjectContext];
    globalId1.globalIdentifier = @"aaa";
    globalId1.nameOfEntity = @"EntityA";
    
    globalId2 = [NSEntityDescription insertNewObjectForEntityForName:@"CDEGlobalIdentifier" inManagedObjectContext:self.eventStore.managedObjectContext];
    globalId2.globalIdentifier = @"bbb";
    globalId2.nameOfEntity = @"EntityB";
    
    globalId3 = [NSEntityDescription insertNewObjectForEntityForName:@"CDEGlobalIdentifier" inManagedObjectContext:self.eventStore.managedObjectContext];
    globalId3.globalIdentifier = @"bbb";
    globalId3.nameOfEntity = @"EntityC";
}

- (void)testFetchForNonExistentIdentifierGivesNSNull
{
    NSArray *ids = [CDEGlobalIdentifier fetchGlobalIdentifiersForIdentifierStrings:@[@"ccc"] withEntityNames:@[@"EntityA"] inManagedObjectContext:self.eventStore.managedObjectContext];
    XCTAssertEqual(ids.count, (NSUInteger)1, @"Should be one result for each object");
    XCTAssertEqualObjects(ids.lastObject, [NSNull null], @"Should not find a object");
}

- (void)testFetchWithUnequalArrayLengthsFails
{
    XCTAssertThrows([CDEGlobalIdentifier fetchGlobalIdentifiersForIdentifierStrings:@[@"aaa"] withEntityNames:@[] inManagedObjectContext:self.eventStore.managedObjectContext], @"Should throw if wrong number of entities");
}

- (void)testFetchOfMatchingGlobalIdButNotMatchingEntityReturnsNull
{
    NSArray *ids = [CDEGlobalIdentifier fetchGlobalIdentifiersForIdentifierStrings:@[@"aaa"] withEntityNames:@[@"EntityB"] inManagedObjectContext:self.eventStore.managedObjectContext];
    XCTAssertEqual(ids.count, (NSUInteger)1, @"Should be one result for each object");
    XCTAssertEqualObjects(ids.lastObject, [NSNull null], @"Should not find a object");
}

- (void)testFetchWithMatchingGlobalIdAndEntityReturnsObject
{
    NSArray *ids = [CDEGlobalIdentifier fetchGlobalIdentifiersForIdentifierStrings:@[@"aaa"] withEntityNames:@[@"EntityA"] inManagedObjectContext:self.eventStore.managedObjectContext];
    XCTAssertEqual(ids.count, (NSUInteger)1, @"Should be one result for each object");
    XCTAssertEqualObjects(ids.lastObject, globalId1, @"Should find the object");
}

- (void)testFetchingMultipleGlobalIds
{
    NSArray *ids = [CDEGlobalIdentifier fetchGlobalIdentifiersForIdentifierStrings:@[@"bbb", @"aaa", @"aaa"] withEntityNames:@[@"EntityB", @"EntityA", @"EntityC"] inManagedObjectContext:self.eventStore.managedObjectContext];
    XCTAssertEqual(ids.count, (NSUInteger)3, @"Should be one result for each object");
    XCTAssertEqualObjects(ids[0], globalId2, @"Wrong first object");
    XCTAssertEqualObjects(ids[1], globalId1, @"Wrong second object");
    XCTAssertEqualObjects(ids[2], [NSNull null], @"Last should be null. Wrong entity.");
}

- (void)testFetchingMultipleObjectsWithSameIdDifferentEntity
{
    NSArray *ids = [CDEGlobalIdentifier fetchGlobalIdentifiersForIdentifierStrings:@[@"bbb", @"bbb"] withEntityNames:@[@"EntityB", @"EntityC"] inManagedObjectContext:self.eventStore.managedObjectContext];
    XCTAssertEqualObjects(ids[0], globalId2, @"Wrong first object");
    XCTAssertEqualObjects(ids[1], globalId3, @"Wrong second object");
}

@end
