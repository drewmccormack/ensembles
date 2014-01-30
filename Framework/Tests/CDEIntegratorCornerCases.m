//
//  CDEIntegratorCornerCases.m
//  Ensembles
//
//  Created by Drew McCormack on 31/08/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "CDEIntegratorTestCase.h"

@interface CDEIntegratorCornerCases : CDEIntegratorTestCase

@end

@implementation CDEIntegratorCornerCases

- (void)addEventsForFile:(NSString *)filename
{
    NSString *path = [[NSBundle bundleForClass:self.class] pathForResource:filename ofType:@"json"];
    [self addEventsFromJSONFile:path];
}

- (NSArray *)fetchParents
{
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Parent"];
    NSArray *parents = [self.testManagedObjectContext executeFetchRequest:fetch error:NULL];
    return parents;
}

- (NSArray *)fetchChildren
{
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Child"];
    NSArray *children = [self.testManagedObjectContext executeFetchRequest:fetch error:NULL];
    return children;
}

- (void)testDoubleInsert
{
    [self addEventsForFile:@"DoubleInsertFixture"];
    [self mergeEvents];
    
    NSArray *parents = [self fetchParents];
    XCTAssertEqual(parents.count, (NSUInteger)1, @"Wrong number of parents");
    
    id parent = parents.lastObject;
    XCTAssertEqual([[parent valueForKey:@"date"] timeIntervalSinceReferenceDate], (NSTimeInterval)20.0f, @"Wrong date. Later timestamp value should apply.");
}

- (void)testUpdateFollowingDeletion
{
    [self addEventsForFile:@"UpdateFollowingDeletion"];
    [self mergeEvents];
    
    NSArray *parents = [self fetchParents];
    XCTAssertEqual(parents.count, (NSUInteger)0, @"Deletion should trump update and there should be no parents left");
}

- (void)testInsertFollowingDeletion
{
    [self addEventsForFile:@"InsertFollowingDeletion"];
    [self mergeEvents];
    
    NSArray *parents = [self fetchParents];
    XCTAssertEqual(parents.count, (NSUInteger)1, @"New insert should trump deletion");
}

- (void)testUpdateConcurrentWithInsert
{
    [self addEventsForFile:@"UpdateConcurrentWithInsert"];
    [self mergeEvents];
    
    NSArray *parents = [self fetchParents];
    XCTAssertEqual(parents.count, (NSUInteger)1, @"Should be a parent");
    
    id parent = parents.lastObject;
    XCTAssertEqual([[parent valueForKey:@"date"] timeIntervalSinceReferenceDate], (NSTimeInterval)10.0f, @"Wrong date. Insert is ordered earlier, so its value should trump update.");
}

- (void)testUpdateToUninserted
{
    [self addEventsForFile:@"UpdateToUninserted"];
    [self mergeEvents];
    
    NSArray *parents = [self fetchParents];
    XCTAssertEqual(parents.count, (NSUInteger)0, @"No insertion, so should be no object");
}

- (void)testDeleteUninserted
{
    [self addEventsForFile:@"DeleteUninserted"];
    [self mergeEvents];
    
    NSArray *parents = [self fetchParents];
    XCTAssertEqual(parents.count, (NSUInteger)0, @"No insertion, so should be no object");
}

- (void)testUpdateRelationshipConcurrently
{
    [self addEventsForFile:@"UpdateRelationshipConcurrently"];
    [self mergeEvents];
    
    NSArray *parents = [self fetchParents];
    XCTAssertEqual(parents.count, (NSUInteger)1, @"Should be a parent");
    
    id parent = parents.lastObject;
    XCTAssertEqual([[parent valueForKey:@"friends"] count], (NSUInteger)1, @"Should be a friend, because add is ordered after remove");
}

- (void)testUpdateRelationshipConcurrentlyWithDeletion
{
    [self addEventsForFile:@"UpdateRelationshipConcurrentWithDeletion"];
    [self mergeEvents];
    
    NSArray *parents = [self fetchParents];
    XCTAssertEqual(parents.count, (NSUInteger)0, @"Should be no parent");
    
    NSArray *children = [self fetchChildren];
    XCTAssertEqual(children.count, (NSUInteger)1, @"Should be a child");
    
    id child = children.lastObject;
    XCTAssertEqual([[child valueForKey:@"testFriends"] count], (NSUInteger)0, @"Should be no friends");
}

@end
