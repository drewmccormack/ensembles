//
//  CDESyncTest.h
//  Ensembles
//
//  Created by Drew McCormack on 19/09/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import <XCTest/XCTest.h>

@class CDEPersistentStoreEnsemble;
@protocol CDECloudFileSystem;

@interface CDESyncTest : XCTestCase {
    @protected
    NSManagedObjectContext *context1, *context2;
    NSManagedObjectModel *model;
    NSString *testStoreFile1, *testStoreFile2;
    NSString *testRootDirectory;
    CDEPersistentStoreEnsemble *ensemble1, *ensemble2;
    id <CDECloudFileSystem> cloudFileSystem1, cloudFileSystem2;
    NSString *cloudRootDir;
    NSURL *testStoreURL1, *testStoreURL2;
    NSString *eventDataRoot1, *eventDataRoot2;
}

- (void)waitForAsync;
- (void)completeAsync;

- (void)leechStores;

- (NSError *)mergeEnsemble:(CDEPersistentStoreEnsemble *)ensemble;
- (NSError *)syncChanges;

@end
