//
//  CDEStoreModificationEventTests.m
//  Ensembles
//
//  Created by Drew McCormack on 30/06/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "CDEEventBuilder.h"
#import "CDEEventStore.h"
#import "CDEStoreModificationEvent.h"
#import "CDEEventStoreTestCase.h"
#import "CDERevisionSet.h"
#import "CDERevision.h"
#import "CDEEventRevision.h"

@interface CDEStoreModificationEventTests : CDEEventStoreTestCase

@end

@implementation CDEStoreModificationEventTests {
    CDEStoreModificationEvent *event;
    CDEEventBuilder *eventBuilder;
    NSManagedObjectContext *testManagedObjectContext;
}

- (void)setUp
{
    [super setUp];
        
    // Test Core Data stack
    NSURL *testModelURL = [[NSBundle bundleForClass:self.class] URLForResource:@"CDEStoreModificationEventTestsModel" withExtension:@"momd"];
    NSManagedObjectModel *testModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:testModelURL];
    NSPersistentStoreCoordinator *testPSC = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:testModel];
    [testPSC addPersistentStoreWithType:NSInMemoryStoreType configuration:nil URL:nil options:nil error:NULL];
    testManagedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSConfinementConcurrencyType];
    testManagedObjectContext.persistentStoreCoordinator = testPSC;
    
    // Event Builder
    eventBuilder = [[CDEEventBuilder alloc] initWithEventStore:(id)self.eventStore];
    [eventBuilder makeNewEventOfType:CDEStoreModificationEventTypeSave];
    event = eventBuilder.event;
}

- (void)testInitialization
{
    XCTAssertNotNil(event, @"Event was nil");
}

- (void)testInitiallyEmpty
{
    [self.eventStore.managedObjectContext performBlockAndWait:^{
        XCTAssertTrue(event.objectChanges.count == 0, @"Should be no object changes initially");
    }];
}

- (void)testAddingInsertChangeProducesChangeObject
{
    id object = [NSEntityDescription insertNewObjectForEntityForName:@"Parent" inManagedObjectContext:testManagedObjectContext];
    NSSet *objects = [NSSet setWithObject:object];
    [testManagedObjectContext obtainPermanentIDsForObjects:objects.allObjects error:NULL];
    [eventBuilder addChangesForInsertedObjects:objects objectsAreSaved:NO inManagedObjectContext:testManagedObjectContext];
    [self.eventStore.managedObjectContext performBlockAndWait:^{
        XCTAssertTrue(event.objectChanges.count == 1, @"Should be no object changes initially");
    }];
}

@end
