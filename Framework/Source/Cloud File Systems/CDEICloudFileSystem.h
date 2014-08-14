//
//  CDEICloudFileSystem.h
//  Ensembles
//
//  Created by Drew McCormack on 20/09/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CDECloudFileSystem.h"

extern NSString * const CDEICloudFileSystemDidDownloadFilesNotification;
extern NSString * const CDEICloudFileSystemDidMakeDownloadProgressNotification;

@interface CDEICloudFileSystem : NSObject <CDECloudFileSystem, NSFilePresenter>

@property (nonatomic, readonly) NSString *relativePathToRootInContainer;
@property (atomic, readonly) unsigned long long bytesRemainingToDownload;

- (instancetype)initWithUbiquityContainerIdentifier:(NSString *)newIdentifier;
- (instancetype)initWithUbiquityContainerIdentifier:(NSString *)newIdentifier relativePathToRootInContainer:(NSString *)rootSubPath;

@end
