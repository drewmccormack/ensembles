//
//  IDMSyncManager.m
//  Idiomatic
//
//  Created by Drew McCormack on 04/03/14.
//  Copyright (c) 2014 The Mental Faculty B.V. All rights reserved.
//

#import <CoreData/CoreData.h>
#import <ObjectiveDropboxOfficial/ObjectiveDropboxOfficial.h>
#import <Security/Security.h>

#import "IDMSyncManager.h"
#import "CDEDropboxV2CloudFileSystem.h"
#import "CDENodeCloudFileSystem.h"
#import "IDMNodeSyncSettingsViewController.h"
#import "CDEMultipeerCloudFileSystem.h"
#import "IDMMultipeerManager.h"

NSString * const IDMSyncActivityDidBeginNotification = @"IDMSyncActivityDidBegin";
NSString * const IDMSyncActivityDidEndNotification = @"IDMSyncActivityDidEnd";

NSString * const IDMCloudServiceUserDefaultKey = @"IDMCloudServiceUserDefaultKey";
NSString * const IDMICloudService = @"icloud";
NSString * const IDMDropboxService = @"dropbox";
NSString * const IDMNodeS3Service = @"node";
NSString * const IDMMultipeerService = @"multipeer";

NSString * const IDMNodeS3EmailDefaultKey = @"IDMNodeS3EmailDefaultKey";

// Set these with your account details
NSString * const IDMICloudContainerIdentifier = nil;
NSString * const IDMDropboxAppKey = @"fjgu077wm7qffv0";
NSString * const IDMDropboxAppSecret = @"djibc9zfvppronm";

@interface IDMSyncManager () <CDEPersistentStoreEnsembleDelegate, CDEDropboxV2CloudFileSystemDelegate, CDENodeCloudFileSystemDelegate>

@end

@implementation IDMSyncManager {
    id <CDECloudFileSystem> cloudFileSystem;
    NSUInteger activeMergeCount;
    CDECompletionBlock dropboxLinkSessionCompletion;
    CDECompletionBlock nodeCredentialUpdateCompletion;
    IDMMultipeerManager *multipeerManager;
}

@synthesize ensemble = ensemble;
@synthesize storePath = storePath;
@synthesize managedObjectContext = managedObjectContext;

+ (instancetype)sharedSyncManager
{
    static id sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[IDMSyncManager alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(icloudDidDownload:) name:CDEICloudFileSystemDidDownloadFilesNotification object:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didSaveMonitoredManagedObjectContext:) name:CDEMonitoredManagedObjectContextDidSaveNotification object:nil];
    }
    return self;
}

#pragma mark - Setting Up and Resetting

- (void)setup
{
    [self setupEnsemble];
}

- (void)reset
{
    [multipeerManager stop];
    [multipeerManager.multipeerCloudFileSystem removeAllFiles];
    multipeerManager = nil;

    [self clearNodePassword];
    
    if ([DBClientsManager authorizedClient]) {
        [DBClientsManager unlinkAndResetClients];
    }
    
    ensemble.delegate = nil;
    [ensemble dismantle];
    ensemble = nil;
    
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:IDMCloudServiceUserDefaultKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

#pragma mark - Connecting to a Backend Service

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
        [self reset];
        if (completion) completion();
    }];
}

#pragma mark - Persistent Store Ensemble

- (void)setupEnsemble
{
    if (!self.canSynchronize) return;

    cloudFileSystem = [self makeCloudFileSystem];
    if (!cloudFileSystem) return;

    NSURL *storeURL = [NSURL fileURLWithPath:storePath];
    NSURL *modelURL = [[NSBundle mainBundle] URLForResource:@"Model" withExtension:@"momd"];
    ensemble = [[CDEPersistentStoreEnsemble alloc] initWithEnsembleIdentifier:@"MainStore" persistentStoreURL:storeURL managedObjectModelURL:modelURL cloudFileSystem:cloudFileSystem];
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
//        dropboxSession = [[DBSession alloc] initWithAppKey:IDMDropboxAppKey appSecret:IDMDropboxAppSecret root:kDBRootAppFolder];
//        dropboxSession.delegate = self;
//        CDEDropboxV2CloudFileSystem *newDropboxSystem = [[CDEDropboxV2CloudFileSystem alloc] initWithSession:dropboxSession];
//        newDropboxSystem.delegate = self;
//        newSystem = newDropboxSystem;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            [DBClientsManager setupWithAppKey:IDMDropboxAppKey];
        });
        CDEDropboxV2CloudFileSystem *newDropboxSystem = [[CDEDropboxV2CloudFileSystem alloc] init];
        newDropboxSystem.delegate = self;
        newSystem = newDropboxSystem;
    }
    else if ([cloudService isEqualToString:IDMNodeS3Service]) {
        NSURL *url = [NSURL URLWithString:@"https://ensembles.herokuapp.com"];
        NSString *username = [[NSUserDefaults standardUserDefaults] stringForKey:IDMNodeS3EmailDefaultKey] ? : @"";
        NSString *password = [self retrieveNodePassword];
        CDENodeCloudFileSystem *newNodeFileSystem = [[CDENodeCloudFileSystem alloc] initWithBaseURL:url];
        newNodeFileSystem.delegate = self;
        newNodeFileSystem.username = username;
        newNodeFileSystem.password = password;
        newSystem = newNodeFileSystem;
    }
    else if ([cloudService isEqualToString:IDMMultipeerService]) {
        multipeerManager = [[IDMMultipeerManager alloc] init];

        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        NSString *path = [paths.lastObject stringByAppendingPathComponent:@"Idiomatic/Multipeer"];
        CDEMultipeerCloudFileSystem *multipeerCloudFileSystem = [[CDEMultipeerCloudFileSystem alloc] initWithRootDirectory:path multipeerConnection:multipeerManager];
        multipeerManager.multipeerCloudFileSystem = multipeerCloudFileSystem;
        [multipeerManager start];
        
        newSystem = multipeerCloudFileSystem;

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didImportFiles) name:CDEMultipeerCloudFileSystemDidImportFilesNotification object:nil];
    }
    
    return newSystem;
}

#pragma mark - Sync Methods

- (void)icloudDidDownload:(NSNotification *)notif
{
    [self synchronizeWithCompletion:NULL];
}

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
            if (error && !ensemble.isLeeched) {
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
            [multipeerManager syncFilesWithAllPeers];
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
    [self reset];
}

#pragma mark - Dropbox Session

- (BOOL)handleOpenURL:(NSURL *)url
{
    DBOAuthResult *authResult = [DBClientsManager handleRedirectURL:url];
    if (!authResult) {
        return NO;
    }
    
    if ([authResult isSuccess]) {
        // Here's an example of injecting a custom API client created from an access token
        // (e.g. when working in a multi-user environment)
        if ([cloudFileSystem isKindOfClass:[CDEDropboxV2CloudFileSystem class]]) {
            CDEDropboxV2CloudFileSystem *dropboxSystem = cloudFileSystem;
            if (!dropboxSystem.client) {
                NSString *accessToken = authResult.accessToken.accessToken;
                dropboxSystem.client = [[DBUserClient alloc] initWithAccessToken:accessToken];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (dropboxLinkSessionCompletion) dropboxLinkSessionCompletion(nil);
            dropboxLinkSessionCompletion = NULL;
        });
    }
    else {
        NSError *error = [NSError errorWithDomain:CDEErrorDomain
                                             code:CDEErrorCodeAuthenticationFailure
                                         userInfo:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (dropboxLinkSessionCompletion) dropboxLinkSessionCompletion(error);
            dropboxLinkSessionCompletion = NULL;
        });
    }
    
    return YES;
}

- (void)linkSessionForDropboxCloudFileSystem:(CDEDropboxV2CloudFileSystem *)fileSystem completion:(CDECompletionBlock)completion
{
    // User is already authorized, call the completion block right away
    if ([DBClientsManager authorizedClient] != nil) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil);
        });
        return;
    }
    
    dropboxLinkSessionCompletion = [completion copy];
    UIApplication *application = [UIApplication sharedApplication];
    UIViewController *rootController = [[application keyWindow] rootViewController];
    [DBClientsManager authorizeFromController:application
                                   controller:rootController
                                      openURL:^(NSURL *url){ [[UIApplication sharedApplication] openURL:url]; }];
}

- (void)applicationDidBecomeActive:(NSNotification *)notif
{
    // Need to check if there is a live dropbox link session, because if the user doesn't have the
    // Dropbox app, and cancels the login in the browser, we get no callback to say it failed.
    if (dropboxLinkSessionCompletion) {
        NSError *error = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeAuthenticationFailure userInfo:nil];
        dropboxLinkSessionCompletion(error);
        dropboxLinkSessionCompletion = NULL;
    }
}

#pragma mark - Node-S3 Backend Delegate Methods

- (void)nodeCloudFileSystem:(CDENodeCloudFileSystem *)fileSystem updateLoginCredentialsWithCompletion:(CDECompletionBlock)completion
{
    [self decrementMergeCount];
    [self clearNodePassword];
    nodeCredentialUpdateCompletion = [completion copy];

    // Present the node settings view
    UIWindow *window = [[UIApplication sharedApplication] keyWindow];
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
    UINavigationController *nodeSettingsNavController = [storyboard instantiateViewControllerWithIdentifier:@"NodeSettingsNavigationController"];
    IDMNodeSyncSettingsViewController *settingsController = (id)nodeSettingsNavController.topViewController;
    settingsController.nodeFileSystem = fileSystem;

    [window.rootViewController presentViewController:nodeSettingsNavController animated:YES completion:NULL];
}

#pragma mark - Storing Node Credentials

- (void)storeNodeCredentials
{
    [self incrementMergeCount];

    CDENodeCloudFileSystem *nodeFileSystem = (id)self.ensemble.cloudFileSystem;
    NSString *email = nodeFileSystem.username;
    NSString *password = nodeFileSystem.password;
    NSError *error = nil;
    if (email && password) {
        [[NSUserDefaults standardUserDefaults] setObject:email forKey:IDMNodeS3EmailDefaultKey];
        [self storeNodePassword:password];
    }
    else {
        NSDictionary *info = @{NSLocalizedDescriptionKey : @"Invalid username or password"};
        error = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeAuthenticationFailure userInfo:info];
    }

    if (nodeCredentialUpdateCompletion) nodeCredentialUpdateCompletion(error);
    nodeCredentialUpdateCompletion = NULL;
}

- (void)cancelNodeCredentialsUpdate
{
    [self incrementMergeCount];

    NSError *error = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeCancelled userInfo:nil];
    if (nodeCredentialUpdateCompletion) nodeCredentialUpdateCompletion(error);
    nodeCredentialUpdateCompletion = NULL;
}

- (NSDictionary *)keychainQuery {
    NSString *serviceName = @"com.mentalfaculty.ensembles.idiosync";
    return @{
             (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
             (__bridge id)kSecAttrService : serviceName,
             (__bridge id)kSecAttrAccount : serviceName,
             (__bridge id)kSecAttrAccessible : (__bridge id)kSecAttrAccessibleAlways
             };
}

- (void)storeNodePassword:(NSString *)newPassword
{
    NSMutableDictionary *keychainQuery = [[self keychainQuery] mutableCopy];
    SecItemDelete((__bridge CFDictionaryRef)keychainQuery);
    keychainQuery[(__bridge id)kSecValueData] = [newPassword dataUsingEncoding:NSUTF8StringEncoding];
    SecItemAdd((__bridge CFDictionaryRef)keychainQuery, NULL);
}

- (NSString *)retrieveNodePassword
{
    NSMutableDictionary *keychainQuery = [[self keychainQuery] mutableCopy];
    keychainQuery[(__bridge id)kSecReturnData] = @YES;
    keychainQuery[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;

    NSString *result = nil;
    CFDataRef data = NULL;
    if (noErr == SecItemCopyMatching((__bridge CFDictionaryRef)keychainQuery, (CFTypeRef *)&data)) {
        result = [[NSString alloc] initWithData:(__bridge id)data encoding:NSUTF8StringEncoding];
    }
    if (data) CFRelease(data);

    return result;
}

- (void)clearNodePassword
{
    NSDictionary *keychainQuery = [self keychainQuery];
    SecItemDelete((__bridge CFDictionaryRef)keychainQuery);
}

#pragma mark - CDEMultipeerCloudFileSystem

- (void)didImportFiles
{
    [self synchronizeWithCompletion:nil];
}

#pragma mark - CDEMonitoredManagedObjectContext

- (void)didSaveMonitoredManagedObjectContext:(NSNotification *)note {
    // Notify other peers of new data
    [self synchronizeWithCompletion:^(NSError *error) {
        [multipeerManager sendNotificationOfNewlyAvailableDataToAllPeers];
    }];
}

@end
