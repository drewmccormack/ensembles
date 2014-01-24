//
//  CDEIntegratorRelationshipTests.m
//  Ensembles
//
//  Created by Drew McCormack on 20/08/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "CDEIntegratorTestCase.h"

@interface CDEBasicIntegratorRelationshipTests : CDEIntegratorTestCase

@end

@implementation CDEBasicIntegratorRelationshipTests
    
    
- (void)setUp
{
    [super setUp];
    NSString *path = [[NSBundle bundleForClass:self.class] pathForResource:@"BasicIntegratorRelationshipTestsFixture" ofType:@"json"];
    [self addEventsFromJSONFile:path];
    [self mergeEvents];
}

- (void)testParentInserted
{
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Parent"];
    NSArray *parents = [self.testManagedObjectContext executeFetchRequest:fetch error:NULL];
    XCTAssertEqual(parents.count, (NSUInteger)1, @"Wrong number of parents");
}

- (void)testChildInserted
{
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Child"];
    NSArray *children = [self.testManagedObjectContext executeFetchRequest:fetch error:NULL];
    XCTAssertEqual(children.count, (NSUInteger)1, @"Wrong number of parents");
}

- (void)testParentDateAttributeIsSet
{
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Parent"];
    NSArray *parents = [self.testManagedObjectContext executeFetchRequest:fetch error:NULL];
    id parent = parents.lastObject;
    XCTAssertEqualWithAccuracy(58472395723.0, [[parent valueForKey:@"date"] timeIntervalSinceReferenceDate], 1.e-3, @"Wrong date");
}

- (void)testOneToOneRelationshipIsSetOnParent
{
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Parent"];
    NSArray *parents = [self.testManagedObjectContext executeFetchRequest:fetch error:NULL];
    id parent = parents.lastObject;
    XCTAssertNotNil([parent valueForKey:@"child"], @"Should have a child object");
}

- (void)testManyToOneRelationshipIsSet
{
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Parent"];
    NSArray *parents = [self.testManagedObjectContext executeFetchRequest:fetch error:NULL];
    id parent = parents.lastObject;
    XCTAssertEqual([[parent valueForKey:@"children"] count], (NSUInteger)1, @"Should have a child object");
}

- (void)testOneToManyRelationshipIsSetOnChild
{
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Child"];
    NSArray *children = [self.testManagedObjectContext executeFetchRequest:fetch error:NULL];
    id child = children.lastObject;
    XCTAssertNotNil([child valueForKey:@"parentWithSiblings"], @"No parent with siblings");
}

- (void)testChildrenRelationshipIsSetOnParent
{
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Parent"];
    NSArray *parents = [self.testManagedObjectContext executeFetchRequest:fetch error:NULL];
    id parent = parents.lastObject;
    XCTAssertEqual([[parent valueForKey:@"children"] count], (NSUInteger)1, @"Should have a child object");
}

- (void)testManyToManyRelationshipIsSetOnParent
{
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Parent"];
    NSArray *parents = [self.testManagedObjectContext executeFetchRequest:fetch error:NULL];
    id parent = parents.lastObject;
    XCTAssertEqual([[parent valueForKey:@"friends"] count], (NSUInteger)1, @"Should have a friend object");
}

- (void)testManyToManyRelationshipIsSetOnChild
{
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Child"];
    NSArray *children = [self.testManagedObjectContext executeFetchRequest:fetch error:NULL];
    id child = children.lastObject;
    XCTAssertEqual([[child valueForKey:@"testFriends"] count], (NSUInteger)1, @"Should have testFriends");
}

@end
