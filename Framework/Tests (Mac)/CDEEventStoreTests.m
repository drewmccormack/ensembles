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

- (void)testHasNopersistentStoreIdentifierBeforeInstall
{
    XCTAssertNil(store.persistentStoreIdentifier, @"Should not have store id");
}

- (void)testInstallingEventStore
{
    XCTAssertTrue([store prepareNewEventStore:NULL], @"Install failed");
}

- (void)testHaspersistentStoreIdentifierAfterInstall
{
    [store prepareNewEventStore:NULL];
    XCTAssertNotNil(store.persistentStoreIdentifier, @"Should have store id");
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
