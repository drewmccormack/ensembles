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
    self.integrator.failedSaveBlock = ^(NSManagedObjectContext *context, NSError *error) {
        NSManagedObjectID *parentID = [error.userInfo[@"NSValidationErrorObject"] objectID];
        NSManagedObject *parent = [context existingObjectWithID:parentID error:NULL];
        [parent setValue:@(0) forKey:@"invalidatingAttribute"];
        return YES;
    };
    self.integrator.didSaveBlock = ^(NSManagedObjectContext *context, NSDictionary *info) {
        didSave = YES;
    };
    [self mergeEventsSinceRevision:-1];
    XCTAssertTrue(didSave, @"Did not successfully save");
}

@end
