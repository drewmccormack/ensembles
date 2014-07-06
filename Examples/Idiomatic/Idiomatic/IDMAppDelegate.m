//
//  IDMAppDelegate.m
//  Idiomatic
//
//  Created by Drew McCormack on 20/09/13.
//  Copyright (c) 2013 The Mental Faculty B.V. All rights reserved.
//

#import <CoreData/CoreData.h>
#import "IDMAppDelegate.h"
#import "IDMNotesViewController.h"
#import "IDMTagsViewController.h"
#import "IDMSyncManager.h"

@interface IDMAppDelegate ()

@property (nonatomic, readonly) NSURL *storeDirectoryURL;
@property (nonatomic, readonly) NSURL *storeURL;

@end

@implementation IDMAppDelegate {
    IDMTagsViewController *tagsController;
    NSManagedObjectContext *managedObjectContext;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    // Ensembles logging
    CDESetCurrentLoggingLevel(CDELoggingLevelVerbose);
    
    // Setup Core Data Stack
    [[NSFileManager defaultManager] createDirectoryAtURL:self.storeDirectoryURL withIntermediateDirectories:YES attributes:nil error:NULL];
    [self setupContext];
    
    // Setup Sync Manager
    IDMSyncManager *syncManager = [IDMSyncManager sharedSyncManager];
    syncManager.managedObjectContext = managedObjectContext;
    syncManager.storePath = self.storeURL.path;
    [syncManager setup];
    
    // Monitor saves
    [[NSNotificationCenter defaultCenter] addObserverForName:NSManagedObjectContextDidSaveNotification object:managedObjectContext queue:nil usingBlock:^(NSNotification *note) {
        [syncManager synchronizeWithCompletion:NULL];
    }];
    
    // Setup UI
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
    UINavigationController *navController = (id)self.window.rootViewController;
    tagsController = (id)navController.topViewController;
    IDMNotesViewController *notesController = [storyboard instantiateViewControllerWithIdentifier:@"NotesViewController"];
    [navController pushViewController:notesController animated:NO];
    
    // Pass context
    tagsController.managedObjectContext = managedObjectContext;
    notesController.managedObjectContext = managedObjectContext;
    
    return YES;
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    UIBackgroundTaskIdentifier identifier = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:NULL];
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        [managedObjectContext performBlock:^{
            if (managedObjectContext.hasChanges) {
                [managedObjectContext save:NULL];
            }
            
            [[IDMSyncManager sharedSyncManager] synchronizeWithCompletion:^(NSError *error) {
                [[UIApplication sharedApplication] endBackgroundTask:identifier];
            }];
        }];
    });
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    [[IDMSyncManager sharedSyncManager] synchronizeWithCompletion:NULL];
}

- (BOOL)application:(UIApplication *)application handleOpenURL:(NSURL *)url
{
    return [[IDMSyncManager sharedSyncManager] handleOpenURL:url];
}

#pragma mark - Core Data Stack

- (void)setupContext
{
    NSError *error;
    NSURL *modelURL = [[NSBundle mainBundle] URLForResource:@"Model" withExtension:@"momd"];
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
    
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

@end
