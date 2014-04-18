//
//  AppDelegate.m
//  Magical Record
//
//  Created by Drew McCormack on 18/04/14.
//  Copyright (c) 2014 Drew McCormack. All rights reserved.
//

#import "AppDelegate.h"
#import "CoreDataEnsembles.h"
#import "CoreData+MagicalRecord.h"
#import "ViewController.h"

@interface AppDelegate () <CDEPersistentStoreEnsembleDelegate>

@end

@implementation AppDelegate {
    CDEPersistentStoreEnsemble *ensemble;
    CDEICloudFileSystem *cloudFileSystem;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    // Setup Core Data Stack
    [MagicalRecord setupCoreDataStack];
    
    // Setup Ensemble
    NSURL *url = [NSPersistentStore MR_defaultLocalStoreUrl];
    NSURL *modelURL = [[NSBundle mainBundle] URLForResource:@"Model" withExtension:@"momd"];
    cloudFileSystem = [[CDEICloudFileSystem alloc] initWithUbiquityContainerIdentifier:nil];
    ensemble = [[CDEPersistentStoreEnsemble alloc] initWithEnsembleIdentifier:@"MagicalRecord" persistentStoreURL:url managedObjectModelURL:modelURL cloudFileSystem:cloudFileSystem];
    ensemble.delegate = self;
    
    // Listen for local saves, and trigger merges
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(localSaveOccurred:) name:CDEMonitoredManagedObjectContextDidSaveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(cloudDataDidDownload:) name:CDEICloudFileSystemDidDownloadFilesNotification object:nil];
    
    [self syncWithCompletion:NULL];
    
    return YES;
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    UIBackgroundTaskIdentifier identifier = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:NULL];
    [[NSManagedObjectContext MR_defaultContext] MR_saveToPersistentStoreWithCompletion:^(BOOL success, NSError *error) {
        [self syncWithCompletion:^{
            [[UIApplication sharedApplication] endBackgroundTask:identifier];
        }];
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
    ViewController *viewController = (id)self.window.rootViewController;
    [viewController.activityIndicator startAnimating];
    if (!ensemble.isLeeched) {
        [ensemble leechPersistentStoreWithCompletion:^(NSError *error) {
            [viewController.activityIndicator stopAnimating];
            if (completion) completion();
        }];
    }
    else {
        [ensemble mergeWithCompletion:^(NSError *error) {
            [viewController.activityIndicator stopAnimating];
            if (completion) completion();
        }];
    }
}

- (void)persistentStoreEnsemble:(CDEPersistentStoreEnsemble *)ensemble didSaveMergeChangesWithNotification:(NSNotification *)notification
{
    NSManagedObjectContext *rootContext = [NSManagedObjectContext MR_rootSavingContext];
    [rootContext performBlock:^{
        [rootContext mergeChangesFromContextDidSaveNotification:notification];
    }];
    
    NSManagedObjectContext *mainContext = [NSManagedObjectContext MR_defaultContext];
    [mainContext performBlock:^{
        [mainContext mergeChangesFromContextDidSaveNotification:notification];
    }];
}

@end

