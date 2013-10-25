//
//  CDETwoWaySyncTests.m
//  Ensembles
//
//  Created by Drew McCormack on 19/09/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import "CDESyncTest.h"

@interface CDETwoWaySyncTests : CDESyncTest

@end

@implementation CDETwoWaySyncTests

- (void)testUpdateAttributeOnSecondDevice
{
    [self leechStores];
    
    NSManagedObject *parentOnDevice1 = [NSEntityDescription insertNewObjectForEntityForName:@"Parent" inManagedObjectContext:context1];
    [parentOnDevice1 setValue:@"bob" forKey:@"name"];
    XCTAssertTrue([context1 save:NULL], @"Could not save");
    
    XCTAssertNil([self syncChanges], @"First sync failed");
    
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Parent"];
    NSArray *parents = [context2 executeFetchRequest:fetch error:NULL];
    XCTAssertEqual(parents.count, (NSUInteger)1, @"Wrong number of parents on device 2");
    
    NSManagedObject *parentOnDevice2 = parents.lastObject;
    [parentOnDevice2 setValue:@"dave" forKey:@"name"];
    XCTAssertTrue([context2 save:NULL], @"Could not save");
    
    XCTAssertNil([self syncChanges], @"Second sync failed");
    
    // Note stalenessInterval setting is 0.0. Otherwise these will use cached values, which are no good.
    [context1 refreshObject:parentOnDevice1 mergeChanges:NO];
    [context2 refreshObject:parentOnDevice2 mergeChanges:NO];
    
    XCTAssertEqualObjects([parentOnDevice1 valueForKey:@"name"], @"dave", @"Wrong name on device 1");
    XCTAssertEqualObjects([parentOnDevice2 valueForKey:@"name"], @"dave", @"Wrong name on device 2");
}

- (void)testConflictingAttributeUpdates
{
    [self leechStores];
    
    NSManagedObject *parentOnDevice1 = [NSEntityDescription insertNewObjectForEntityForName:@"Parent" inManagedObjectContext:context1];
    [parentOnDevice1 setValue:@"bob" forKey:@"name"];
    XCTAssertTrue([context1 save:NULL], @"Could not save");
    
    XCTAssertNil([self syncChanges], @"First sync failed");
    
    // Update on device 1
    [parentOnDevice1 setValue:@"john" forKey:@"name"];
    XCTAssertTrue([context1 save:NULL], @"Could not save");
    
    // Concurrent update on device 2. This one should win due to timestamp.
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Parent"];
    NSManagedObject *parentOnDevice2 = [[context2 executeFetchRequest:fetch error:NULL] lastObject];
    XCTAssertEqualObjects([parentOnDevice2 valueForKey:@"name"], @"bob", @"Wrong name on device 2 after first sync");
    
    [parentOnDevice2 setValue:@"dave" forKey:@"name"];
    XCTAssertTrue([context2 save:NULL], @"Could not save");
    
    XCTAssertNil([self syncChanges], @"Second sync failed");
    
    // Note stalenessInterval setting is 0.0. Otherwise these will use cached values, which are no good.
    [context1 refreshObject:parentOnDevice1 mergeChanges:NO];
    [context2 refreshObject:parentOnDevice2 mergeChanges:NO];
    
    XCTAssertEqualObjects([parentOnDevice1 valueForKey:@"name"], @"dave", @"Wrong name on device 1");
    XCTAssertEqualObjects([parentOnDevice2 valueForKey:@"name"], @"dave", @"Wrong name on device 2");
}

- (void)testUpdateToOneRelationship
{
    [self leechStores];
    
    id parent = [NSEntityDescription insertNewObjectForEntityForName:@"Parent" inManagedObjectContext:context1];
    id childOnDevice1 = [NSEntityDescription insertNewObjectForEntityForName:@"Child" inManagedObjectContext:context1];
    [childOnDevice1 setValue:parent forKey:@"parent"];
    XCTAssertTrue([context1 save:NULL], @"Could not save");
    
    XCTAssertNil([self syncChanges], @"Sync failed");
    
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Child"];
    NSArray *children = [context2 executeFetchRequest:fetch error:NULL];
    id childOnDevice2 = children.lastObject;
    
    id newParent = [NSEntityDescription insertNewObjectForEntityForName:@"Parent" inManagedObjectContext:context2];
    [newParent setValue:@"newdad" forKey:@"name"];
    [childOnDevice2 setValue:newParent forKey:@"parent"];
    XCTAssertTrue([context2 save:NULL], @"Could not save");
    
    XCTAssertNil([self syncChanges], @"Sync failed");
    
    [context1 refreshObject:childOnDevice1 mergeChanges:NO];
    [context1 refreshObject:parent mergeChanges:NO];
    
    id newParentOnDevice1 = [childOnDevice1 valueForKey:@"parent"];
    XCTAssertNotNil(newParentOnDevice1, @"No parent");
    XCTAssertNotEqualObjects(parent, newParentOnDevice1, @"Wrong parent");
    XCTAssertEqualObjects([newParentOnDevice1 valueForKey:@"name"], @"newdad", @"Wrong name for new parent");
}

- (void)testUpdateOrderedRelationship
{
    [self leechStores];
    
    // Create parent with ordered children on device 1
    id parent = [NSEntityDescription insertNewObjectForEntityForName:@"Parent" inManagedObjectContext:context1];

    id child1OnDevice1 = [NSEntityDescription insertNewObjectForEntityForName:@"Child" inManagedObjectContext:context1];
    id child2OnDevice1 = [NSEntityDescription insertNewObjectForEntityForName:@"Child" inManagedObjectContext:context1];
    id child3OnDevice1 = [NSEntityDescription insertNewObjectForEntityForName:@"Child" inManagedObjectContext:context1];
    
    [child1OnDevice1 setName:@"child1"];
    [child2OnDevice1 setName:@"child2"];
    [child3OnDevice1 setName:@"child3"];
    
    NSOrderedSet *set = [NSOrderedSet orderedSetWithArray:@[child1OnDevice1, child2OnDevice1, child3OnDevice1]];
    [parent setValue:set forKey:@"orderedChildren"];

    XCTAssertTrue([context1 save:NULL], @"Could not save");
    
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Parent"];
    NSArray *parents = [context2 executeFetchRequest:fetch error:NULL];
    XCTAssertEqual(parents.count, (NSUInteger)0, @"Should be no parents on device 2 before sync");

    XCTAssertNil([self syncChanges], @"Sync failed");

    // Check that sync objects came over
    fetch = [NSFetchRequest fetchRequestWithEntityName:@"Parent"];
    parents = [context2 executeFetchRequest:fetch error:NULL];
    id parentOnDevice2 = parents.lastObject;
    XCTAssertNotNil(parentOnDevice2, @"Parent should not be nil after sync");

    NSMutableOrderedSet *childrenOnDevice2 = [[parentOnDevice2 valueForKey:@"orderedChildren"] mutableCopy];
    XCTAssertEqual(childrenOnDevice2.count, (NSUInteger)3, @"Expected 3 children");
    XCTAssertEqualObjects([childrenOnDevice2[0] name], @"child1", @"Wrong child at index 0");
    XCTAssertEqualObjects([childrenOnDevice2[1] name], @"child2", @"Wrong child at index 1");
    XCTAssertEqualObjects([childrenOnDevice2[2] name], @"child3", @"Wrong child at index 2");

    // Reorder the children on device 2 and sync changes back to device 1
    [childrenOnDevice2 moveObjectsAtIndexes:[NSIndexSet indexSetWithIndex:2] toIndex:1];
    [parentOnDevice2 setValue:childrenOnDevice2 forKey:@"orderedChildren"];
    XCTAssertTrue([context2 save:NULL], @"Could not save");
    
    XCTAssertNil([self syncChanges], @"Sync failed");

    [context1 refreshObject:child1OnDevice1 mergeChanges:NO];
    id parentOnDevice1 = [child1OnDevice1 valueForKey:@"orderedParent"];
    [context1 refreshObject:parentOnDevice1 mergeChanges:NO];

    NSOrderedSet *orderedChildrenOnDevice1 = [parentOnDevice1 valueForKey:@"orderedChildren"];
    XCTAssertEqual(orderedChildrenOnDevice1.count, (NSUInteger)3, @"Expected 3 children");
    XCTAssertNotNil(parentOnDevice1, @"No parent");

    XCTAssertEqualObjects(orderedChildrenOnDevice1[0], child1OnDevice1, @"Incorrect order");
    XCTAssertEqualObjects(orderedChildrenOnDevice1[1], child3OnDevice1, @"Incorrect order");
    XCTAssertEqualObjects(orderedChildrenOnDevice1[2], child2OnDevice1, @"Incorrect order");
}

- (void)testUpdateConflictingOrderedRelationship
{
    [self leechStores];
    
    // Create objects on device 1
    id parent = [NSEntityDescription insertNewObjectForEntityForName:@"Parent" inManagedObjectContext:context1];
    
    id child1OnDevice1 = [NSEntityDescription insertNewObjectForEntityForName:@"Child" inManagedObjectContext:context1];
    id child2OnDevice1 = [NSEntityDescription insertNewObjectForEntityForName:@"Child" inManagedObjectContext:context1];
    id child3OnDevice1 = [NSEntityDescription insertNewObjectForEntityForName:@"Child" inManagedObjectContext:context1];
    
    [child1OnDevice1 setName:@"child1"];
    [child2OnDevice1 setName:@"child2"];
    [child3OnDevice1 setName:@"child3"];
    
    NSOrderedSet *set = [NSOrderedSet orderedSetWithArray:@[ child1OnDevice1, child2OnDevice1, child3OnDevice1]];
    [parent setValue:set forKey:@"orderedChildren"];
    
    XCTAssertTrue([context1 save:NULL], @"Could not save");
    XCTAssertNil([self syncChanges], @"Sync failed");
    
    // Fetch objects on device 2
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Parent"];
    NSArray *parents = [context2 executeFetchRequest:fetch error:NULL];
    id parentOnDevice2 = [parents lastObject];

    NSMutableOrderedSet *childrenOnDevice2 = [[parentOnDevice2 valueForKey:@"orderedChildren"] mutableCopy];
    XCTAssertEqual(childrenOnDevice2.count, (NSUInteger)3, @"Expected 3 children");

    // On device one, add a new object at index 1 (child1,child4,child2,child3)
    [context1 refreshObject:parent mergeChanges:NO];

    id child4OnDevice1 = [NSEntityDescription insertNewObjectForEntityForName:@"Child" inManagedObjectContext:context1];
    [child4OnDevice1 setName:@"child4"];
    set = [NSOrderedSet orderedSetWithArray:@[child1OnDevice1, child4OnDevice1, child2OnDevice1, child3OnDevice1]];
    [parent setValue:set forKey:@"orderedChildren"];
    XCTAssertTrue([context1 save:NULL], @"Could not save");

    // On device two, do a concurrent swap of indexes 0 and 2 (child3,child2,child1)
    [childrenOnDevice2 moveObjectsAtIndexes:[NSIndexSet indexSetWithIndex:2] toIndex:0];
    [childrenOnDevice2 moveObjectsAtIndexes:[NSIndexSet indexSetWithIndex:2] toIndex:1];
    [parentOnDevice2 setValue:childrenOnDevice2 forKey:@"orderedChildren"];
    XCTAssertTrue([context2 save:NULL], @"Could not save");

    XCTAssertNil([self syncChanges], @"Sync failed");
    
    [context1 refreshObject:parent mergeChanges:NO];
    [context2 refreshObject:parentOnDevice2 mergeChanges:NO];
    
    NSOrderedSet *finalDevice1Set = [parent valueForKey:@"orderedChildren"];
    NSOrderedSet *finalDevice2Set = [parentOnDevice2 valueForKey:@"orderedChildren"];

    NSString *set1Items = [[finalDevice1Set.array valueForKeyPath:@"name"] componentsJoinedByString:@","];
    NSString *set2Items = [[finalDevice2Set.array valueForKeyPath:@"name"] componentsJoinedByString:@","];
    XCTAssert([set1Items isEqualToString:set2Items], @"Expected consistent merge results");
}

@end
