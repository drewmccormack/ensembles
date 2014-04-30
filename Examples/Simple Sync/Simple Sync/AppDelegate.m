//
//  AppDelegate.m
//  Simple Sync
//
//  Created by Drew McCormack on 30/04/14.
//  Copyright (c) 2014 The Mental Faculty B.V. All rights reserved.
//

#import "AppDelegate.h"
#import "ViewController.h"
#import "NumberHolder.h"

@interface AppDelegate () <CDEPersistentStoreEnsembleDelegate>

@end

@implementation AppDelegate {
    CDEPersistentStoreEnsemble *ensemble;
    CDEICloudFileSystem *cloudFileSystem;
    NSManagedObjectContext *managedObjectContext;
}

#pragma mark Core Data Stack

- (void)setupCoreData
{
    NSError *error;
    NSURL *modelURL = [[NSBundle mainBundle] URLForResource:@"Model" withExtension:@"momd"];
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
    
    [[NSFileManager defaultManager] createDirectoryAtURL:self.storeDirectoryURL withIntermediateDirectories:YES attributes:nil error:NULL];
    
    NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
    NSDictionary *options = @{NSMigratePersistentStoresAutomaticallyOption: @YES, NSInferMappingModelAutomaticallyOption: @YES};
    [coordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:self.storeURL options:options error:&error];
    
    managedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    managedObjectContext.persistentStoreCoordinator = coordinator;
    managedObjectContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy;
}

- (NSURL *)storeDirectoryURL
{
    NSURL *directoryURL = [[NSFileManager defaultManager] URLForDirectory:NSApplicationSupportDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:NULL];
    directoryURL = [directoryURL URLByAppendingPathComponent:NSBundle.mainBundle.bundleIdentifier isDirectory:YES];
    return directoryURL;
}

- (NSURL *)storeURL
{
    NSURL *storeURL = [self.storeDirectoryURL URLByAppendingPathComponent:@"store.sqlite"];
    return storeURL;
}

#pragma mark Application Delegate Methods

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    // Core Data Stack
    [self setupCoreData];
    
    // Create holder object if necessary. Ensure it is fully saved before we leech.
    [NumberHolder numberHolderInManagedObjectContext:managedObjectContext];
    [managedObjectContext save:NULL];
    
    // Setup Ensemble
    NSURL *modelURL = [[NSBundle mainBundle] URLForResource:@"Model" withExtension:@"momd"];
    cloudFileSystem = [[CDEICloudFileSystem alloc] initWithUbiquityContainerIdentifier:nil];
    ensemble = [[CDEPersistentStoreEnsemble alloc] initWithEnsembleIdentifier:@"NumberStore" persistentStoreURL:self.storeURL managedObjectModelURL:modelURL cloudFileSystem:cloudFileSystem];
    ensemble.delegate = self;
    
    // Listen for local saves, and trigger merges
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(localSaveOccurred:) name:CDEMonitoredManagedObjectContextDidSaveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(cloudDataDidDownload:) name:CDEICloudFileSystemDidDownloadFilesNotification object:nil];
    
    [self syncWithCompletion:NULL];
    
    // Pass context to controller
    ViewController *controller = (id)self.window.rootViewController;
    controller.managedObjectContext = managedObjectContext;
    
    return YES;
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    UIBackgroundTaskIdentifier identifier = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:NULL];
    [managedObjectContext save:NULL];
    [self syncWithCompletion:^{
        [[UIApplication sharedApplication] endBackgroundTask:identifier];
    }];
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    [self syncWithCompletion:NULL];
}

- (void)localSaveOccurred:(NSNotification *)notif
{
    [self syncWithCompletion:NULL];
}

- (void)cloudDataDidDownload:(NSNotification *)notif
{
    [self syncWithCompletion:NULL];
}

- (void)syncWithCompletion:(void(^)(void))completion
{
    if (ensemble.isMerging) return;
    
    ViewController *viewController = (id)self.window.rootViewController;
    [viewController.activityIndicator startAnimating];
    if (!ensemble.isLeeched) {
        [ensemble leechPersistentStoreWithCompletion:^(NSError *error) {
            if (error) NSLog(@"Error in leech: %@", error);
            [viewController.activityIndicator stopAnimating];
            [viewController refresh];
            if (completion) completion();
        }];
    }
    else {
        [ensemble mergeWithCompletion:^(NSError *error) {
            if (error) NSLog(@"Error in merge: %@", error);
            [viewController.activityIndicator stopAnimating];
            [viewController refresh];
            if (completion) completion();
        }];
    }
}

#pragma mark Ensemble Delegate Methods

- (void)persistentStoreEnsemble:(CDEPersistentStoreEnsemble *)ensemble didSaveMergeChangesWithNotification:(NSNotification *)notification
{
    [managedObjectContext performBlockAndWait:^{
        [managedObjectContext mergeChangesFromContextDidSaveNotification:notification];
    }];
}

- (NSArray *)persistentStoreEnsemble:(CDEPersistentStoreEnsemble *)ensemble globalIdentifiersForManagedObjects:(NSArray *)objects
{
    return [objects valueForKeyPath:@"uniqueIdentifier"];
}

@end

