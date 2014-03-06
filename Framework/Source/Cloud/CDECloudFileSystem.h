//
//  CDECloudFileSystem.h
//  Ensembles
//
//  Created by Drew McCormack on 4/12/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CDEDefines.h"

typedef void (^CDEFileExistenceCallback)(BOOL exists, BOOL isDirectory, NSError *error);
typedef void (^CDEDirectoryContentsCallback)(NSArray *contents, NSError *error);

@protocol CDECloudFileSystem <NSObject>

@required
@property (nonatomic, assign, readonly) BOOL isConnected;
@property (nonatomic, strong, readonly) id <NSObject, NSCopying, NSCoding> identityToken; // Must fire KVO Notifications

- (void)connect:(CDECompletionBlock)completion;

- (void)fileExistsAtPath:(NSString *)path completion:(CDEFileExistenceCallback)block;

- (void)createDirectoryAtPath:(NSString *)path completion:(CDECompletionBlock)block;
- (void)contentsOfDirectoryAtPath:(NSString *)path completion:(CDEDirectoryContentsCallback)block;

- (void)removeItemAtPath:(NSString *)fromPath completion:(CDECompletionBlock)block;

- (void)uploadLocalFile:(NSString *)fromPath toPath:(NSString *)toPath completion:(CDECompletionBlock)block;
- (void)downloadFromPath:(NSString *)fromPath toLocalFile:(NSString *)toPath completion:(CDECompletionBlock)block;

@optional
- (void)performInitialPreparation:(CDECompletionBlock)completion;

@end
