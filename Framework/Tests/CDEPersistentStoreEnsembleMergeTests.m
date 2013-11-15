//
//  CDEPersistentStoreEnsembleMergeTests.m
//  Ensembles Mac
//
//  Created by Drew McCormack on 15/11/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "CDEPersistentStoreEnsemble.h"
#import "CDELocalCloudFileSystem.h"
#import "CDEEventStore.h"

@interface CDEPersistentStoreEnsemble (CDETestMethods)

- (CDEEventStore *)eventStore;

@end

@interface CDEPersistentStoreEnsembleMergeTests : XCTestCase <CDEPersistentStoreEnsembleDelegate>

@end

@implementation CDEPersistentStoreEnsembleMergeTests {
    CDEPersistentStoreEnsemble *ensemble1, *ensemble2;
    NSManagedObjectContext *managedObjectContext1, *managedObjectContext2;
    NSString *rootTestDir;
    NSString *cloudDir;
    NSDictionary *willSaveInfo, *didSaveInfo;
    BOOL didSaveRepairMethodWasCalled, willSaveRepairMethodWasCalled, failedSaveRepairMethodWasCalled;
    BOOL finishedAsync;
}

- (void)setUp
{
    [super setUp];
    
    rootTestDir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"CDEPersistentStoreEnsembleMergeTests"];
    [[NSFileManager defaultManager] removeItemAtPath:rootTestDir error:NULL];
    [[NSFileManager defaultManager] createDirectoryAtPath:rootTestDir withIntermediateDirectories:YES attributes:nil error:NULL];
    
    NSURL *testModelURL = [[NSBundle bundleForClass:self.class] URLForResource:@"CDEStoreModificationEventTestsModel" withExtension:@"momd"];
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] initWithContentsOfURL:testModelURL];

    cloudDir = [rootTestDir stringByAppendingPathComponent:@"cloud"];
    [[NSFileManager defaultManager] createDirectoryAtPath:cloudDir withIntermediateDirectories:YES attributes:nil error:NULL];
    
    // First ensemble object
    CDELocalCloudFileSystem *cloudFileSystem = (id)[[CDELocalCloudFileSystem alloc] initWithRootDirectory:cloudDir];
    
    NSString *storePath = [rootTestDir stringByAppendingPathComponent:@"first.sqlite"];
    NSURL *storeURL = [NSURL fileURLWithPath:storePath];
    [[NSFileManager defaultManager] removeItemAtURL:storeURL error:NULL];
    
    NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
    [coordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:nil error:NULL];
    managedObjectContext1 = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSConfinementConcurrencyType];
    managedObjectContext1.persistentStoreCoordinator = coordinator;
    
    [CDEEventStore setDefaultPathToEventDataRootDirectory:[rootTestDir stringByAppendingPathComponent:@"eventStore1"]];

    ensemble1 = [[CDEPersistentStoreEnsemble alloc] initWithEnsembleIdentifier:@"testensemble" persistentStorePath:storePath managedObjectModelURL:testModelURL cloudFileSystem:(id)cloudFileSystem];
    
    [ensemble1 leechPersistentStoreWithCompletion:^(NSError *error) {
        [self finishAsync];
    }];
    [self waitForAsync];
    
    // Second ensemble object
    cloudFileSystem = (id)[[CDELocalCloudFileSystem alloc] initWithRootDirectory:cloudDir];
    
    storePath = [rootTestDir stringByAppendingPathComponent:@"second.sqlite"];
    storeURL = [NSURL fileURLWithPath:storePath];
    [[NSFileManager defaultManager] removeItemAtURL:storeURL error:NULL];
    
    coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
    [coordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:nil error:NULL];
    managedObjectContext2 = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSConfinementConcurrencyType];
    managedObjectContext2.persistentStoreCoordinator = coordinator;
    
    [CDEEventStore setDefaultPathToEventDataRootDirectory:[rootTestDir stringByAppendingPathComponent:@"eventStore2"]];

    ensemble2 = [[CDEPersistentStoreEnsemble alloc] initWithEnsembleIdentifier:@"testensemble" persistentStorePath:storePath managedObjectModelURL:testModelURL cloudFileSystem:(id)cloudFileSystem];
    
    [ensemble2 leechPersistentStoreWithCompletion:^(NSError *error) {
        [self finishAsync];
    }];
    [self waitForAsync];
}

- (void)tearDown
{
    [[NSFileManager defaultManager] removeItemAtPath:rootTestDir error:NULL];
    [super tearDown];
}

- (void)waitForAsync
{
    finishedAsync = NO;
    while (!finishedAsync) CFRunLoopRun();
}

- (void)finishAsync
{
    finishedAsync = YES;
    CFRunLoopStop(CFRunLoopGetCurrent());
}

- (void)testWillSaveMergeRepairMethodGetsInvoked
{
    [NSEntityDescription insertNewObjectForEntityForName:@"Parent" inManagedObjectContext:managedObjectContext2];
    [managedObjectContext2 save:NULL];
    [ensemble2 mergeWithCompletion:^(NSError *error) {
        XCTAssertNil(error, @"Merge failed");
        [self finishAsync];
    }];
    [self waitForAsync];
    
    ensemble1.delegate = self;
    [ensemble1 mergeWithCompletion:^(NSError *error) {
        XCTAssertNil(error, @"Merge failed");
        [self performSelector:@selector(checkForWillSaveRepair) withObject:nil afterDelay:0.05];
    }];
    [self waitForAsync];
}

- (void)testDidSaveMergeRepairMethodGetsInvoked
{
    [NSEntityDescription insertNewObjectForEntityForName:@"Parent" inManagedObjectContext:managedObjectContext2];
    [managedObjectContext2 save:NULL];
    [ensemble2 mergeWithCompletion:^(NSError *error) {
        XCTAssertNil(error, @"Merge failed");
        [self finishAsync];
    }];
    [self waitForAsync];
    
    ensemble1.delegate = self;
    [ensemble1 mergeWithCompletion:^(NSError *error) {
        XCTAssertNil(error, @"Merge failed");
        [self performSelector:@selector(checkForDidSaveRepair) withObject:nil afterDelay:0.05];
    }];
    [self waitForAsync];
}

- (void)checkForWillSaveRepair
{
    XCTAssert(willSaveRepairMethodWasCalled, @"No will-save method invocation occurred");
    XCTAssert([willSaveInfo[NSInsertedObjectsKey] count] == 1, @"Wrong count for inserted object ids");
    XCTAssert([willSaveInfo[NSUpdatedObjectsKey] count] == 0, @"Wrong count for updated object ids");
    XCTAssert([willSaveInfo[NSDeletedObjectsKey] count] == 0, @"Wrong count for deleted object ids");
    [self finishAsync];
}

- (void)checkForDidSaveRepair
{
    XCTAssert(didSaveRepairMethodWasCalled, @"No did-save method invocation occurred");
    [self finishAsync];
}

- (void)persistentStoreEnsemble:(CDEPersistentStoreEnsemble *)ensemble willSaveMergedChangesInManagedObjectContext:(NSManagedObjectContext *)context info:(NSDictionary *)infoDict
{
    willSaveInfo = infoDict;
    willSaveRepairMethodWasCalled = YES;
}

- (BOOL)persistentStoreEnsemble:(CDEPersistentStoreEnsemble *)ensemble didFailToSaveMergedChangesInManagedObjectContext:(NSManagedObjectContext *)context error:(NSError *)error
{
    failedSaveRepairMethodWasCalled = YES;
    return NO;
}

- (void)persistentStoreEnsemble:(CDEPersistentStoreEnsemble *)ensemble didSaveMergeChangesWithNotification:(NSNotification *)notification
{
    didSaveRepairMethodWasCalled = YES;
}

@end
