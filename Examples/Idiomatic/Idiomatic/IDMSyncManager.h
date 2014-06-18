//
//  IDMSyncManager.h
//  Idiomatic
//
//  Created by Drew McCormack on 04/03/14.
//  Copyright (c) 2014 The Mental Faculty B.V. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Ensembles/Ensembles.h>

extern NSString * const IDMSyncActivityDidBeginNotification;
extern NSString * const IDMSyncActivityDidEndNotification;

extern NSString * const IDMCloudServiceUserDefaultKey;
extern NSString * const IDMICloudService;
extern NSString * const IDMDropboxService;
extern NSString * const IDMNodeS3Service;
extern NSString * const IDMMultipeerService;

@interface IDMSyncManager : NSObject

@property (nonatomic, readonly, strong) CDEPersistentStoreEnsemble *ensemble;
@property (nonatomic, readwrite, strong) NSManagedObjectContext *managedObjectContext;
@property (nonatomic, readwrite, copy) NSString *storePath;

+ (instancetype)sharedSyncManager;

- (void)connectToSyncService:(NSString *)serviceId withCompletion:(CDECompletionBlock)completion;
- (void)disconnectFromSyncServiceWithCompletion:(CDECodeBlock)completion;

- (void)synchronizeWithCompletion:(CDECompletionBlock)completion;
- (BOOL)canSynchronize;

- (void)setup;
- (void)reset;

- (BOOL)handleOpenURL:(NSURL *)url;

- (void)storeNodeCredentials;
- (void)cancelNodeCredentialsUpdate;

@end
