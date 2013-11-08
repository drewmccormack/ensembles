//
//  CDEManagedObjectModelTests.m
//  Ensembles Mac
//
//  Created by Drew McCormack on 08/11/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "NSManagedObjectModel+CDEAdditions.h"

@interface CDEManagedObjectModelTests : XCTestCase

@end

@implementation CDEManagedObjectModelTests {
    NSManagedObjectModel *model;
}

- (void)setUp
{
    [super setUp];
    
    NSURL *url = [[NSBundle bundleForClass:self.class] URLForResource:@"CDEStoreModificationEventTestsModel" withExtension:@"momd"];
    model = [[NSManagedObjectModel alloc] initWithContentsOfURL:url];
}

- (void)tearDown
{
    [super tearDown];
}

- (void)testModelCreated
{
    XCTAssertNotNil(model, @"Model not created");
}

- (void)testModelHash
{
    NSString *hash = [model cde_modelHash];
    NSString *childHash = model.entityVersionHashesByName[@"Child"];
    NSString *parentHash = model.entityVersionHashesByName[@"Parent"];
    NSString *expectedHash = [NSString stringWithFormat:@"Child_%@__Parent_%@", childHash, parentHash];
    XCTAssertEqualObjects(hash, expectedHash, @"Hash wrong");
}

@end
