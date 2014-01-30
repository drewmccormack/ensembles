//
//  CDEMergeRepairTests.m
//  Ensembles
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
    self.integrator.failedSaveBlock = ^(NSManagedObjectContext *context, NSError *error, NSManagedObjectContext *reparationContext) {
        __block NSManagedObjectID *parentID;
        [context performBlockAndWait:^{
            parentID = [error.userInfo[@"NSValidationErrorObject"] objectID];
        }];
        
        [reparationContext performBlockAndWait:^{
            NSManagedObject *parent = [reparationContext existingObjectWithID:parentID error:NULL];
            [parent setValue:@(0) forKey:@"invalidatingAttribute"];
        }];

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
    self.integrator.failedSaveBlock = ^(NSManagedObjectContext *context, NSError *error, NSManagedObjectContext *reparationContext) {
        failBlockInvoked = YES;
        failError = error;
        return NO;
    };
    [self mergeEvents];
    
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
    [self mergeEvents];
    XCTAssertTrue(didSave, @"Did not successfully save");
}

- (void)testMergeEventIncludesObjectChanges
{
    [self mergeEvents];

    [self.eventStore.managedObjectContext performBlockAndWait:^{
        NSArray *events = [CDEStoreModificationEvent fetchNonBaselineEventsForPersistentStoreIdentifier:self.eventStore.persistentStoreIdentifier sinceRevisionNumber:-1 inManagedObjectContext:self.eventStore.managedObjectContext];
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
    self.integrator.shouldSaveBlock = ^(NSManagedObjectContext *context, NSManagedObjectContext *reparationContext) {
        __block NSManagedObjectID *parentID;
        [reparationContext performBlockAndWait:^{
            NSManagedObject *parent = context.insertedObjects.anyObject;
            parentID = parent.objectID;
        }];

        [reparationContext performBlockAndWait:^{
            NSManagedObject *repairParent = [reparationContext existingObjectWithID:parentID error:NULL];
            [repairParent setValue:@(0) forKey:@"invalidatingAttribute"];
        }];
        
        return YES;
    };
    
    __block BOOL failBlockInvoked = NO;
    __block NSError *failError = nil;
    self.integrator.failedSaveBlock = ^(NSManagedObjectContext *context, NSError *error, NSManagedObjectContext *reparationContext) {
        failBlockInvoked = YES;
        failError = error;
        return NO;
    };
    [self mergeEvents];
    
    XCTAssertFalse(failBlockInvoked, @"Fail block not invoked");
}

- (void)testRelationshipUpdateGeneratesObjectChange
{
    self.integrator.shouldSaveBlock = ^(NSManagedObjectContext *context, NSManagedObjectContext *reparationContext) {
        __block NSManagedObjectID *parentID;
        [reparationContext performBlockAndWait:^{
            NSManagedObject *parent = context.insertedObjects.anyObject;
            parentID = parent.objectID;
        }];
        
        [reparationContext performBlockAndWait:^{
            NSManagedObject *repairParent = [reparationContext existingObjectWithID:parentID error:NULL];
            [repairParent setValue:@(0) forKey:@"invalidatingAttribute"];
            
            id child = [NSEntityDescription insertNewObjectForEntityForName:@"Child" inManagedObjectContext:reparationContext];
            [repairParent setValue:child forKey:@"child"];
            [repairParent setValue:@(0) forKey:@"invalidatingAttribute"];
        }];
        
        return YES;
    };
    
    [self mergeEvents];
    
    [self.eventStore.managedObjectContext performBlockAndWait:^{
        NSArray *events = [CDEStoreModificationEvent fetchNonBaselineEventsForPersistentStoreIdentifier:self.eventStore.persistentStoreIdentifier sinceRevisionNumber:-1 inManagedObjectContext:self.eventStore.managedObjectContext];
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
