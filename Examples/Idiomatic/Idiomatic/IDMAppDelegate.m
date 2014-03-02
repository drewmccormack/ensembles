//
//  IDMAppDelegate.m
//  Idiomatic
//
//  Created by Drew McCormack on 20/09/13.
//  Copyright (c) 2013 The Mental Faculty B.V. All rights reserved.
//

#import <CoreData/CoreData.h>
#import <DropboxSDK/DropboxSDK.h>

#import "CoreDataEnsembles.h"
#import "CDEICloudFileSystem.h"
#import "CDEDropboxCloudFileSystem.h"
#import "CDENodeCloudFileSystem.h"
#import "IDMAppDelegate.h"
#import "IDMNotesViewController.h"
#import "IDMTagsViewController.h"

NSString * const IDMSyncActivityDidBeginNotification = @"IDMSyncActivityDidBegin";
NSString * const IDMSyncActivityDidEndNotification = @"IDMSyncActivityDidEnd";

NSString * const IDMCloudServiceUserDefaultKey = @"IDMCloudServiceUserDefaultKey";
NSString * const IDMICloudService = @"icloud";
NSString * const IDMDropboxService = @"dropbox";
NSString * const IDMNodeS3Service = @"node";

// Set these with your account details
NSString * const IDMICloudContainerIdentifier = @"P7BXV6PHLD.com.mentalfaculty.idiomatic";
NSString * const IDMDropboxAppKey = @"fjgu077wm7qffv0";
NSString * const IDMDropboxAppSecret = @"djibc9zfvppronm";

@interface IDMAppDelegate () <CDEPersistentStoreEnsembleDelegate, DBSessionDelegate, CDEDropboxCloudFileSystemDelegate, CDENodeCloudFileSystemDelegate>

@property (nonatomic, readonly) NSURL *storeDirectoryURL;
@property (nonatomic, readonly) NSURL *storeURL;

@end

@implementation IDMAppDelegate {
    NSManagedObjectContext *managedObjectContext;
    CDEPersistentStoreEnsemble *ensemble;
    CDEICloudFileSystem *cloudFileSystem;
    NSUInteger activeMergeCount;
    CDECompletionBlock dropboxLinkSessionCompletion;
    DBSession *dropboxSession;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    // Ensembles logging
    CDESetCurrentLoggingLevel(CDELoggingLevelVerbose);
    
    // Setup Core Data Stack
    [[NSFileManager defaultManager] createDirectoryAtURL:self.storeDirectoryURL withIntermediateDirectories:YES attributes:nil error:NULL];
    [self setupContext];
    
    // Setup Ensemble
    [self setupEnsemble];
    
    // Setup UI
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
    UINavigationController *navController = (id)self.window.rootViewController;
    IDMTagsViewController *tagsController = (id)navController.topViewController;
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
            
            [self incrementMergeCount];
            [ensemble mergeWithCompletion:^(NSError *error) {
                [self decrementMergeCount];
                if (error) NSLog(@"Error merging: %@", error);
                [[UIApplication sharedApplication] endBackgroundTask:identifier];
            }];
        }];
    });
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    [self synchronizeWithCompletion:NULL];
}

#pragma mark - Persistent Store

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

#pragma mark - Persistent Store Ensemble

- (void)connectToSyncService:(NSString *)serviceId withCompletion:(CDECompletionBlock)completion
{
    [[NSUserDefaults standardUserDefaults] setObject:serviceId forKey:IDMCloudServiceUserDefaultKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self setupEnsemble];
    [self synchronizeWithCompletion:completion];
}

- (void)disconnectFromSyncServiceWithCompletion:(CDECodeBlock)completion
{
    [ensemble deleechPersistentStoreWithCompletion:^(NSError *error) {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:IDMCloudServiceUserDefaultKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
        [dropboxSession unlinkAll];
        dropboxSession = nil;
        ensemble.delegate = nil;
        ensemble = nil;
        if (completion) completion();
    }];
}

- (void)setupEnsemble
{
    if (!self.canSynchronize) return;
    
    cloudFileSystem = [self makeCloudFileSystem];
    if (!cloudFileSystem) return;
    
    NSURL *modelURL = [[NSBundle mainBundle] URLForResource:@"Model" withExtension:@"momd"];
    ensemble = [[CDEPersistentStoreEnsemble alloc] initWithEnsembleIdentifier:@"MainStore" persistentStorePath:self.storeURL.path managedObjectModelURL:modelURL cloudFileSystem:cloudFileSystem];
    ensemble.delegate = self;
}

- (id <CDECloudFileSystem>)makeCloudFileSystem
{
    NSString *cloudService = [[NSUserDefaults standardUserDefaults] stringForKey:IDMCloudServiceUserDefaultKey];
    id <CDECloudFileSystem> newSystem = nil;
    if ([cloudService isEqualToString:IDMICloudService]) {
        newSystem = [[CDEICloudFileSystem alloc] initWithUbiquityContainerIdentifier:IDMICloudContainerIdentifier];
    }
    else if ([cloudService isEqualToString:IDMDropboxService]) {
        dropboxSession = [[DBSession alloc] initWithAppKey:IDMDropboxAppKey appSecret:IDMDropboxAppSecret root:kDBRootAppFolder];
        dropboxSession.delegate = self;
        CDEDropboxCloudFileSystem *newDropboxSystem = [[CDEDropboxCloudFileSystem alloc] initWithSession:dropboxSession];
        newDropboxSystem.delegate = self;
        newSystem = newDropboxSystem;
    }
    else if ([cloudService isEqualToString:IDMNodeS3Service]) {
        NSURL *url = [NSURL URLWithString:@"https://ensembles.herokuapp.com"];
        CDENodeCloudFileSystem *newNodeFileSystem = [[CDENodeCloudFileSystem alloc] initWithBaseURL:url];
        newNodeFileSystem.delegate = self;
        newSystem = newNodeFileSystem;
    }
    return newSystem;
}

#pragma mark - Sync Methods

- (BOOL)canSynchronize
{
    NSString *cloudService = [[NSUserDefaults standardUserDefaults] stringForKey:IDMCloudServiceUserDefaultKey];
    return cloudService != nil;
}

- (void)synchronizeWithCompletion:(CDECompletionBlock)completion
{
    if (!self.canSynchronize) return;
    
    [self incrementMergeCount];
    if (!ensemble.isLeeched) {
        [ensemble leechPersistentStoreWithCompletion:^(NSError *error) {
            [self decrementMergeCount];
            [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
            if (error) {
                NSLog(@"Could not leech to ensemble: %@", error);
                [self disconnectFromSyncServiceWithCompletion:^{
                    if (completion) completion(error);
                }];
            }
            else {
                if (completion) completion(error);
            }
        }];
    }
    else {
        [ensemble mergeWithCompletion:^(NSError *error) {
            [self decrementMergeCount];
            if (error) NSLog(@"Error merging: %@", error);
            if (completion) completion(error);
        }];
    }
}

- (void)decrementMergeCount
{
    activeMergeCount--;
    if (activeMergeCount == 0) {
        [[NSNotificationCenter defaultCenter] postNotificationName:IDMSyncActivityDidEndNotification object:nil];
        [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
    }
}

- (void)incrementMergeCount
{
    activeMergeCount++;
    if (activeMergeCount == 1) {
        [[NSNotificationCenter defaultCenter] postNotificationName:IDMSyncActivityDidBeginNotification object:nil];
        [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:YES];
    }
}

#pragma mark - Persistent Store Ensemble Delegate

- (void)persistentStoreEnsemble:(CDEPersistentStoreEnsemble *)ensemble didSaveMergeChangesWithNotification:(NSNotification *)notification
{
    [managedObjectContext performBlock:^{
        [managedObjectContext mergeChangesFromContextDidSaveNotification:notification];
    }];
}

- (NSArray *)persistentStoreEnsemble:(CDEPersistentStoreEnsemble *)ensemble globalIdentifiersForManagedObjects:(NSArray *)objects
{
    return [objects valueForKeyPath:@"uniqueIdentifier"];
}

- (void)persistentStoreEnsemble:(CDEPersistentStoreEnsemble *)ensemble didDeleechWithError:(NSError *)error
{
    NSLog(@"Store did deleech with error: %@", error);
}

#pragma mark - Dropbox Session

- (BOOL)application:(UIApplication *)application handleOpenURL:(NSURL *)url {
	if ([dropboxSession handleOpenURL:url]) {
		if ([dropboxSession isLinked]) {
            if (dropboxLinkSessionCompletion) dropboxLinkSessionCompletion(nil);
		}
        else {
            NSError *error = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeAuthenticationFailure userInfo:nil];
            if (dropboxLinkSessionCompletion) dropboxLinkSessionCompletion(error);
        }
        dropboxLinkSessionCompletion = NULL;
		return YES;
	}
	
	return NO;
}

- (void)linkSessionForDropboxCloudFileSystem:(CDEDropboxCloudFileSystem *)fileSystem completion:(CDECompletionBlock)completion
{
    dropboxLinkSessionCompletion = [completion copy];
    [dropboxSession linkFromController:self.window.rootViewController];
}

- (void)sessionDidReceiveAuthorizationFailure:(DBSession*)session userId:(NSString *)userId
{
}

#pragma mark - Node Server Delegate Methods

- (void)nodeCloudFileSystem:(CDENodeCloudFileSystem *)fileSystem updateLoginCredentialsWithCompletion:(CDECompletionBlock)completion
{
    completion(nil);
}

@end
