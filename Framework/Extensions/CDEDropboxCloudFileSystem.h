//
//  CDEDropboxCloudFileSystem.h
//
//  Created by Drew McCormack on 4/12/13.
//  Copyright (c) 2013 The Mental Faculty B.V. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <Ensembles/Ensembles.h>

#import "DBRestClient.h"

@class CDEDropboxCloudFileSystem;


@protocol CDEDropboxCloudFileSystemDelegate <NSObject>

- (void)linkSessionForDropboxCloudFileSystem:(CDEDropboxCloudFileSystem *)fileSystem completion:(CDECompletionBlock)completion;

@end


@interface CDEDropboxCloudFileSystem : NSObject <CDECloudFileSystem, DBRestClientDelegate>

@property (readonly) DBSession *session;
@property (readwrite, weak) id <CDEDropboxCloudFileSystemDelegate> delegate;

- (instancetype)initWithSession:(DBSession *)session;

@end
