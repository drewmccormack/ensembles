//
//  CDEPersistentStoreEnsembleMergeTests.m
//  Ensembles
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
    NSSet *inserted, *updated, *deleted;
    NSDictionary *didSaveInfo;
    NSInteger failedSaveErrorCode;
    BOOL didSaveRepairMethodWasCalled, willSaveRepairMethodWasCalled, failedSaveRepairMethodWasCalled;
    BOOL finishedAsync;
    BOOL testingDidFail;
}

- (void)setUp
{
    [super setUp];
    
    didSaveRepairMethodWasCalled = NO;
    willSaveRepairMethodWasCalled = NO;
    failedSaveRepairMethodWasCalled = NO;
    
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

    ensemble1 = [[CDEPersistentStoreEnsemble alloc] initWithEnsembleIdentifier:@"testensemble" persistentStoreURL:storeURL managedObjectModelURL:testModelURL cloudFileSystem:(id)cloudFileSystem];
    
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

    ensemble2 = [[CDEPersistentStoreEnsemble alloc] initWithEnsembleIdentifier:@"testensemble" persistentStoreURL:storeURL managedObjectModelURL:testModelURL cloudFileSystem:(id)cloudFileSystem];
    
    [ensemble2 leechPersistentStoreWithCompletion:^(NSError *error) {
        [self finishAsync];
    }];
    [self waitForAsync];
    
    testingDidFail = NO;
}

- (void)tearDown
{
    didSaveInfo = nil;
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

- (void)testWillSaveMergeRepairMethod
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

- (void)testDidSaveMergeRepairMethod
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

- (void)testDidFailMergeRepairMethod
{
    id parentInContext2 = [NSEntityDescription insertNewObjectForEntityForName:@"Parent" inManagedObjectContext:managedObjectContext2];
    [managedObjectContext2 save:NULL];
    [ensemble2 mergeWithCompletion:^(NSError *error) {
        XCTAssertNil(error, @"Merge failed");
        [self finishAsync];
    }];
    [self waitForAsync];
    
    [ensemble1 mergeWithCompletion:^(NSError *error) {
        [self finishAsync];
    }];
    [self waitForAsync];
    
    // Add conflicting changes, adding up to too many children for the relationship
    id child3 = [NSEntityDescription insertNewObjectForEntityForName:@"Child" inManagedObjectContext:managedObjectContext2];
    [parentInContext2 setValue:[NSSet setWithObjects:child3, nil] forKey:@"maxedChildren"];
    [managedObjectContext2 save:NULL];
    
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Parent"];
    id parentInContext1 = [[managedObjectContext1 executeFetchRequest:fetch error:NULL] lastObject];
    id child1 = [NSEntityDescription insertNewObjectForEntityForName:@"Child" inManagedObjectContext:managedObjectContext1];
    id child2 = [NSEntityDescription insertNewObjectForEntityForName:@"Child" inManagedObjectContext:managedObjectContext1];
    [parentInContext1 setValue:[NSSet setWithObjects:child1, child2, nil] forKey:@"maxedChildren"];
    [managedObjectContext1 save:NULL];
    
    // Merge
    [ensemble2 mergeWithCompletion:^(NSError *error) {
        [self finishAsync];
    }];
    [self waitForAsync];
    
    testingDidFail = YES;
    ensemble1.delegate = self;
    [ensemble1 mergeWithCompletion:^(NSError *error) {
        [self performSelector:@selector(checkForDidFailRepair) withObject:nil afterDelay:0.05];
    }];
    [self waitForAsync];
}

- (void)checkForWillSaveRepair
{
    XCTAssert(willSaveRepairMethodWasCalled, @"No will-save method invocation occurred");
    XCTAssert(inserted.count == 1, @"Wrong count for inserted object ids");
    XCTAssert(updated.count == 0, @"Wrong count for updated object ids");
    XCTAssert(deleted.count == 0, @"Wrong count for deleted object ids");
    [self finishAsync];
}

- (void)checkForDidSaveRepair
{
    XCTAssert(didSaveRepairMethodWasCalled, @"No did-save method invocation occurred");
    XCTAssert(inserted.count == 1, @"Wrong count for inserted objects");
    XCTAssert(updated.count == 0, @"Wrong count for updated objects");
    [self finishAsync];
}

- (void)checkForDidFailRepair
{
    XCTAssert(failedSaveRepairMethodWasCalled, @"No did-fail method invocation occurred");
    XCTAssertEqual(failedSaveErrorCode, (NSInteger)NSValidationRelationshipExceedsMaximumCountError, @"Wrong error code");
    [self finishAsync];
}

- (BOOL)persistentStoreEnsemble:(CDEPersistentStoreEnsemble *)ensemble shouldSaveMergedChangesInManagedObjectContext:(NSManagedObjectContext *)savingContext reparationManagedObjectContext:(NSManagedObjectContext *)reparationContext
{
    [savingContext performBlockAndWait:^{
        inserted = savingContext.insertedObjects;
        updated = savingContext.updatedObjects;
        deleted = savingContext.deletedObjects;
    }];
    willSaveRepairMethodWasCalled = YES;
    return YES;
}

- (BOOL)persistentStoreEnsemble:(CDEPersistentStoreEnsemble *)ensemble didFailToSaveMergedChangesInManagedObjectContext:(NSManagedObjectContext *)savingContext error:(NSError *)error reparationManagedObjectContext:(NSManagedObjectContext *)reparationContext
{
    failedSaveRepairMethodWasCalled = YES;
    failedSaveErrorCode = error.code;
    return NO;
}

- (void)persistentStoreEnsemble:(CDEPersistentStoreEnsemble *)ensemble didSaveMergeChangesWithNotification:(NSNotification *)notification
{
    didSaveInfo = notification.userInfo;
    didSaveRepairMethodWasCalled = YES;
}

@end
