//
//  CDEEventStoreTest.m
//  Ensembles
//
//  Created by Drew McCormack on 6/29/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "CDEEventStore.h"

static NSString *rootTestDirectory;

@interface CDEEventStoreTests : XCTestCase

@end

@implementation CDEEventStoreTests {
    CDEEventStore *store;
}

+ (void)setUp
{
    [super setUp];
    rootTestDirectory = [NSTemporaryDirectory() stringByAppendingString:@"CDEEventStoreTests"];
    [[NSFileManager defaultManager] removeItemAtPath:rootTestDirectory error:NULL];
    [[NSFileManager defaultManager] createDirectoryAtPath:rootTestDirectory withIntermediateDirectories:YES attributes:nil error:NULL];
}

+ (void)tearDown
{
    [[NSFileManager defaultManager] removeItemAtPath:rootTestDirectory error:NULL];
    [super tearDown];
}

- (void)setUp
{
    [super setUp];
    [CDEEventStore setDefaultPathToEventDataRootDirectory:rootTestDirectory];
    store = [[CDEEventStore alloc] initWithEnsembleIdentifier:@"test" pathToEventDataRootDirectory:nil];
}

- (void)tearDown
{
    [super tearDown];
    [store removeEventStore];
}

- (void)testInitialization
{
    XCTAssertNotNil(store, @"Store nil");
    XCTAssertEqualObjects(store.ensembleIdentifier, @"test", @"Wrong ensembled identifier");
}

- (void)testHasNoPersistentStoreIdentifierBeforeInstall
{
    XCTAssertNil(store.persistentStoreIdentifier, @"Should not have store id");
}

- (void)testHasNoIncompleteEventsBeforeInstall
{
    XCTAssertNotNil(store.incompleteEventIdentifiers, @"Should return empty array for ids");
    XCTAssertNotNil(store.incompleteMandatoryEventIdentifiers, @"Should return empty array for mandatory ids");
    XCTAssertEqual(store.incompleteEventIdentifiers.count, (NSUInteger)0, @"Should have no ids");
    XCTAssertEqual(store.incompleteMandatoryEventIdentifiers.count, (NSUInteger)0, @"Should have no mandatory ids");
}

- (void)testInstallingEventStore
{
    XCTAssertTrue([store prepareNewEventStore:NULL], @"Install failed");
}

- (void)testHasPersistentStoreIdentifierAfterInstall
{
    [store prepareNewEventStore:NULL];
    XCTAssertNotNil(store.persistentStoreIdentifier, @"Should have store id");
}

- (void)testRegisteringIncompleteEvent
{
    [store prepareNewEventStore:NULL];
    [store registerIncompleteEventIdentifier:@"TestID" isMandatory:NO];
    XCTAssertEqual(store.incompleteEventIdentifiers.count, (NSUInteger)1, @"Should have one incomplete");
    XCTAssertEqualObjects(store.incompleteEventIdentifiers[0], @"TestID", @"Wrong id");
    XCTAssertEqual(store.incompleteMandatoryEventIdentifiers.count, (NSUInteger)0, @"Should have no mandatory");
}

- (void)testRegisteringIncompleteMandatoryEvent
{
    [store prepareNewEventStore:NULL];
    [store registerIncompleteEventIdentifier:@"TestID" isMandatory:YES];
    XCTAssertEqual(store.incompleteEventIdentifiers.count, (NSUInteger)1, @"Should have one incomplete");
    XCTAssertEqualObjects(store.incompleteEventIdentifiers[0], @"TestID", @"Wrong id");
    XCTAssertEqual(store.incompleteMandatoryEventIdentifiers.count, (NSUInteger)1, @"Should have no mandatory");
}

- (void)testDeregisteringIncompleteEvent
{
    [store prepareNewEventStore:NULL];
    [store registerIncompleteEventIdentifier:@"TestID" isMandatory:NO];
    [store deregisterIncompleteEventIdentifier:@"TestID"];
    XCTAssertEqual(store.incompleteEventIdentifiers.count, (NSUInteger)0, @"Should have one incomplete");
}

- (void)testDeregisteringIncompleteMandatoryEvent
{
    [store prepareNewEventStore:NULL];
    [store registerIncompleteEventIdentifier:@"TestID" isMandatory:YES];
    [store deregisterIncompleteEventIdentifier:@"TestID"];
    XCTAssertEqual(store.incompleteEventIdentifiers.count, (NSUInteger)0, @"Should have one incomplete");
}

- (void)testPersistenceOfIncompleteEvents
{
    [store prepareNewEventStore:NULL];
    [store registerIncompleteEventIdentifier:@"TestID" isMandatory:NO];
    
    CDEEventStore *newStore = [[CDEEventStore alloc] initWithEnsembleIdentifier:@"test" pathToEventDataRootDirectory:nil];
    XCTAssertEqual(newStore.incompleteEventIdentifiers.count, (NSUInteger)1, @"Should have one incomplete");
}

- (void)testManagedObjectContextNilBeforeInstall
{
    XCTAssertNil(store.managedObjectContext, @"Managed object context should be nil before an install");
}

- (void)testManagedObjectContextCreatedAfterInstall
{
    [store prepareNewEventStore:NULL];
    XCTAssertNotNil(store.managedObjectContext, @"Managed object context is nil");
}

- (void)testEventPersistentStorePath
{
    XCTAssertTrue([store prepareNewEventStore:NULL], @"Couldn't prepare store");
    NSPersistentStore *firstStore = store.managedObjectContext.persistentStoreCoordinator.persistentStores[0];
    NSURL *url = [firstStore URL];
    NSString *expectedPath = [[CDEEventStore defaultPathToEventDataRootDirectory] stringByAppendingPathComponent:@"test/events.sqlite"];
    XCTAssertEqualObjects(url.path, expectedPath, @"Wrong store path");
}

- (void)testEventStoreSavesStoreId
{
    [store prepareNewEventStore:NULL];
    CDEEventStore *secondStore = [[CDEEventStore alloc] initWithEnsembleIdentifier:@"test" pathToEventDataRootDirectory:nil];
    XCTAssertEqualObjects(store.persistentStoreIdentifier, secondStore.persistentStoreIdentifier, @"Store id not stored properly");
}

- (void)testSettingNilDataRoot
{
    XCTAssertNoThrow([[CDEEventStore alloc] initWithEnsembleIdentifier:@"blah" pathToEventDataRootDirectory:nil], @"Should not throw with root directory nil. Should just use default.");
}

- (void)testInstallingInNonStandardDataRoot
{
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ensemblestest"];
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
    [CDEEventStore setDefaultPathToEventDataRootDirectory:path];
    CDEEventStore *secondStore = [[CDEEventStore alloc] initWithEnsembleIdentifier:@"test" pathToEventDataRootDirectory:nil];
    XCTAssertTrue([secondStore prepareNewEventStore:NULL], @"Install failed in non standard location");
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
}

@end
