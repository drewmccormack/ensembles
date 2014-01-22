//
//  CDECloudManager.h
//  Test App iOS
//
//  Created by Drew McCormack on 5/29/13.
//  Copyright (c) 2013 The Mental Faculty B.V. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CDEDefines.h"

@protocol CDECloudFileSystem;
@class CDEEventStore;

@interface CDECloudManager : NSObject

@property (nonatomic, strong, readonly) CDEEventStore *eventStore;
@property (nonatomic, strong, readonly) id <CDECloudFileSystem> cloudFileSystem;

- (instancetype)initWithEventStore:(CDEEventStore *)newStore cloudFileSystem:(id <CDECloudFileSystem>)cloudFileSystem;

- (void)createRemoteDirectoryStructureWithCompletion:(CDECompletionBlock)completion;

- (void)snapshotRemoteFilesWithCompletion:(CDECompletionBlock)completion;
- (void)clearSnapshot;

- (void)importNewRemoteEventsWithCompletion:(CDECompletionBlock)completion;
- (void)transferNewRemoteEventFilesToTransitCacheWithCompletion:(CDECompletionBlock)completion;

- (void)importNewBaselineEventsWithCompletion:(CDECompletionBlock)completion;
- (void)transferNewRemoteBaselineFilesToTransitCacheWithCompletion:(CDECompletionBlock)completion;

- (void)migrateNewEventsWithAllowedTypes:(NSArray *)types fromTransitCacheWithCompletion:(CDECompletionBlock)completion;

- (void)exportNewLocalEventsWithCompletion:(CDECompletionBlock)completion;
- (void)migrateNewLocalNonBaselineEventsToTransitCacheWithCompletion:(CDECompletionBlock)completion;

- (void)exportNewLocalBaselineWithCompletion:(CDECompletionBlock)completion;

- (void)transferFilesInTransitCacheToRemoteDirectory:(NSString *)remoteDirectory completion:(CDECompletionBlock)completion;

- (void)removeOutdatedRemoteFilesWithCompletion:(CDECompletionBlock)completion;

- (void)retrieveRegistrationInfoForStoreWithIdentifier:(NSString *)identifier completion:(void(^)(NSDictionary *info, NSError *error))completion;
- (void)setRegistrationInfo:(NSDictionary *)info forStoreWithIdentifier:(NSString *)identifier completion:(CDECompletionBlock)completion;

@end
