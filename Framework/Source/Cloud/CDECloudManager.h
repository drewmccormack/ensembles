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
@property (nonatomic, strong, readonly) NSString *remoteEnsembleDirectory;

- (instancetype)initWithEventStore:(CDEEventStore *)newStore cloudFileSystem:(id <CDECloudFileSystem>)cloudFileSystem;

- (void)setup;

- (void)createRemoteDirectoryStructureWithCompletion:(CDECompletionBlock)completion;

- (void)snapshotRemoteFilesWithCompletion:(CDECompletionBlock)completion;
- (void)clearSnapshot;

- (void)importNewRemoteNonBaselineEventsWithCompletion:(CDECompletionBlock)completion;
- (void)importNewBaselineEventsWithCompletion:(CDECompletionBlock)completion;
- (void)importNewDataFilesWithCompletion:(CDECompletionBlock)completion;

- (void)exportNewLocalNonBaselineEventsWithCompletion:(CDECompletionBlock)completion;
- (void)exportNewLocalBaselineWithCompletion:(CDECompletionBlock)completion;
- (void)exportDataFilesWithCompletion:(CDECompletionBlock)completion;

- (void)removeOutdatedRemoteFilesWithCompletion:(CDECompletionBlock)completion;
- (BOOL)removeOutOfDateNewlyImportedFiles:(NSError * __autoreleasing *)error;

- (void)retrieveRegistrationInfoForStoreWithIdentifier:(NSString *)identifier completion:(void(^)(NSDictionary *info, NSError *error))completion;
- (void)setRegistrationInfo:(NSDictionary *)info forStoreWithIdentifier:(NSString *)identifier completion:(CDECompletionBlock)completion;

@end
