//
//  CDEMergeRepairTests.m
//  Ensembles Mac
//
//  Created by Drew McCormack on 15/11/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "CDEEventIntegrator.h"
#import "CDEIntegratorTestCase.h"

@interface CDEIntegratorMergeRepairTests : CDEIntegratorTestCase

@end

@implementation CDEIntegratorMergeRepairTests {
}

- (void)setUp
{
    [super setUp];
    
    // Add event
    NSString *path = [[NSBundle bundleForClass:self.class] pathForResource:@"IntegratorMergeTestsFixture" ofType:@"json"];
    [self addEventsFromJSONFile:path];
    
    // Handle failed save
    self.integrator.failedSaveBlock = ^(NSManagedObjectContext *context, NSError *error) {
        NSManagedObjectID *parentID = [error.userInfo[@"NSValidationErrorObject"] objectID];
        NSManagedObject *parent = [context existingObjectWithID:parentID error:NULL];
        [parent setValue:@(0) forKey:@"invalidatingAttribute"];
        return YES;
    };
}

- (void)tearDown
{
    [super tearDown];
}

- (void)testFailsToSaveDueToInvalidAttribute
{
    __block BOOL failBlockInvoked = NO;
    __block NSError *failError = nil;
    self.integrator.failedSaveBlock = ^(NSManagedObjectContext *context, NSError *error) {
        failBlockInvoked = YES;
        failError = error;
        return NO;
    };
    [self mergeEventsSinceRevision:-1];
    
    XCTAssert(failBlockInvoked, @"Fail block not invoked");
    XCTAssertNotNil(failError, @"Should give an error");
    XCTAssertEqual(failError.code, (NSInteger)NSValidationNumberTooSmallError, @"Should give an error");
}

- (void)testRepairInFailLeadsToSuccessfulMerge
{
    __block BOOL didSave = NO;
    self.integrator.didSaveBlock = ^(NSManagedObjectContext *context, NSDictionary *info) {
        didSave = YES;
    };
    [self mergeEventsSinceRevision:-1];
    XCTAssertTrue(didSave, @"Did not successfully save");
}

- (void)testMergeEventIncludesObjectChanges
{
    [self mergeEventsSinceRevision:-1];

    [self.eventStore.managedObjectContext performBlockAndWait:^{
        NSArray *events = [CDEStoreModificationEvent fetchStoreModificationEventsForPersistentStoreIdentifier:self.eventStore.persistentStoreIdentifier sinceRevisionNumber:-1 inManagedObjectContext:self.eventStore.managedObjectContext];
        CDEStoreModificationEvent *mergeEvent = events.lastObject;
        XCTAssertNotNil(mergeEvent, @"There was no merge event generated");
        XCTAssertEqual(mergeEvent.objectChanges.count, (NSUInteger)1, @"Wrong number of object changes");
        
        CDEObjectChange *objectChange = mergeEvent.objectChanges.anyObject;
        XCTAssertEqual(objectChange.propertyChangeValues.count, (NSUInteger)1, @"Wrong number of property change values");

        CDEPropertyChangeValue *propertyChange = objectChange.propertyChangeValues.lastObject;
        XCTAssertEqualObjects(propertyChange.propertyName, @"invalidatingAttribute", @"Wrong property");
        XCTAssertEqualObjects(propertyChange.value, @(0), @"Wrong value");
    }];
}

- (void)testRepairInWillSaveBlockAvoidsFail
{
    self.integrator.willSaveBlock = ^(NSManagedObjectContext *context, NSDictionary *info) {
        NSManagedObjectID *parentID = [info[NSInsertedObjectsKey] anyObject];
        NSManagedObject *parent = [context existingObjectWithID:parentID error:NULL];
        [parent setValue:@(0) forKey:@"invalidatingAttribute"];
    };
    
    __block BOOL failBlockInvoked = NO;
    __block NSError *failError = nil;
    self.integrator.failedSaveBlock = ^(NSManagedObjectContext *context, NSError *error) {
        failBlockInvoked = YES;
        failError = error;
        return NO;
    };
    [self mergeEventsSinceRevision:-1];
    
    XCTAssertFalse(failBlockInvoked, @"Fail block not invoked");
}

- (void)testRelationshipUpdateGeneratesObjectChange
{
    self.integrator.willSaveBlock = ^(NSManagedObjectContext *context, NSDictionary *info) {
        NSManagedObjectID *parentID = [info[NSInsertedObjectsKey] anyObject];
        NSManagedObject *parent = [context existingObjectWithID:parentID error:NULL];
        id child = [NSEntityDescription insertNewObjectForEntityForName:@"Child" inManagedObjectContext:context];
        [parent setValue:child forKey:@"child"];
        [parent setValue:@(0) forKey:@"invalidatingAttribute"];
    };
    
    [self mergeEventsSinceRevision:-1];
    
    [self.eventStore.managedObjectContext performBlockAndWait:^{
        NSArray *events = [CDEStoreModificationEvent fetchStoreModificationEventsForPersistentStoreIdentifier:self.eventStore.persistentStoreIdentifier sinceRevisionNumber:-1 inManagedObjectContext:self.eventStore.managedObjectContext];
        CDEStoreModificationEvent *mergeEvent = events.lastObject;
        
        NSSet *objectChanges = mergeEvent.objectChanges;
        XCTAssertEqual(objectChanges.count, (NSUInteger)2, @"Should be change for parent, and change for child");
        
        NSSet *changes = [objectChanges filteredSetUsingPredicate:[NSPredicate predicateWithFormat:@"nameOfEntity = \"Parent\""]];
        CDEObjectChange *parentChange = [changes anyObject];
        XCTAssertEqual(parentChange.propertyChangeValues.count, (NSUInteger)2, @"Wrong property change values on parent");
       
        changes = [objectChanges filteredSetUsingPredicate:[NSPredicate predicateWithFormat:@"nameOfEntity = \"Child\""]];
        CDEObjectChange *childChange = [changes anyObject];
        XCTAssertEqual(childChange.type, CDEObjectChangeTypeInsert, @"Should be insert type");
    }];

}

@end
