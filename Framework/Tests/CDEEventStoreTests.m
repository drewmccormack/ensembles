//
//  CDEEventStoreTest.m
//  Ensembles
//
//  Created by Drew McCormack on 6/29/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "CDEEventStore.h"
#import "CDEObjectChange.h"
#import "CDEDataFile.h"

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

- (void)testImportingDataFile
{
    [store prepareNewEventStore:NULL];
    NSString *file = [NSTemporaryDirectory() stringByAppendingPathComponent:@"fileToImport"];
    [@"Hi there" writeToFile:file atomically:NO encoding:NSUTF8StringEncoding error:NULL];
    XCTAssertTrue([store importDataFile:file], @"Import failed");
    
    NSString *storePath = [store.pathToEventDataRootDirectory stringByAppendingPathComponent:@"test/newdata/fileToImport"];
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:storePath], @"No file found in data dir");
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:file], @"Original file should be gone");
    
    [store dataForFile:@"file"]; // Should cause it not to be new any more, ie, move directories
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:storePath], @"Newly created file should be gone");
    storePath = [store.pathToEventDataRootDirectory stringByAppendingPathComponent:@"test/data/fileToImport"];
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:storePath], @"Prereferenced file should be there");
}

- (void)testExportingDataFile
{
    NSString *exportPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"fileToExport"];
    [[NSFileManager defaultManager] removeItemAtPath:exportPath error:NULL];
    
    [store prepareNewEventStore:NULL];
    
    NSString *storePath = [store.pathToEventDataRootDirectory stringByAppendingPathComponent:@"test/data/fileToExport"];
    [@"Hi there" writeToFile:storePath atomically:NO encoding:NSUTF8StringEncoding error:NULL];
    
    
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:exportPath], @"File is already in temp dir");
    [store exportDataFile:@"fileToExport" toDirectory:NSTemporaryDirectory()];
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:exportPath], @"File is not exported");
}

- (void)testRemovingDataFile
{
    [store prepareNewEventStore:NULL];
    
    NSString *storePath = [store.pathToEventDataRootDirectory stringByAppendingPathComponent:@"test/data/fileToRemove"];
    [@"Hi there" writeToFile:storePath atomically:NO encoding:NSUTF8StringEncoding error:NULL];
    
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:storePath], @"No file found in data dir");
    [store removePreviouslyReferencedDataFile:@"fileToRemove"];
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:storePath], @"File is not gone");
}

- (void)testRetrievingDataFilenames
{
    [store prepareNewEventStore:NULL];

    NSString *storePath = [store.pathToEventDataRootDirectory stringByAppendingPathComponent:@"test/data/file1"];
    [@"Hi there" writeToFile:storePath atomically:NO encoding:NSUTF8StringEncoding error:NULL];
    storePath = [store.pathToEventDataRootDirectory stringByAppendingPathComponent:@"test/newdata/file2"];
    [@"Hi there" writeToFile:storePath atomically:NO encoding:NSUTF8StringEncoding error:NULL];
    
    NSSet *files = store.allDataFilenames;
    XCTAssertEqual(files.count, (NSUInteger)2, @"Wrong file count");
    XCTAssertTrue([files.anyObject hasPrefix:@"file"], @"Wrong file name prefix");
}

- (void)testRemovingOutdatedDataFiles
{
    [store prepareNewEventStore:NULL];
    [store.managedObjectContext performBlockAndWait:^{
        CDEObjectChange *change = [NSEntityDescription insertNewObjectForEntityForName:@"CDEObjectChange" inManagedObjectContext:store.managedObjectContext];
        CDEDataFile *dataFile1 = [NSEntityDescription insertNewObjectForEntityForName:@"CDEDataFile" inManagedObjectContext:store.managedObjectContext];
        dataFile1.objectChange = change;
        dataFile1.filename = @"123";
        
        CDEDataFile *dataFile2 = [NSEntityDescription insertNewObjectForEntityForName:@"CDEDataFile" inManagedObjectContext:store.managedObjectContext];
        dataFile2.filename = @"345";

        [store.managedObjectContext save:NULL];
    }];
    
    NSString *storePath1 = [store.pathToEventDataRootDirectory stringByAppendingPathComponent:@"test/data/123"];
    [@"Hi" writeToFile:storePath1 atomically:NO encoding:NSUTF8StringEncoding error:NULL];
    
    NSString *storePath2 = [store.pathToEventDataRootDirectory stringByAppendingPathComponent:@"test/data/234"];
    [@"Hi" writeToFile:storePath2 atomically:NO encoding:NSUTF8StringEncoding error:NULL];
    
    NSString *storePath3 = [store.pathToEventDataRootDirectory stringByAppendingPathComponent:@"test/data/345"];
    [@"Hi" writeToFile:storePath3 atomically:NO encoding:NSUTF8StringEncoding error:NULL];
    
    NSString *storePath4 = [store.pathToEventDataRootDirectory stringByAppendingPathComponent:@"test/newdata/789"];
    [@"Hi" writeToFile:storePath4 atomically:NO encoding:NSUTF8StringEncoding error:NULL];
    
    [store removeUnreferencedDataFiles];
    
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:storePath1], @"Should have file 123");
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:storePath2], @"Should not have file 234");
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:storePath3], @"Should not have file 345, because it is not attached to a CDEObjectChange");
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:storePath4], @"Should have file 789, because is newly imported");
}

@end
