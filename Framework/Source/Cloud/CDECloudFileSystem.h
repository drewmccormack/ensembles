//
//  CDECloudFileSystem.h
//  Syncophant for iOS
//
//  Created by Drew McCormack on 4/12/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CDEDefines.h"

@protocol CDECloudFileSystem <NSObject>

@required
@property (nonatomic, readonly) BOOL isConnected;
@property (nonatomic, readonly) id <NSObject, NSCopying, NSCoding> identityToken; // Must fire KVO Notifications

- (void)connect:(CDECompletionBlock)completion;

- (void)fileExistsAtPath:(NSString *)path completion:(void(^)(BOOL exists, BOOL isDirectory, NSError *error))block;

- (void)createDirectoryAtPath:(NSString *)path completion:(CDECompletionBlock)block;
- (void)contentsOfDirectoryAtPath:(NSString *)path completion:(void(^)(NSArray *contents, NSError *error))block;

- (void)removeItemAtPath:(NSString *)fromPath completion:(CDECompletionBlock)block;

- (void)uploadLocalFile:(NSString *)fromPath toPath:(NSString *)toPath completion:(CDECompletionBlock)block;
- (void)downloadFromPath:(NSString *)fromPath toLocalFile:(NSString *)toPath completion:(CDECompletionBlock)block;

@optional
- (void)performInitialPreparation:(CDECompletionBlock)completion;

@end
