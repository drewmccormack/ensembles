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

@interface CDEICloudFileSystem : NSObject <CDECloudFileSystem>

@property (nonatomic, readonly) NSString *relativePathToRootInContainer;

- (instancetype)initWithUbiquityContainerIdentifier:(NSString *)newIdentifier;
- (instancetype)initWithUbiquityContainerIdentifier:(NSString *)newIdentifier relativePathToRootInContainer:(NSString *)rootSubPath;

@end
