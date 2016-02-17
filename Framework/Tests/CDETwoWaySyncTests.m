//
//  CDETwoWaySyncTests.m
//  Ensembles
//
//  Created by Drew McCormack on 19/09/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import "CDESyncTest.h"
#import "CDEPersistentStoreEnsemble.h"

@interface CDETwoWaySyncTests : CDESyncTest <CDEPersistentStoreEnsembleDelegate>

@end

@implementation CDETwoWaySyncTests {
    BOOL shouldFailMerge;
}

- (void)setUp
{
    [super setUp];
    shouldFailMerge = NO;
}

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
    
    CDESetCurrentLoggingLevel(CDELoggingLevelVerbose);
    
    NSManagedObject *parentOnDevice2 = parents.lastObject;
    [parentOnDevice2 setValue:@"dave" forKey:@"name"];
    XCTAssertTrue([context2 save:NULL], @"Could not save");
    
    XCTAssertNil([self syncChanges], @"Second sync failed");
    
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
    
    XCTAssertEqualObjects([parentOnDevice1 valueForKey:@"name"], @"dave", @"Wrong name on device 1");
    XCTAssertEqualObjects([parentOnDevice2 valueForKey:@"name"], @"dave", @"Wrong name on device 2");
}

- (void)testConcurrentInsertsOfSameObject
{
    [self leechStores];
    
    ensemble1.delegate = self;
    ensemble2.delegate = self;
    
    id parent1 = [NSEntityDescription insertNewObjectForEntityForName:@"Parent" inManagedObjectContext:context1];
    NSDate *date = [NSDate dateWithTimeIntervalSinceReferenceDate:10.0];
    [parent1 setValue:@"bob" forKey:@"name"];
    [parent1 setValue:date forKey:@"date"];
    XCTAssertTrue([context1 save:NULL], @"Could not save");
    
    id parent2 = [NSEntityDescription insertNewObjectForEntityForName:@"Parent" inManagedObjectContext:context2];
    [parent2 setValue:@"bob" forKey:@"name"];
    [parent2 setValue:date forKey:@"date"];
    XCTAssertTrue([context2 save:NULL], @"Could not save");
    
    XCTAssertNil([self syncChanges], @"Sync failed");
    
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Parent"];
    NSArray *parents = [context2 executeFetchRequest:fetch error:NULL];
    XCTAssertEqual(parents.count, (NSUInteger)1, @"Wrong number of parents found");
    
    parents = [context1 executeFetchRequest:fetch error:NULL];
    XCTAssertEqual(parents.count, (NSUInteger)1, @"Wrong number of parents found");
}

- (void)testConcurrentInsertsOfSameObjectWithInterruptedMerge
{
    [self leechStores];
    
    ensemble1.delegate = self;
    ensemble2.delegate = self;
    
    id parent1 = [NSEntityDescription insertNewObjectForEntityForName:@"Parent" inManagedObjectContext:context1];
    NSDate *date = [NSDate dateWithTimeIntervalSinceReferenceDate:10.0];
    [parent1 setValue:@"bob" forKey:@"name"];
    [parent1 setValue:date forKey:@"date"];
    XCTAssertTrue([context1 save:NULL], @"Could not save");
    
    id parent2 = [NSEntityDescription insertNewObjectForEntityForName:@"Parent" inManagedObjectContext:context2];
    [parent2 setValue:@"bob" forKey:@"name"];
    [parent2 setValue:date forKey:@"date"];
    XCTAssertTrue([context2 save:NULL], @"Could not save");
    
    [self mergeEnsemble:ensemble1];
    
    shouldFailMerge = YES;
    [self mergeEnsemble:ensemble2];
    shouldFailMerge = NO;
    [self mergeEnsemble:ensemble2];
    
    [self mergeEnsemble:ensemble1];
    
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Parent"];
    NSArray *parents = [context2 executeFetchRequest:fetch error:NULL];
    XCTAssertEqual(parents.count, (NSUInteger)1, @"Wrong number of parents found");
    
    parents = [context1 executeFetchRequest:fetch error:NULL];
    XCTAssertEqual(parents.count, (NSUInteger)1, @"Wrong number of parents found");
}

- (void)testImportOfSameObjectOnMultipleDevices
{
    id parent1 = [NSEntityDescription insertNewObjectForEntityForName:@"Parent" inManagedObjectContext:context1];
    NSDate *date = [NSDate dateWithTimeIntervalSinceReferenceDate:10.0];
    [parent1 setValue:@"bob" forKey:@"name"];
    [parent1 setValue:date forKey:@"date"];
    XCTAssertTrue([context1 save:NULL], @"Could not save");
    
    id parent2 = [NSEntityDescription insertNewObjectForEntityForName:@"Parent" inManagedObjectContext:context2];
    [parent2 setValue:@"bob" forKey:@"name"];
    [parent2 setValue:date forKey:@"date"];
    XCTAssertTrue([context2 save:NULL], @"Could not save");
    
    ensemble1.delegate = self;
    ensemble2.delegate = self;
    [self leechStores];
    
    [self syncChanges];
    
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Parent"];
    NSArray *parents = [context2 executeFetchRequest:fetch error:NULL];
    XCTAssertEqual(parents.count, (NSUInteger)1, @"Wrong number of parents found");
    
    parents = [context1 executeFetchRequest:fetch error:NULL];
    XCTAssertEqual(parents.count, (NSUInteger)1, @"Wrong number of parents found");
}

- (NSArray *)persistentStoreEnsemble:(CDEPersistentStoreEnsemble *)ensemble globalIdentifiersForManagedObjects:(NSArray *)objects
{
    return [objects valueForKeyPath:@"name"];
}

- (BOOL)persistentStoreEnsemble:(CDEPersistentStoreEnsemble *)ensemble shouldSaveMergedChangesInManagedObjectContext:(NSManagedObjectContext *)savingContext reparationManagedObjectContext:(NSManagedObjectContext *)reparationContext
{
    return !shouldFailMerge;
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
    
    id newParentOnDevice1 = [childOnDevice1 valueForKey:@"parent"];
    XCTAssertNotNil(newParentOnDevice1, @"No parent");
    XCTAssertNotEqualObjects(parent, newParentOnDevice1, @"Wrong parent");
    XCTAssertEqualObjects([newParentOnDevice1 valueForKey:@"name"], @"newdad", @"Wrong name for new parent");
}

- (void)testUpdateToManyRelationship
{
    [self leechStores];
    
    id parent = [NSEntityDescription insertNewObjectForEntityForName:@"Parent" inManagedObjectContext:context1];
    
    id child1OnDevice1 = [NSEntityDescription insertNewObjectForEntityForName:@"Child" inManagedObjectContext:context1];
    [child1OnDevice1 setValue:@"child1" forKey:@"name"];
    [child1OnDevice1 setValue:parent forKey:@"parentWithSiblings"];

    id child2OnDevice1 = [NSEntityDescription insertNewObjectForEntityForName:@"Child" inManagedObjectContext:context1];
    [child2OnDevice1 setValue:@"child2" forKey:@"name"];
    [child2OnDevice1 setValue:parent forKey:@"parentWithSiblings"];
    
    XCTAssertTrue([context1 save:NULL], @"Could not save");
    XCTAssertNil([self syncChanges], @"Sync failed");
    
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Child"];
    NSArray *children = [context2 executeFetchRequest:fetch error:NULL];
    id child1OnDevice2 = [children filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"name = 'child1'"]][0];
    [context2 deleteObject:child1OnDevice2];
    
    XCTAssertTrue([context2 save:NULL], @"Could not save");
    XCTAssertNil([self syncChanges], @"Sync failed");

    NSSet *childrenOnDevice1 = [parent valueForKey:@"children"];
    XCTAssertEqualObjects([child2OnDevice1 valueForKey:@"name"], @"child2", @"Wrong name for child");
    XCTAssertEqual(childrenOnDevice1.count, (NSUInteger)1, @"Wrong number of children");
    XCTAssertEqualObjects(parent, [child2OnDevice1 valueForKey:@"parentWithSiblings"], @"Wrong child");
}

- (void)testUpdateOrderedRelationship
{
    [self leechStores];
    
    // Create parent with ordered children on device 1
    id parent = [NSEntityDescription insertNewObjectForEntityForName:@"Parent" inManagedObjectContext:context1];

    id child1OnDevice1 = [NSEntityDescription insertNewObjectForEntityForName:@"Child" inManagedObjectContext:context1];
    id child2OnDevice1 = [NSEntityDescription insertNewObjectForEntityForName:@"Child" inManagedObjectContext:context1];
    id child3OnDevice1 = [NSEntityDescription insertNewObjectForEntityForName:@"Child" inManagedObjectContext:context1];
    
    [child1OnDevice1 setValue:@"child1" forKey:@"name"];
    [child2OnDevice1 setValue:@"child2" forKey:@"name"];
    [child3OnDevice1 setValue:@"child3" forKey:@"name"];
    
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

    id parentOnDevice1 = [child1OnDevice1 valueForKey:@"orderedParent"];

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
    
    [child1OnDevice1 setValue:@"child1" forKey:@"name"];
    [child2OnDevice1 setValue:@"child2" forKey:@"name"];
    [child3OnDevice1 setValue:@"child3" forKey:@"name"];
    
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

    id child4OnDevice1 = [NSEntityDescription insertNewObjectForEntityForName:@"Child" inManagedObjectContext:context1];
    [child4OnDevice1 setValue:@"child4" forKey:@"name"];
    set = [NSOrderedSet orderedSetWithArray:@[child1OnDevice1, child4OnDevice1, child2OnDevice1, child3OnDevice1]];
    [parent setValue:set forKey:@"orderedChildren"];
    XCTAssertTrue([context1 save:NULL], @"Could not save");

    // On device two, do a concurrent swap of indexes 0 and 2 (child3,child2,child1)
    [childrenOnDevice2 moveObjectsAtIndexes:[NSIndexSet indexSetWithIndex:2] toIndex:0];
    [childrenOnDevice2 moveObjectsAtIndexes:[NSIndexSet indexSetWithIndex:2] toIndex:1];
    [parentOnDevice2 setValue:childrenOnDevice2 forKey:@"orderedChildren"];
    XCTAssertTrue([context2 save:NULL], @"Could not save");

    XCTAssertNil([self syncChanges], @"Sync failed");
    
    NSOrderedSet *finalDevice1Set = [parent valueForKey:@"orderedChildren"];
    NSOrderedSet *finalDevice2Set = [parentOnDevice2 valueForKey:@"orderedChildren"];

    NSString *set1Items = [[finalDevice1Set.array valueForKeyPath:@"name"] componentsJoinedByString:@","];
    NSString *set2Items = [[finalDevice2Set.array valueForKeyPath:@"name"] componentsJoinedByString:@","];
    XCTAssert([set1Items isEqualToString:set2Items], @"Expected consistent merge results");
}

- (void)testUpdateOrderedRelationshipWithDeletions
{
    [self leechStores];
    
    // Put parent on both devices
    id P1 = [NSEntityDescription insertNewObjectForEntityForName:@"Parent" inManagedObjectContext:context1];
    
    XCTAssertTrue([context1 save:NULL], @"Could not save");
    XCTAssertNil([self syncChanges], @"Sync failed");

    // Device 1
    id A1 = [NSEntityDescription insertNewObjectForEntityForName:@"Child" inManagedObjectContext:context1];
    [A1 setValue:@"A" forKey:@"name"];
    
    NSOrderedSet *set = [NSOrderedSet orderedSetWithArray:@[A1]];
    [P1 setValue:set forKey:@"orderedChildren"];
    
    XCTAssertTrue([context1 save:NULL], @"Could not save");

    // Device 2
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Parent"];
    NSArray *parents = [context2 executeFetchRequest:fetch error:NULL];
    id P2 = [parents lastObject];
    
    id F2 = [NSEntityDescription insertNewObjectForEntityForName:@"Child" inManagedObjectContext:context2];
    id G2 = [NSEntityDescription insertNewObjectForEntityForName:@"Child" inManagedObjectContext:context2];
    id H2 = [NSEntityDescription insertNewObjectForEntityForName:@"Child" inManagedObjectContext:context2];

    [F2 setValue:@"F" forKey:@"name"];
    [G2 setValue:@"G" forKey:@"name"];
    [H2 setValue:@"H" forKey:@"name"];
    
    set = [NSOrderedSet orderedSetWithArray:@[F2, G2, H2]];
    [P2 setValue:set forKey:@"orderedChildren"];
    
    XCTAssertTrue([context2 save:NULL], @"Could not save");

    // Device 1
    id B1 = [NSEntityDescription insertNewObjectForEntityForName:@"Child" inManagedObjectContext:context1];
    id C1 = [NSEntityDescription insertNewObjectForEntityForName:@"Child" inManagedObjectContext:context1];
    id D1 = [NSEntityDescription insertNewObjectForEntityForName:@"Child" inManagedObjectContext:context1];
    id E1 = [NSEntityDescription insertNewObjectForEntityForName:@"Child" inManagedObjectContext:context1];

    [B1 setValue:@"B" forKey:@"name"];
    [C1 setValue:@"C" forKey:@"name"];
    [D1 setValue:@"D" forKey:@"name"];
    [E1 setValue:@"E" forKey:@"name"];
    
    set = [NSOrderedSet orderedSetWithArray:@[A1, B1, C1, D1, E1]];
    [P1 setValue:set forKey:@"orderedChildren"];
    
    XCTAssertTrue([context1 save:NULL], @"Could not save");

    [context1 deleteObject:B1];
    [context1 deleteObject:C1];
    [context1 deleteObject:D1];
    
    XCTAssertTrue([context1 save:NULL], @"Could not save");

    XCTAssertNil([self syncChanges], @"Sync failed");
    
    NSOrderedSet *finalDevice1Set = [P1 valueForKey:@"orderedChildren"];
    NSOrderedSet *finalDevice2Set = [P2 valueForKey:@"orderedChildren"];
    
    NSString *set1Items = [[finalDevice1Set.array valueForKeyPath:@"name"] componentsJoinedByString:@","];
    NSString *set2Items = [[finalDevice2Set.array valueForKeyPath:@"name"] componentsJoinedByString:@","];
    XCTAssert([set1Items isEqualToString:set2Items], @"Expected consistent merge results");
}

- (void)testDeletingAllObjectsAndReinserting
{
    [self leechStores];
    
    ensemble1.delegate = self;
    ensemble2.delegate = self;
    
    // Create all
    [self createNamedParentsAndChildrenInContext:context1];
    XCTAssertTrue([context1 save:NULL], @"Could not save");
    
    // Create all 2
    [self createNamedParentsAndChildrenInContext:context2];
    XCTAssertTrue([context1 save:NULL], @"Could not save");
    
    // Make small, reversible change in 2, to try to mess things up
    NSArray *parents = [self parentsInContext:context2];
    id parent = parents.lastObject;
    id child = [[parent valueForKey:@"children"] anyObject];
    [[parent mutableSetValueForKey:@"children"] removeObject:child];
    XCTAssertTrue([context2 save:NULL], @"Could not save");
    [[parent mutableSetValueForKey:@"children"] addObject:child];
    XCTAssertTrue([context2 save:NULL], @"Could not save");

    // Delete all
    parents = [self parentsInContext:context1];
    for (id parent in parents) [context1 deleteObject:parent];
    XCTAssertTrue([context1 save:NULL], @"Could not save");
    
    // Create all 1
    [self createNamedParentsAndChildrenInContext:context1];
    XCTAssertTrue([context1 save:NULL], @"Could not save");
    
    // Sync
    XCTAssertNil([self syncChanges], @"Sync failed");
    
    // Delete all
    parents = [self parentsInContext:context2];
    for (id parent in parents) [context2 deleteObject:parent];
    XCTAssertTrue([context2 save:NULL], @"Could not save");
    
    // Make sure there are no objects
    NSArray *children = [self childrenInContext:context2];
    XCTAssertEqual(children.count, (NSUInteger)0, @"Wrong number of children in context2 after full delete");
    
    // Recreate objects in second context
    [self createNamedParentsAndChildrenInContext:context2];
    XCTAssertTrue([context2 save:NULL], @"Could not save");

    XCTAssertNil([self syncChanges], @"Sync failed");
    
    parents = [self parentsInContext:context1];
    XCTAssertEqual(parents.count, (NSUInteger)5, @"Wrong number of parents in context1");
    XCTAssertEqual([[parents.lastObject valueForKey:@"children"] count], (NSUInteger)5, @"Wrong number of children of parent in context1");
    XCTAssertEqual([[parents.lastObject valueForKey:@"orderedChildren"] count], (NSUInteger)5, @"Wrong number of ordered children of parent in context1");

    children = [self childrenInContext:context1];
    XCTAssertEqual(children.count, (NSUInteger)50, @"Wrong number of children in context1");
    
    parents = [self parentsInContext:context2];
    XCTAssertEqual(parents.count, (NSUInteger)5, @"Wrong number of parents in context2");
    XCTAssertEqual([[parents.lastObject valueForKey:@"children"] count], (NSUInteger)5, @"Wrong number of children of parent in context2");
    XCTAssertEqual([[parents.lastObject valueForKey:@"orderedChildren"] count], (NSUInteger)5, @"Wrong number of ordered children of parent in context2");
    
    children = [self childrenInContext:context2];
    XCTAssertEqual(children.count, (NSUInteger)50, @"Wrong number of children in context2");
}

- (void)createNamedParentsAndChildrenInContext:(NSManagedObjectContext *)context
{
    // Parents
    for (int i = 0; i < 5; i++) {
        id parent = [NSEntityDescription insertNewObjectForEntityForName:@"Parent" inManagedObjectContext:context];
        [parent setValue:[NSString stringWithFormat:@"%d", i] forKey:@"name"]; // Used as unique id
        
        // Children
        for (int ic = 0; ic < 5; ic++) {
            id child = [NSEntityDescription insertNewObjectForEntityForName:@"Child" inManagedObjectContext:context];
            [child setValue:[NSString stringWithFormat:@"%d_%d", i, ic] forKey:@"name"]; // Used as unique id
            [child setValue:parent forKey:@"parentWithSiblings"];
        }
        
        // Ordered Children
        for (int ic = 0; ic < 5; ic++) {
            id child = [NSEntityDescription insertNewObjectForEntityForName:@"Child" inManagedObjectContext:context];
            [child setValue:[NSString stringWithFormat:@"ordered %d_%d", i, ic] forKey:@"name"]; // Used as unique id
            [[parent mutableOrderedSetValueForKey:@"orderedChildren"] addObject:child];
        }
    }
}

- (NSArray *)childrenInContext:(NSManagedObjectContext *)context
{
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Child"];
    NSArray *children = [context executeFetchRequest:fetch error:NULL];
    return children;
}

- (NSArray *)parentsInContext:(NSManagedObjectContext *)context
{
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Parent"];
    NSArray *parents = [context executeFetchRequest:fetch error:NULL];
    return parents;
}

- (void)testBaselineConsolidationWithLargeData
{
    const uint8_t bytes[10010];
    id parent1 = [NSEntityDescription insertNewObjectForEntityForName:@"Parent" inManagedObjectContext:context1];
    [parent1 setValue:[[NSData alloc] initWithBytes:bytes length:10001] forKey:@"data"];
    [parent1 setValue:@"1" forKey:@"name"];
    [context1 save:NULL];
    
    id parent2 = [NSEntityDescription insertNewObjectForEntityForName:@"Parent" inManagedObjectContext:context2];
    [parent2 setValue:[[NSData alloc] initWithBytes:bytes length:10002] forKey:@"data"];
    [parent2 setValue:@"2" forKey:@"name"];
    [context2 save:NULL];
    
    [self leechStores];
    XCTAssertNil([self syncChanges], @"Error syncing");
    
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Parent"];
    fetch.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES]];
    
    NSArray *parents = [context1 executeFetchRequest:fetch error:NULL];
    XCTAssertEqual([[parents[0] valueForKey:@"data"] length], (NSUInteger) 10001, @"Wrong data length parent 1");
    XCTAssertEqual([[parents[1] valueForKey:@"data"] length], (NSUInteger) 10002, @"Wrong data length parent 2");
    
    NSString *eventStoreDataDir = [eventDataRoot1 stringByAppendingPathComponent:@"com.ensembles.synctest/data"];
    NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:eventStoreDataDir error:NULL];
    XCTAssertEqual(contents.count, (NSUInteger)2, @"Should be a 2 data files for event store 1.");
    
    parents = [context2 executeFetchRequest:fetch error:NULL];
    XCTAssertEqual([[parents[0] valueForKey:@"data"] length], (NSUInteger) 10001, @"Wrong data length parent 1");
    XCTAssertEqual([[parents[1] valueForKey:@"data"] length], (NSUInteger) 10002, @"Wrong data length parent 2");
    
    eventStoreDataDir = [eventDataRoot2 stringByAppendingPathComponent:@"com.ensembles.synctest/data"];
    contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:eventStoreDataDir error:NULL];
    XCTAssertEqual(contents.count, (NSUInteger)2, @"Should be a 2 data files for event store 2.");
}

@end
