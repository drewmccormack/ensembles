//
//  CDECloudManagerTests.m
//  Ensembles
//
//  Created by Drew McCormack on 11/09/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "CDEEventStoreTestCase.h"
#import "CDEStoreModificationEvent.h"
#import "CDECloudManager.h"
#import "CDECloudFileSystem.h"
#import "CDECloudFile.h"
#import "CDEMockCloudFileSystem.h"

@interface CDECloudManager (TestMethods)

@property (nonatomic, strong, readonly) NSString *localUploadDirectory;
@property (nonatomic, strong, readonly) NSString *remoteEventsDirectory;
@property (nonatomic, strong, readwrite) NSSet *snapshotEventFilenames;

- (NSArray *)sortFilenamesByGlobalCount:(NSArray *)files;

- (void)migrateNewEventsWithAllowedTypes:(NSArray *)types fromTransitCacheWithCompletion:(CDECompletionBlock)completion;

- (void)transferFilesInTransitCacheToRemoteDirectory:(NSString *)remoteDirectory completion:(CDECompletionBlock)completion;
- (void)migrateNewLocalEventsToTransitCacheWithRemoteDirectory:(NSString *)remoteDirectory existingRemoteFilenames:(NSArray *)filenames allowedTypes:(NSArray *)types completion:(CDECompletionBlock)completion;

@end

@interface CDECloudManagerTests : CDEEventStoreTestCase

@end

@implementation CDECloudManagerTests {
    CDECloudManager *cloudManager;
    id <CDECloudFileSystem> cloudFileSystem;
    NSFileManager *fileManager;
    NSString *rootDir, *remoteEnsemblesDir;
}

- (void)setUp
{
    [super setUp];
    
    fileManager = [[NSFileManager alloc] init];
    
    rootDir = [NSTemporaryDirectory() stringByAppendingString:@"CDECloudManagerTestsData"];
    self.eventStore.pathToEventDataRootDirectory = rootDir;
    
    remoteEnsemblesDir = @"/ensemble1";
    
    [fileManager removeItemAtPath:rootDir error:NULL];
    [fileManager createDirectoryAtPath:rootDir withIntermediateDirectories:YES attributes:nil error:NULL];
    
    cloudFileSystem = [[CDEMockCloudFileSystem alloc] init];
    cloudManager = [[CDECloudManager alloc] initWithEventStore:(id)self.eventStore cloudFileSystem:cloudFileSystem];
}

- (void)tearDown
{
    [fileManager removeItemAtPath:rootDir error:NULL];
    [super tearDown];
}

- (void)waitForAsyncOperation
{
    CFRunLoopRun();
}

- (void)stopWaiting
{
    CFRunLoopStop(CFRunLoopGetCurrent());
}

- (void)testCreateRemoteEventDirectoryFirstTime
{
    [cloudManager createRemoteDirectoryStructureWithCompletion:^(NSError *error) {
        XCTAssertNil(error, @"Error creating directories");
        NSString *eventsDir = [remoteEnsemblesDir stringByAppendingPathComponent:@"events"];
        [cloudFileSystem fileExistsAtPath:eventsDir completion:^(BOOL exists, BOOL isDirectory, NSError *error) {
            XCTAssert(isDirectory, @"Events was not directory");
            XCTAssert(exists, @"No events dir created");
            [self stopWaiting];
        }];
    }];
    [self waitForAsyncOperation];
}

- (void)testCreateRemoteEventDirectoryThatAlreadyExist
{
    [cloudManager createRemoteDirectoryStructureWithCompletion:^(NSError *error) {
        XCTAssertNil(error, @"Error creating directories");

        [cloudManager createRemoteDirectoryStructureWithCompletion:^(NSError *error) {
            XCTAssertNil(error, @"Error creating directories");
            NSString *eventsDir = [remoteEnsemblesDir stringByAppendingPathComponent:@"events"];
            [cloudFileSystem fileExistsAtPath:eventsDir completion:^(BOOL exists, BOOL isDirectory, NSError *error) {
                XCTAssert(isDirectory, @"Events was not directory");
                XCTAssert(exists, @"No events dir created");
                [self stopWaiting];
            }];
        }];
    }];
    [self waitForAsyncOperation];
}

- (void)testCreateRemoteStoresDirectory
{
    [cloudManager createRemoteDirectoryStructureWithCompletion:^(NSError *error) {
        XCTAssertNil(error, @"Error creating directories");
        NSString *eventsDir = [remoteEnsemblesDir stringByAppendingPathComponent:@"stores"];
        [cloudFileSystem fileExistsAtPath:eventsDir completion:^(BOOL exists, BOOL isDirectory, NSError *error) {
            XCTAssert(isDirectory, @"Stores was not directory");
            XCTAssert(exists, @"No stores dir created");
            [self stopWaiting];
        }];
    }];
    [self waitForAsyncOperation];
}

- (void)testCreateRemoteBaselinesDirectory
{
    [cloudManager createRemoteDirectoryStructureWithCompletion:^(NSError *error) {
        XCTAssertNil(error, @"Error creating directories");
        NSString *eventsDir = [remoteEnsemblesDir stringByAppendingPathComponent:@"baselines"];
        [cloudFileSystem fileExistsAtPath:eventsDir completion:^(BOOL exists, BOOL isDirectory, NSError *error) {
            XCTAssert(isDirectory, @"Stores was not directory");
            XCTAssert(exists, @"No stores dir created");
            [self stopWaiting];
        }];
    }];
    [self waitForAsyncOperation];
}

- (void)testCreateRemoteDataDirectory
{
    [cloudManager createRemoteDirectoryStructureWithCompletion:^(NSError *error) {
        XCTAssertNil(error, @"Error creating directories");
        NSString *eventsDir = [remoteEnsemblesDir stringByAppendingPathComponent:@"data"];
        [cloudFileSystem fileExistsAtPath:eventsDir completion:^(BOOL exists, BOOL isDirectory, NSError *error) {
            XCTAssert(isDirectory, @"Stores was not directory");
            XCTAssert(exists, @"No stores dir created");
            [self stopWaiting];
        }];
    }];
    [self waitForAsyncOperation];
}

- (void)testImportFromCloudWithNoData
{
    [cloudManager snapshotRemoteFilesWithCompletion:^(NSError *error) {
        [cloudManager importNewRemoteNonBaselineEventsWithCompletion:^(NSError *error) {
            XCTAssertNil(error, @"Error when trying to import with no data");
            [self stopWaiting];
        }];
    }];
    [self waitForAsyncOperation];
}

- (void)testImportFromCloudWithInvalidData
{
    NSString *file = [NSTemporaryDirectory() stringByAppendingPathComponent:@"testfile"];
    [[@"Test data" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:file atomically:YES];
    
    [cloudManager createRemoteDirectoryStructureWithCompletion:^(NSError *error) {
        [cloudFileSystem uploadLocalFile:file toPath:@"/ensemble1/events/0_store1_0" completion:^(NSError *error) {
            [cloudManager snapshotRemoteFilesWithCompletion:^(NSError *error) {
                XCTAssertNil(error, @"Error uploading file");
                [cloudManager importNewRemoteNonBaselineEventsWithCompletion:^(NSError *error) {
                    XCTAssertNotNil(error, @"No error when should be one");
                    [self stopWaiting];
                }];
            }];
        }];
    }];
    [self waitForAsyncOperation];
}

- (void)testExportingPopulatesCloud
{
    [self.eventStore.managedObjectContext performBlockAndWait:^{
        [self addModEventForStore:self.eventStore.persistentStoreIdentifier revision:0 globalCount:0 timestamp:0.0];
        [self.eventStore.managedObjectContext save:NULL];
    }];
    
    [cloudManager createRemoteDirectoryStructureWithCompletion:^(NSError *error) {
        [cloudManager snapshotRemoteFilesWithCompletion:^(NSError *error) {
            [cloudManager exportNewLocalNonBaselineEventsWithCompletion:^(NSError *error) {
                NSString *path = [remoteEnsemblesDir stringByAppendingPathComponent:@"events/0_store1_0.cdeevent"];
                [cloudFileSystem fileExistsAtPath:path completion:^(BOOL exists, BOOL isDirectory, NSError *error) {
                    XCTAssert(exists, @"File doesn't exist in cloud");
                    XCTAssertNil(error, @"Should not be an error");
                    XCTAssertFalse(isDirectory, @"Should not be a directory");
                    [self stopWaiting];
                }];
            }];
        }];
    }];
    [self waitForAsyncOperation];
}

- (void)testExportingPopulatesTransitCache
{
    [self.eventStore.managedObjectContext performBlockAndWait:^{
        [self addModEventForStore:self.eventStore.persistentStoreIdentifier revision:1 globalCount:2 timestamp:0.0];
        [self addModEventForStore:self.eventStore.persistentStoreIdentifier revision:4 globalCount:7 timestamp:0.1];
        [self.eventStore.managedObjectContext save:NULL];
    }];
    
    [cloudManager createRemoteDirectoryStructureWithCompletion:^(NSError *error) {
        [cloudManager snapshotRemoteFilesWithCompletion:^(NSError *error) {
            NSArray *types = @[@(CDEStoreModificationEventTypeMerge), @(CDEStoreModificationEventTypeSave)];
            [cloudManager migrateNewLocalEventsToTransitCacheWithRemoteDirectory:cloudManager.remoteEventsDirectory existingRemoteFilenames:cloudManager.snapshotEventFilenames.allObjects allowedTypes:types completion:^(NSError *error) {
                BOOL isDir;
                NSString *path = [rootDir stringByAppendingPathComponent:@"transitcache/ensemble1/upload/2_store1_1.cdeevent"];
                XCTAssertTrue([fileManager fileExistsAtPath:path isDirectory:&isDir], @"Transit file missing");
                
                NSString *eventsDir = [path stringByDeletingLastPathComponent];
                XCTAssertEqual([[fileManager contentsOfDirectoryAtPath:eventsDir error:NULL] count], (NSUInteger)2, @"Wrong number of files exported");
                
                [cloudManager transferFilesInTransitCacheToRemoteDirectory:cloudManager.remoteEventsDirectory completion:^(NSError *error) {
                    XCTAssertNil(error, @"Error transferring to cloud");
                    
                    NSString *remotePath = [remoteEnsemblesDir stringByAppendingPathComponent:@"events/2_store1_1.cdeevent"];
                    [cloudFileSystem fileExistsAtPath:remotePath completion:^(BOOL exists, BOOL isDirectory, NSError *error) {
                        XCTAssert(exists, @"File doesn't exist in cloud");
                        XCTAssertNil(error, @"Should not be an error");
                        XCTAssertFalse(isDirectory, @"Should not be a directory");
                        [self stopWaiting];
                    }];
                }];
            }];
        }];
    }];
    [self waitForAsyncOperation];
}

- (void)testExportingCleansUpTransitCache
{
    [self.eventStore.managedObjectContext performBlockAndWait:^{
        [self addModEventForStore:self.eventStore.persistentStoreIdentifier revision:1 globalCount:2 timestamp:0.0];
        [self addModEventForStore:self.eventStore.persistentStoreIdentifier revision:4 globalCount:7 timestamp:0.1];
        [self.eventStore.managedObjectContext save:NULL];
    }];
    
    [cloudManager createRemoteDirectoryStructureWithCompletion:^(NSError *error) {
        [cloudManager snapshotRemoteFilesWithCompletion:^(NSError *error) {
            [cloudManager exportNewLocalNonBaselineEventsWithCompletion:^(NSError *error) {
                NSString *eventsDir = [rootDir stringByAppendingPathComponent:@"transitcache/ensemble1/upload"];
                XCTAssertEqual([[fileManager contentsOfDirectoryAtPath:eventsDir error:NULL] count], (NSUInteger)0, @"Should be no files after a successful export");
                [self stopWaiting];
            }];
        }];
    }];
    [self waitForAsyncOperation];
}

- (void)testMigrateFromTransitCachePopulatesEventStore
{
    __block CDEStoreModificationEvent *event;
    NSString *store = self.eventStore.persistentStoreIdentifier;
    NSManagedObjectContext *moc = self.eventStore.managedObjectContext;
    [moc performBlockAndWait:^{
        event = [self addModEventForStore:store revision:1 globalCount:2 timestamp:0.0];
        [self.eventStore.managedObjectContext save:NULL];
    }];
    
    [cloudManager createRemoteDirectoryStructureWithCompletion:^(NSError *error) {
        NSArray *types = @[@(CDEStoreModificationEventTypeMerge), @(CDEStoreModificationEventTypeSave)];
        [cloudManager snapshotRemoteFilesWithCompletion:^(NSError *error) {
            [cloudManager migrateNewLocalEventsToTransitCacheWithRemoteDirectory:cloudManager.remoteEventsDirectory existingRemoteFilenames:cloudManager.snapshotEventFilenames.allObjects allowedTypes:types completion:^(NSError *error) {
                // Move cached file from the upload to the download folder
                NSString *uploadEventsDir = [rootDir stringByAppendingPathComponent:@"transitcache/ensemble1/upload"];
                NSString *downloadEventsDir = [rootDir stringByAppendingPathComponent:@"transitcache/ensemble1/download"];
                NSString *uploadFile = [uploadEventsDir stringByAppendingPathComponent:@"2_store1_1.cdeevent"];
                NSString *downloadFile = [downloadEventsDir stringByAppendingPathComponent:@"2_store1_1.cdeevent"];
                XCTAssertTrue([fileManager moveItemAtPath:uploadFile toPath:downloadFile error:NULL], @"Failed to move file");
                
                // Clear out the event store
                [self.eventStore.managedObjectContext performBlockAndWait:^{
                    [moc deleteObject:event];
                    [moc save:NULL];
                }];
                
                [moc performBlockAndWait:^{
                    CDEStoreModificationEvent *fetchedEvent = [CDEStoreModificationEvent fetchNonBaselineEventForPersistentStoreIdentifier:store revisionNumber:1 inManagedObjectContext:moc];
                    XCTAssertNil(fetchedEvent, @"Event should not be present after deletion");
                }];
                
                NSArray *types = @[@(CDEStoreModificationEventTypeSave), @(CDEStoreModificationEventTypeMerge)];
                [cloudManager migrateNewEventsWithAllowedTypes:types fromTransitCacheWithCompletion:^(NSError *error) {
                    XCTAssertNil(error, @"Error importing");
                    
                    [moc performBlockAndWait:^{
                        CDEStoreModificationEvent *fetchedEvent = [CDEStoreModificationEvent fetchNonBaselineEventForPersistentStoreIdentifier:store revisionNumber:1 inManagedObjectContext:moc];
                        XCTAssertNotNil(fetchedEvent, @"Event was not imported");
                    }];
                    
                    XCTAssertEqual([[fileManager contentsOfDirectoryAtPath:downloadEventsDir error:NULL] count], (NSUInteger)0, @"Should be no files after a successful import");
                    
                    [self stopWaiting];
                }];
            }];
        }];
    }];
    
    [self waitForAsyncOperation];
}

- (void)testSortingOfFilesByGlobalCount
{
    NSArray *files = @[@"10_store1_0", @"9_store1_3", @"8_aaa_8"];
    NSArray *sortedFiles = [cloudManager sortFilenamesByGlobalCount:files];
    XCTAssertEqualObjects(sortedFiles[0], files[2], @"Wrong 1st");
    XCTAssertEqualObjects(sortedFiles[1], files[1], @"Wrong 2nd");
    XCTAssertEqualObjects(sortedFiles[2], files[0], @"Wrong 3rd");
}

@end
