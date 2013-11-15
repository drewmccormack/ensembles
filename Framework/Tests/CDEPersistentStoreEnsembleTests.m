//
//  CDEPersistentStoreEnsembleTests.m
//  Ensembles Mac
//
//  Created by Drew McCormack on 25/09/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "CDEEventStore.h"
#import "CDEPersistentStoreEnsemble.h"
#import "CDELocalCloudFileSystem.h"

@interface CDEMockLocalFileSystem : CDELocalCloudFileSystem

@property (nonatomic, readwrite) id <NSObject, NSCoding, NSCopying> identityToken;

@end

@implementation CDEMockLocalFileSystem {
    id <NSObject, NSCopying, NSCoding> _identityToken;
}

- (id <NSObject, NSCopying, NSCoding>)identityToken
{
    return _identityToken;
}

- (void)setIdentityToken:(id <NSObject, NSCopying, NSCoding>)newToken
{
    _identityToken = newToken;
}

@end


@interface CDEPersistentStoreEnsemble (CDETestMethods)

- (CDEEventStore *)eventStore;

@end


@interface CDEPersistentStoreEnsembleTests : XCTestCase <CDEPersistentStoreEnsembleDelegate>

@end

@implementation CDEPersistentStoreEnsembleTests {
    CDEPersistentStoreEnsemble *ensemble;
    CDEMockLocalFileSystem *cloudFileSystem;
    NSString *cloudDir;
    NSURL *storeURL;
    BOOL deleechOccurred;
    BOOL finishedAsync;
}

- (void)setUp
{
    [super setUp];
    
    cloudDir = [NSTemporaryDirectory() stringByAppendingString:@"CDEPersistentStoreEnsembleTests"];
    [[NSFileManager defaultManager] removeItemAtPath:cloudDir error:NULL];
    [[NSFileManager defaultManager] createDirectoryAtPath:cloudDir withIntermediateDirectories:YES attributes:nil error:NULL];

    cloudFileSystem = (id)[[CDEMockLocalFileSystem alloc] initWithRootDirectory:cloudDir];
    cloudFileSystem.identityToken = @"first";
    
    NSString *storePath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"teststore.sqlite"];
    storeURL = [NSURL fileURLWithPath:storePath];
    [[NSFileManager defaultManager] removeItemAtURL:storeURL error:NULL];
    
    NSURL *testModelURL = [[NSBundle bundleForClass:self.class] URLForResource:@"CDEStoreModificationEventTestsModel" withExtension:@"momd"];
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] initWithContentsOfURL:testModelURL];
    NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
    [coordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:nil error:NULL];
    NSManagedObjectContext *context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSConfinementConcurrencyType];
    context.persistentStoreCoordinator = coordinator;
    [NSEntityDescription insertNewObjectForEntityForName:@"Parent" inManagedObjectContext:context];
    [context save:NULL];
    
    ensemble = [[CDEPersistentStoreEnsemble alloc] initWithEnsembleIdentifier:@"testensemble" persistentStorePath:storePath managedObjectModelURL:testModelURL cloudFileSystem:(id)cloudFileSystem];
    ensemble.delegate = self;
    
    deleechOccurred = NO;
}

- (void)tearDown
{
    NSString *eventStoreRoot = [ensemble.eventStore pathToEventDataRootDirectory];
    [[NSFileManager defaultManager] removeItemAtPath:eventStoreRoot error:NULL];
    [[NSFileManager defaultManager] removeItemAtPath:cloudDir error:NULL];
    [[NSFileManager defaultManager] removeItemAtURL:storeURL error:NULL];
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

- (void)testInitialization
{
    XCTAssertNotNil(ensemble, @"Ensemble should not be nil");
}

- (void)testLeech
{
    XCTAssertFalse(ensemble.isLeeched, @"Should not be leeched");
    [ensemble leechPersistentStoreWithCompletion:^(NSError *error) {
        XCTAssertNil(error, @"Error occurred while leeching");
        XCTAssertTrue(ensemble.isLeeched, @"Should be leeched");
        [self finishAsync];
    }];
    [self waitForAsync];
}

- (void)testDeleech
{
    [ensemble leechPersistentStoreWithCompletion:^(NSError *error) {
        XCTAssertNil(error, @"Error occurred while leeching");
        [ensemble deleechPersistentStoreWithCompletion:^(NSError *error) {
            XCTAssertNil(error, @"Error occurred while deleeching");
            [self finishAsync];
        }];
    }];
    [self waitForAsync];
}

- (void)testDeleechWithoutLeech
{
    [ensemble deleechPersistentStoreWithCompletion:^(NSError *error) {
        XCTAssertNotNil(error, @"Error should occur while deleeching");
        [self finishAsync];
    }];
    [self waitForAsync];
}

- (void)testChangingIdentityTokenCausesDeleech
{
    XCTAssertFalse(deleechOccurred, @"Should be NO");
    [ensemble leechPersistentStoreWithCompletion:^(NSError *error) {
        XCTAssertNil(error, @"Error occurred while leeching");
        cloudFileSystem.identityToken = @"second";
        [self performSelector:@selector(checkForDeleech) withObject:nil afterDelay:0.05];
    }];
    [self waitForAsync];
}

- (void)testRemovingRegistrationInfoCausesDeleech
{
    XCTAssertFalse(deleechOccurred, @"Should be NO");
    [ensemble leechPersistentStoreWithCompletion:^(NSError *error) {
        XCTAssertNil(error, @"Error occurred while leeching");
        
        NSString *path = [cloudDir stringByAppendingPathComponent:@"testensemble/stores"];
        path = [path stringByAppendingPathComponent:ensemble.eventStore.persistentStoreIdentifier];
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        
        [ensemble mergeWithCompletion:^(NSError *error) {
            XCTAssertNotNil(error, @"Merge should fail due to missing store info");
            [self checkForDeleech];
        }];
    }];
    [self waitForAsync];
}

- (void)testInitWithIncompleteMandatoryEventsCausesDeleech
{
    [ensemble leechPersistentStoreWithCompletion:^(NSError *error) {
        XCTAssertNil(error, @"Error occurred while leeching");
        [[ensemble eventStore] registerIncompleteEventIdentifier:@"123" isMandatory:YES];
        [self finishAsync];
    }];
    [self waitForAsync];
    
    [ensemble processPendingChangesWithCompletion:^(NSError *error) {
        [self finishAsync];
    }];
    [self waitForAsync];
    
    ensemble = [[CDEPersistentStoreEnsemble alloc] initWithEnsembleIdentifier:@"testensemble" persistentStorePath:ensemble.storePath managedObjectModelURL:ensemble.managedObjectModelURL cloudFileSystem:(id)cloudFileSystem];
    ensemble.delegate = self;
    
    [self performSelector:@selector(checkForDeleech) withObject:nil afterDelay:0.05];
    [self waitForAsync];
}

- (void)testInitWithIncompleteNonMandatoryEventsDoesNotCauseDeleech
{
    [ensemble leechPersistentStoreWithCompletion:^(NSError *error) {
        XCTAssertNil(error, @"Error occurred while leeching");
        [[ensemble eventStore] registerIncompleteEventIdentifier:@"123" isMandatory:NO];
        [self finishAsync];
    }];
    [self waitForAsync];
    
    ensemble = [[CDEPersistentStoreEnsemble alloc] initWithEnsembleIdentifier:@"testensemble" persistentStorePath:ensemble.storePath managedObjectModelURL:ensemble.managedObjectModelURL cloudFileSystem:(id)cloudFileSystem];
    ensemble.delegate = self;
    
    [self performSelector:@selector(checkForLeech) withObject:nil afterDelay:0.05];
    [self waitForAsync];
}

- (void)checkForLeech
{
    XCTAssert(!deleechOccurred, @"A deleech occurred when it shouldn't have");
    [self finishAsync];
}

- (void)checkForDeleech
{
    XCTAssert(deleechOccurred, @"No deleech occurred");
    [self finishAsync];
}

- (void)persistentStoreEnsemble:(CDEPersistentStoreEnsemble *)ensemble didDeleechWithError:(NSError *)error
{
    deleechOccurred = YES;
}

@end
