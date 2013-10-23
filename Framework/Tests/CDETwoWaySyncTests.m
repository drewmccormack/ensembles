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

    [context1 refreshObject:parent mergeChanges:NO];
    
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Parent"];
    NSArray *parents = [context2 executeFetchRequest:fetch error:NULL];
    id parentOnDevice2 = parents.lastObject;
    XCTAssertNil(parentOnDevice2, @"Expected no Parent entities");

    // This sync will move the object into the second context
    XCTAssertNil([self syncChanges], @"Sync failed");

    fetch = [NSFetchRequest fetchRequestWithEntityName:@"Parent"];
    parents = [context2 executeFetchRequest:fetch error:NULL];
    parentOnDevice2 = parents.lastObject;

    NSMutableOrderedSet *childrenOnDevice2 = [[parentOnDevice2 valueForKey:@"orderedChildren"] mutableCopy];
    XCTAssert(childrenOnDevice2.count == 3, @"Expected 3 children");

    // Reorder the children on device 2
    [childrenOnDevice2 moveObjectsAtIndexes:[NSIndexSet indexSetWithIndex:2] toIndex:1];

    [parentOnDevice2 setValue:childrenOnDevice2 forKey:@"orderedChildren"];

    XCTAssertTrue([context2 save:NULL], @"Could not save");
    
    XCTAssertNil([self syncChanges], @"Sync failed");

    [context1 refreshObject:parent mergeChanges:NO];

    id parentOnDevice1 = [child1OnDevice1 valueForKey:@"orderedParent"];
    [context1 refreshObject:parentOnDevice1 mergeChanges:NO];

    NSOrderedSet *orderedChildrenOnDevice1 = [parentOnDevice1 valueForKey:@"orderedChildren"];
    XCTAssert(orderedChildrenOnDevice1.count == 3, @"Expected 3 children");
    XCTAssertNotNil(parentOnDevice1, @"No parent");

    XCTAssertTrue(orderedChildrenOnDevice1.array[0] == child1OnDevice1, @"Incorrect order");
    XCTAssertTrue(orderedChildrenOnDevice1.array[1] == child3OnDevice1, @"Incorrect order");
    XCTAssertTrue(orderedChildrenOnDevice1.array[2] == child2OnDevice1, @"Incorrect order");
}

- (void)testUpdateConflictingOrderedRelationship
{
    [self leechStores];
    
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
    
    [context1 refreshObject:parent mergeChanges:NO];
    
    // This sync will move the object into the second context
    XCTAssertNil([self syncChanges], @"Sync failed");
    
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Parent"];
    fetch = [NSFetchRequest fetchRequestWithEntityName:@"Parent"];
    NSArray *parents = [context2 executeFetchRequest:fetch error:NULL];
    id parentOnDevice2 = [parents lastObject];

    NSMutableOrderedSet *childrenOnDevice2 = [[parentOnDevice2 valueForKey:@"orderedChildren"] mutableCopy];
    XCTAssert(childrenOnDevice2.count == 3, @"Expected 3 children");

    // On device one, add a new object at index 1 (child1,child4,child2,child3)
    id child4OnDevice1 = [NSEntityDescription insertNewObjectForEntityForName:@"Child" inManagedObjectContext:context1];
    [child4OnDevice1 setName:@"child4"];
    set = [NSOrderedSet orderedSetWithArray:@[ child1OnDevice1, child4OnDevice1, child2OnDevice1, child3OnDevice1]];
    [parent setValue:set forKey:@"orderedChildren"];
    XCTAssertTrue([context1 save:NULL], @"Could not save");

    // On device two, swap indices 0 and 2 (child3,child2,child1)
    [childrenOnDevice2 moveObjectsAtIndexes:[NSIndexSet indexSetWithIndex:2] toIndex:0];
    [childrenOnDevice2 moveObjectsAtIndexes:[NSIndexSet indexSetWithIndex:2] toIndex:1];
    [parentOnDevice2 setValue:childrenOnDevice2 forKey:@"orderedChildren"];
    XCTAssertTrue([context2 save:NULL], @"Could not save");

    XCTAssertNil([self syncChanges], @"Sync failed");
    
    [context1 refreshObject:parent mergeChanges:NO];
    [context2 refreshObject:parentOnDevice2 mergeChanges:NO];
    
    NSOrderedSet *finalDevice1Set = [parent valueForKey:@"orderedChildren"];
    NSOrderedSet *finalDevice2Set = [parentOnDevice2 valueForKey:@"orderedChildren"];

    NSString *set1Items = [[finalDevice1Set.array valueForKey:@"name"] componentsJoinedByString:@","];
    NSString *set2Items = [[finalDevice2Set.array valueForKey:@"name"] componentsJoinedByString:@","];
    XCTAssertEqual(set1Items, set2Items, @"Expected consistent merge results");
}

@end
