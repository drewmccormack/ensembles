//
//  CDEIntegratorTests.m
//  Ensembles
//
//  Created by Drew McCormack on 17/08/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "CDEIntegratorTestCase.h"

@interface CDEEventIntegrator (TestMethods)

- (BOOL)needsFullIntegration;

@end


@interface CDEIntegratorTests : CDEIntegratorTestCase

@end


@implementation CDEIntegratorTests {
    CDEStoreModificationEvent *modEvent;
    CDEGlobalIdentifier *globalId1, *globalId2, *globalId3;
    CDEObjectChange *objectChange1, *objectChange2, *objectChange3;
}

- (void)setUp
{
    [super setUp];

    NSManagedObjectContext *moc = self.eventStore.managedObjectContext;
    [self.eventStore.managedObjectContext performBlockAndWait:^{
        modEvent = [self addModEventForStore:@"store2" revision:0 timestamp:123];
                
        globalId1 = [self addGlobalIdentifier:@"parent1" forEntity:@"Parent"];
        globalId2 = [self addGlobalIdentifier:@"child1" forEntity:@"Child"];
        globalId3 = [self addGlobalIdentifier:@"parent2" forEntity:@"Parent"];

        objectChange1 = [self addObjectChangeOfType:CDEObjectChangeTypeInsert withGlobalIdentifier:globalId1 toEvent:modEvent];
        CDEPropertyChangeValue *dateChangeValue = [self attributeChangeForName:@"date" value:[NSDate dateWithTimeIntervalSinceReferenceDate:0]];
        CDEPropertyChangeValue *childChange = [self toOneRelationshipChangeForName:@"child" relatedIdentifier:globalId2.globalIdentifier];
        CDEPropertyChangeValue *nameChange = [self attributeChangeForName:@"name" value:@"parent1"];
        objectChange1.propertyChangeValues = @[dateChangeValue, childChange, nameChange];
        
        objectChange2 = [self addObjectChangeOfType:CDEObjectChangeTypeInsert withGlobalIdentifier:globalId2 toEvent:modEvent];
        CDEPropertyChangeValue *parentChange = [self toOneRelationshipChangeForName:@"parent" relatedIdentifier:globalId1.globalIdentifier];
        objectChange2.propertyChangeValues = @[parentChange];
        
        objectChange3 = [self addObjectChangeOfType:CDEObjectChangeTypeInsert withGlobalIdentifier:globalId3 toEvent:modEvent];
        CDEPropertyChangeValue *dateChangeValue1 = [self attributeChangeForName:@"date" value:nil];
        CDEPropertyChangeValue *nameChange1 = [self attributeChangeForName:@"name" value:@"parent2"];
        objectChange3.propertyChangeValues = @[dateChangeValue1, nameChange1];
        
        [moc save:NULL];
        [self.eventStore updateRevisionsForSave];
    }];
}

- (void)testInsertGeneratesObjects
{
    [self mergeEvents];
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Parent"];
    NSArray *parents = [self.testManagedObjectContext executeFetchRequest:fetch error:NULL];
    XCTAssertEqual(parents.count, (NSUInteger)2, @"Wrong number of parents");
}

- (void)testInsertSetsAttribute
{
    [self mergeEvents];
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Parent"];
    NSArray *parents = [self.testManagedObjectContext executeFetchRequest:fetch error:NULL];
    parents = [parents filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"name = \"parent1\""]];
    id parent = parents.lastObject;
    XCTAssertEqualObjects([parent valueForKey:@"date"], [NSDate dateWithTimeIntervalSinceReferenceDate:0], @"Wrong date attribute");
}

- (void)testInsertSetsNilAttribute
{
    [self mergeEvents];
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Parent"];
    NSArray *parents = [self.testManagedObjectContext executeFetchRequest:fetch error:NULL];
    parents = [parents filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"name = \"parent2\""]];
    id parent = parents.lastObject;
    XCTAssertEqualObjects([parent valueForKey:@"date"], nil, @"Wrong date attribute");
}

- (void)testInsertSetsRelationship
{
    [self mergeEvents];
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Parent"];
    NSArray *parents = [self.testManagedObjectContext executeFetchRequest:fetch error:NULL];
    parents = [parents filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"name = \"parent1\""]];
    id parent = parents.lastObject;
    XCTAssertNotNil([parent valueForKey:@"child"], @"Should have a child object");
}

- (void)testMergeWithNoRepairGeneratesAStoreModificationEvent
{
    [self mergeEvents];
    NSManagedObjectContext *moc = self.eventStore.managedObjectContext;
    [self.eventStore.managedObjectContext performBlockAndWait:^{
        NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"CDEStoreModificationEvent"];
        fetch.predicate = [NSPredicate predicateWithFormat:@"type = %d", CDEStoreModificationEventTypeMerge];
        XCTAssertEqual([moc countForFetchRequest:fetch error:NULL], (NSUInteger)1, @"Should be a merge event");
    }];
}

- (void)testMergeWithRepairGeneratesStoreModificationEvent
{
    self.integrator.shouldSaveBlock = ^(NSManagedObjectContext *savingContext, NSManagedObjectContext *reparationContext) {
        [NSEntityDescription insertNewObjectForEntityForName:@"Parent" inManagedObjectContext:savingContext];
        return YES;
    };
    
    [self mergeEvents];
    
    NSManagedObjectContext *moc = self.eventStore.managedObjectContext;
    [self.eventStore.managedObjectContext performBlockAndWait:^{
        NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"CDEStoreModificationEvent"];
        fetch.predicate = [NSPredicate predicateWithFormat:@"type = %d", CDEStoreModificationEventTypeMerge];
        XCTAssertEqual([moc countForFetchRequest:fetch error:NULL], (NSUInteger)1, @"Should be a merge event");
        
        CDEStoreModificationEvent *merge = [[self.eventStore.managedObjectContext executeFetchRequest:fetch error:NULL] lastObject];
        XCTAssertEqual(merge.globalCount, (CDEGlobalCount)1, @"Wrong global count");
        XCTAssertEqual(merge.eventRevision.revisionNumber, (CDERevisionNumber)1, @"Wrong revision number");
    }];
}

- (void)testNilBaselineIdRequiresFullIntegration
{
    self.eventStore.identifierOfBaselineUsedToConstructStore = nil;
    self.eventStore.currentBaselineIdentifier = @"1";
    XCTAssertTrue([self.integrator needsFullIntegration], @"With nil as id, should do full integration");
}


- (void)testNonMatchingBaselineIdsRequireFullIntegration
{
    self.eventStore.identifierOfBaselineUsedToConstructStore = @"2";
    self.eventStore.currentBaselineIdentifier = @"1";
    XCTAssertTrue([self.integrator needsFullIntegration], @"With different ids, should do full integration");
}

@end
