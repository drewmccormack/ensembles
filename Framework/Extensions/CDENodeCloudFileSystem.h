//
//  CDENodeCloudFileSystem.h
//
//  Created by Drew McCormack on 2/17/14.
//  Copyright (c) 2014 The Mental Faculty B.V. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "CDECloudFileSystem.h"

@class CDENodeCloudFileSystem;


@protocol CDENodeCloudFileSystemDelegate <NSObject>

@required
- (void)nodeCloudFileSystem:(CDENodeCloudFileSystem *)fileSystem updateLoginCredentialsWithCompletion:(CDECompletionBlock)completion;

@end


@interface CDENodeCloudFileSystem : NSObject <CDECloudFileSystem>

@property (nonatomic, readwrite) NSString *username;
@property (nonatomic, readwrite) NSString *password;
@property (readwrite, weak) id <CDENodeCloudFileSystemDelegate> delegate;

- (id)initWithUsername:(NSString *)newUsername andPassword:(NSString *)newPassword;

@end
