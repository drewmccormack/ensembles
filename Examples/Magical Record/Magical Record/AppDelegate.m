//
//  AppDelegate.m
//  Magical Record
//
//  Created by Drew McCormack on 18/04/14.
//  Copyright (c) 2014 Drew McCormack. All rights reserved.
//

#import <Ensembles/Ensembles.h>

#import "AppDelegate.h"
#import "CoreData+MagicalRecord.h"
#import "ViewController.h"
#import "NumberHolder.h"

@interface AppDelegate () <CDEPersistentStoreEnsembleDelegate>

@end

@implementation AppDelegate {
    CDEPersistentStoreEnsemble *ensemble;
    CDEICloudFileSystem *cloudFileSystem;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    // Load model. Don't use the standard 'merged model' of Magical Record, because that would include
    // the Ensembles model. Don't want to merge models.
    NSManagedObjectModel *model = [NSManagedObjectModel MR_newManagedObjectModelNamed:@"Model.momd"];
    [NSManagedObjectModel MR_setDefaultManagedObjectModel:model];
    
    // Setup Core Data Stack
    [MagicalRecord setShouldAutoCreateManagedObjectModel:NO];
    [MagicalRecord setupAutoMigratingCoreDataStack];
    
    // Create holder object if necessary. Ensure it is fully saved before we leech.
    NumberHolder *numberHolder = [NumberHolder MR_findFirst];
    if (!numberHolder) {
        numberHolder = [NumberHolder MR_createEntity];
        numberHolder.uniqueIdentifier = @"NumberHolder";
    }
    [[NSManagedObjectContext MR_defaultContext] MR_saveToPersistentStoreAndWait];
    
    // Setup Ensemble
    NSURL *url = [NSPersistentStore MR_urlForStoreName:[MagicalRecord defaultStoreName]];
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
    NSManagedObjectContext *rootContext = [NSManagedObjectContext MR_rootSavingContext];
    [rootContext performBlockAndWait:^{
        [rootContext mergeChangesFromContextDidSaveNotification:notification];
    }];
    
    NSManagedObjectContext *mainContext = [NSManagedObjectContext MR_defaultContext];
    [mainContext performBlockAndWait:^{
        [mainContext mergeChangesFromContextDidSaveNotification:notification];
    }];
}

- (NSArray *)persistentStoreEnsemble:(CDEPersistentStoreEnsemble *)ensemble globalIdentifiersForManagedObjects:(NSArray *)objects
{
    return [objects valueForKeyPath:@"uniqueIdentifier"];
}

@end

