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

@end
