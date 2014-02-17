//
//  CDEEnsemblesServerCloudFileSystem.h
//
//  Created by Drew McCormack on 2/17/14.
//  Copyright (c) 2014 The Mental Faculty B.V. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "CDECloudFileSystem.h"


@protocol CDEEnsemblesServerCloudFileSystemDelegate <NSObject>

@end


@interface CDEEnsemblesServerCloudFileSystem : NSObject <CDECloudFileSystem>

@property (nonatomic, readonly) NSString *username;
@property (nonatomic, readonly) NSString * password;

@property (readwrite, weak) id <CDEEnsemblesServerCloudFileSystemDelegate> delegate;

@end
