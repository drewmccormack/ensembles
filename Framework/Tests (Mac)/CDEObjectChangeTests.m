//
//  CDEObjectChangeTests.m
//  Ensembles
//
//  Created by Drew McCormack on 01/07/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "CDEEventStoreTestCase.h"
#import "CDEStoreModificationEvent.h"
#import "CDEObjectChange.h"
#import "CDEGlobalIdentifier.h"
#import "CDEEventRevision.h"

@interface CDEObjectChangeTests : CDEEventStoreTestCase

@end

@implementation CDEObjectChangeTests {
    CDEStoreModificationEvent *modEvent;
    CDEGlobalIdentifier *globalId;
    CDEObjectChange *objectChange;
}

- (void)setUp
{
    [super setUp];
    [self.eventStore.managedObjectContext performBlockAndWait:^{
        modEvent = [NSEntityDescription insertNewObjectForEntityForName:@"CDEStoreModificationEvent" inManagedObjectContext:self.eventStore.managedObjectContext];
        modEvent.timestamp = 123;
        
        CDEEventRevision *revision = [NSEntityDescription insertNewObjectForEntityForName:@"CDEEventRevision" inManagedObjectContext:self.eventStore.managedObjectContext];
        revision.persistentStoreIdentifier = @"1234";
        revision.revisionNumber = 0;
        modEvent.eventRevision = revision;
        
        globalId = [NSEntityDescription insertNewObjectForEntityForName:@"CDEGlobalIdentifier" inManagedObjectContext:self.eventStore.managedObjectContext];
        globalId.globalIdentifier = @"123";
        globalId.nameOfEntity = @"CDEObjectChange";
        
        objectChange = [NSEntityDescription insertNewObjectForEntityForName:@"CDEObjectChange" inManagedObjectContext:self.eventStore.managedObjectContext];
        objectChange.nameOfEntity = @"Hello";
        objectChange.type = CDEObjectChangeTypeUpdate;
        objectChange.storeModificationEvent = modEvent;
        objectChange.globalIdentifier = globalId;
        objectChange.propertyChangeValues = @[@"a", @"b"];
    }];
}

- (void)tearDown
{
    [super tearDown];
}

- (void)testRequiredProperties
{
    [self.eventStore.managedObjectContext performBlockAndWait:^{
        NSError *error;
        objectChange.nameOfEntity = nil;
        BOOL success = [self.eventStore.managedObjectContext save:NULL];
        XCTAssertFalse(success, @"Should not save with no entity name");
        
        objectChange.nameOfEntity = @"Hello";
        objectChange.storeModificationEvent = nil;
        success = [self.eventStore.managedObjectContext save:NULL];
        XCTAssertFalse(success, @"Should not save with no store mod event");
        
        objectChange.storeModificationEvent = modEvent;
        objectChange.globalIdentifier = nil;
        success = [self.eventStore.managedObjectContext save:NULL];
        XCTAssertFalse(success, @"Should not save with no global id");
        
        objectChange.propertyChangeValues = @[@"a", @"b"];
        objectChange.globalIdentifier = globalId;
        success = [self.eventStore.managedObjectContext save:&error];
        XCTAssertTrue(success, @"Should save with all required set: %@", error);
        
        objectChange.propertyChangeValues = nil;
        success = [self.eventStore.managedObjectContext save:&error];
        XCTAssertFalse(success, @"Should not save for update with nil as propertyChangeValues");

    }];
}

- (void)testPropertyValuesSavedAndRestored
{
    [self.eventStore.managedObjectContext performBlockAndWait:^{
        objectChange.propertyChangeValues = @[@"val"];
        NSError *error;
        BOOL success = [self.eventStore.managedObjectContext save:&error];
        XCTAssertTrue(success, @"Failed to save: %@", error);
        [self.eventStore.managedObjectContext refreshObject:objectChange mergeChanges:NO];
        NSArray *values = objectChange.propertyChangeValues;
        XCTAssertEqualObjects(values[0], @"val", @"Wrong values");
    }];
}

@end
