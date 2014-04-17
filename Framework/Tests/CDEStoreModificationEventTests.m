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
    [eventBuilder makeNewEventOfType:CDEStoreModificationEventTypeSave uniqueIdentifier:nil];
    [eventBuilder finalizeNewEvent];
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
        XCTAssertTrue(event.objectChanges.count == 1, @"Should be an object change initially");
    }];
}

- (void)testFetchingOnTypeAndStore
{
    NSManagedObjectContext *context = self.eventStore.managedObjectContext;
    
    CDEEventBuilder *b = [[CDEEventBuilder alloc] initWithEventStore:(id)self.eventStore];
    [b makeNewEventOfType:CDEStoreModificationEventTypeMerge uniqueIdentifier:nil];
    [b finalizeNewEvent];

    b = [[CDEEventBuilder alloc] initWithEventStore:(id)self.eventStore];
    [b makeNewEventOfType:CDEStoreModificationEventTypeBaseline uniqueIdentifier:nil];
    [b finalizeNewEvent];

    b = [[CDEEventBuilder alloc] initWithEventStore:(id)self.eventStore];
    [b makeNewEventOfType:CDEStoreModificationEventTypeMerge uniqueIdentifier:nil];
    [b finalizeNewEvent];
    
    [context performBlockAndWait:^{
        b.event.eventRevision.persistentStoreIdentifier = @"123";
        
        NSArray *types = @[@(CDEStoreModificationEventTypeMerge)];
        NSArray *events = [CDEStoreModificationEvent fetchStoreModificationEventsWithTypes:types persistentStoreIdentifier:@"123" inManagedObjectContext:context];
        XCTAssertEqual(events.count, (NSUInteger)1, @"Wrong number of events when fetching or a particular store");
        
        types = @[@(CDEStoreModificationEventTypeMerge), @(CDEStoreModificationEventTypeSave)];
        events = [CDEStoreModificationEvent fetchStoreModificationEventsWithTypes:types persistentStoreIdentifier:nil inManagedObjectContext:context];
        XCTAssertEqual(events.count, (NSUInteger)3, @"Wrong number of save/merge");
        
        events = [CDEStoreModificationEvent fetchStoreModificationEventsWithTypes:nil persistentStoreIdentifier:@"123" inManagedObjectContext:context];
        XCTAssertEqual(events.count, (NSUInteger)1, @"Wrong number of events for particular store");
    }];
}

@end
