//
//  CDEIntegratorUpdateTests.m
//  Ensembles
//
//  Created by Drew McCormack on 24/08/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "CDEIntegratorTestCase.h"

@interface CDEIntegratorUpdateTests : CDEIntegratorTestCase

@end

@implementation CDEIntegratorUpdateTests {
    id parent1, parent2, child1, child2, child3;
}

- (void)setUp
{
    [super setUp];
    
    // Add first event
    NSString *path = [[NSBundle bundleForClass:self.class] pathForResource:@"IntegratorUpdateTestsFixture1" ofType:@"json"];
    [self addEventsFromJSONFile:path];
    [self mergeEvents];
    [self.testManagedObjectContext save:NULL];
    [self.testManagedObjectContext reset];

    // Add other events
    path = [[NSBundle bundleForClass:self.class] pathForResource:@"IntegratorUpdateTestsFixture2" ofType:@"json"];
    [self addEventsFromJSONFile:path];
    [self mergeEvents];
    [self.testManagedObjectContext save:NULL];
    [self.testManagedObjectContext reset];
    
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Parent"];
    NSArray *parents = [self.testManagedObjectContext executeFetchRequest:fetch error:NULL];
    parent1 = parents.lastObject;
    
    NSFetchRequest *childFetch = [NSFetchRequest fetchRequestWithEntityName:@"Child"];
    NSArray *children = [self.testManagedObjectContext executeFetchRequest:childFetch error:NULL];
    child1 = [[children filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"name = \"child1\""]] lastObject];
    child2 = [[children filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"name = \"child2\""]] lastObject];
    child3 = [[children filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"name = \"child3\""]] lastObject];
}

- (void)testOneToOneRelationshipUpdatedToNil
{
    XCTAssertNil([parent1 valueForKey:@"child"], @"Parent should end with no child");
    XCTAssertNil([child1 valueForKey:@"parent"], @"Child1 should have no parent");
}

- (void)testOneToManyRelationshipUpdated
{
    XCTAssertEqual([[parent1 valueForKey:@"children"] count], (NSUInteger)1, @"Parent should end with children count 1");
    
    id newChild = [[parent1 valueForKey:@"children"] anyObject];
    XCTAssertEqualObjects(newChild, child2, @"Wrong child in children");
    XCTAssertNotNil([child2 valueForKey:@"parentWithSiblings"], @"child2 should have a parentWithSiblings");
    XCTAssertNil([child1 valueForKey:@"parentWithSiblings"], @"child1 should not have a parentWithSiblings");
}

- (void)testManyToManyRelationshipsUpdated
{
    XCTAssertEqual([[parent1 valueForKey:@"friends"] count], (NSUInteger)2, @"Parent has wrong number of friends");
    XCTAssertEqual([[child2 valueForKey:@"testFriends"] count], (NSUInteger)1, @"child2 has wrong number of testFriends");
    XCTAssertEqual([[child1 valueForKey:@"testFriends"] count], (NSUInteger)1, @"child1 has wrong number of testFriends");
}

- (void)testDeletions
{
    XCTAssertNil(child3, @"Child3 should be deleted");
    XCTAssertNil(parent2, @"Parent2 should be deleted");
}

@end
