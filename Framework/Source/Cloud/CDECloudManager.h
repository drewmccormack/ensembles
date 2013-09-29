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

@property (nonatomic, readonly) CDEEventStore *eventStore;
@property (nonatomic, readonly) id <CDECloudFileSystem> cloudFileSystem;

- (instancetype)initWithEventStore:(CDEEventStore *)newStore cloudFileSystem:(id <CDECloudFileSystem>)cloudFileSystem;

- (void)createRemoteDirectoryStructureWithCompletion:(CDECompletionBlock)completion;

- (void)importNewRemoteEventsWithCompletion:(CDECompletionBlock)completion;
- (void)transferNewRemoteFilesToTransitCacheWithCompletion:(CDECompletionBlock)completion;
- (void)migrateNewEventsFromTransitCacheWithCompletion:(CDECompletionBlock)completion;

- (void)exportNewLocalEventsWithCompletion:(CDECompletionBlock)completion;
- (void)migrateNewLocalEventsToTransitCacheWithCompletion:(CDECompletionBlock)completion;
- (void)transferFilesInTransitCacheToCloudWithCompletion:(CDECompletionBlock)completion;

@end
