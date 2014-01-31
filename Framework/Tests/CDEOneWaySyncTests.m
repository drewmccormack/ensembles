//
//  CDEOneWaySyncTest.m
//  Ensembles
//
//  Created by Drew McCormack on 9/14/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import "CDESyncTest.h"
#import "CDEPersistentStoreEnsemble.h"
#import "CDELocalCloudFileSystem.h"

@interface CDEOneWaySyncTests : CDESyncTest <CDEPersistentStoreEnsembleDelegate>

@end

@implementation CDEOneWaySyncTests

- (void)testLeeching
{
    [ensemble1 leechPersistentStoreWithCompletion:^(NSError *error) {
        XCTAssertNil(error, @"Error during leech");
        [self completeAsync];
    }];
    [self waitForAsync];
    
    XCTAssert(ensemble1.isLeeched, @"Should be leeched");
}

- (void)testLeechingTwiceGivesError
{
    [ensemble1 leechPersistentStoreWithCompletion:^(NSError *error) {
        XCTAssertNil(error, @"Error during leech");
        [ensemble1 leechPersistentStoreWithCompletion:^(NSError *error) {
            XCTAssertNotNil(error, @"Should get error in during second leech");
            [self completeAsync];
        }];
    }];
    [self waitForAsync];
    
    XCTAssert(ensemble1.isLeeched, @"Should be leeched");
}

- (void)testDeleeching
{
    [ensemble1 leechPersistentStoreWithCompletion:^(NSError *error) {
        [ensemble1 deleechPersistentStoreWithCompletion:^(NSError *error) {
            XCTAssertNil(error, @"Error during deleech");
            [self completeAsync];
        }];
    }];
    [self waitForAsync];
    
    XCTAssertFalse(ensemble1.isLeeched, @"Should not be leeched");
}

- (void)testDeleechingTwiceGivesError
{
    [ensemble1 leechPersistentStoreWithCompletion:^(NSError *error) {
        [ensemble1 deleechPersistentStoreWithCompletion:^(NSError *error) {
            [ensemble1 deleechPersistentStoreWithCompletion:^(NSError *error) {
                XCTAssertNotNil(error, @"Should be error during second deleech");
                [self completeAsync];
            }];
        }];
    }];
    [self waitForAsync];
    
    XCTAssertFalse(ensemble1.isLeeched, @"Should not be leeched");
}

- (void)testSaveAndMerge
{
    [self leechStores];
    
    id parent = [NSEntityDescription insertNewObjectForEntityForName:@"Parent" inManagedObjectContext:context1];
    NSDate *date = [NSDate dateWithTimeIntervalSinceReferenceDate:10.0];
    [parent setValue:@"bob" forKey:@"name"];
    [parent setValue:date forKey:@"date"];
    XCTAssertTrue([context1 save:NULL], @"Could not save");

    XCTAssertNil([self syncChanges], @"Sync failed");
    
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Parent"];
    NSArray *parents = [context2 executeFetchRequest:fetch error:NULL];
    XCTAssertEqual(parents.count, (NSUInteger)1, @"No parent found");
    
    id syncedParent = parents.lastObject;
    XCTAssertEqualObjects([syncedParent valueForKey:@"name"], @"bob", @"Wrong name");
    XCTAssertEqualObjects([syncedParent valueForKey:@"date"], date, @"Wrong date");
}

- (void)testUpdate
{
    [self leechStores];
    
    id parent = [NSEntityDescription insertNewObjectForEntityForName:@"Parent" inManagedObjectContext:context1];
    NSDate *date = [NSDate dateWithTimeIntervalSinceReferenceDate:10.0];
    [parent setValue:@"bob" forKey:@"name"];
    [parent setValue:date forKey:@"date"];
    XCTAssertTrue([context1 save:NULL], @"Could not save");
    
    XCTAssertNil([self syncChanges], @"First sync failed");

    [parent setValue:@"dave" forKey:@"name"];
    XCTAssertTrue([context1 save:NULL], @"Could not save");

    NSError *syncError = [self syncChanges];
    XCTAssertNil(syncError, @"Second sync failed");
    
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Parent"];
    NSArray *parents = [context2 executeFetchRequest:fetch error:NULL];
    XCTAssertEqual(parents.count, (NSUInteger)1, @"No parent found");
    
    id syncedParent = parents.lastObject;
    XCTAssertEqualObjects([syncedParent valueForKey:@"name"], @"dave", @"Wrong name");
    XCTAssertEqualObjects([syncedParent valueForKey:@"date"], date, @"Wrong date");
}

- (void)testToOneRelationship
{
    [self leechStores];
    
    id parent = [NSEntityDescription insertNewObjectForEntityForName:@"Parent" inManagedObjectContext:context1];
    id child = [NSEntityDescription insertNewObjectForEntityForName:@"Child" inManagedObjectContext:context1];
    [child setValue:parent forKey:@"parent"];
    XCTAssertTrue([context1 save:NULL], @"Could not save");
    
    XCTAssertNil([self syncChanges], @"Sync failed");
    
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Parent"];
    NSArray *parents = [context2 executeFetchRequest:fetch error:NULL];
    XCTAssertEqual(parents.count, (NSUInteger)1, @"No parent found");
    
    fetch = [NSFetchRequest fetchRequestWithEntityName:@"Child"];
    NSArray *children = [context2 executeFetchRequest:fetch error:NULL];
    XCTAssertEqual(children.count, (NSUInteger)1, @"No child found");
    
    id syncedParent = parents.lastObject;
    id syncedChild = children.lastObject;
    XCTAssertEqualObjects(syncedChild, [syncedParent valueForKey:@"child"], @"Relationship not set");
}

- (void)testToManyRelationship
{
    [self leechStores];
    
    id parent = [NSEntityDescription insertNewObjectForEntityForName:@"Parent" inManagedObjectContext:context1];
    id child = [NSEntityDescription insertNewObjectForEntityForName:@"Child" inManagedObjectContext:context1];
    [child setValue:parent forKey:@"parentWithSiblings"];
    XCTAssertTrue([context1 save:NULL], @"Could not save");
    
    XCTAssertNil([self syncChanges], @"Sync failed");
    
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Parent"];
    NSArray *parents = [context2 executeFetchRequest:fetch error:NULL];
    fetch = [NSFetchRequest fetchRequestWithEntityName:@"Child"];
    NSArray *children = [context2 executeFetchRequest:fetch error:NULL];
    
    id syncedParent = parents.lastObject;
    id syncedChild = children.lastObject;
    XCTAssertEqualObjects([[syncedParent valueForKey:@"children"] anyObject], syncedChild, @"Relationship not set");
}

@end
