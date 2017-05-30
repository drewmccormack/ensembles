//
//  CDEDropboxV2CloudFileSystem.h
//
//  Created by Drew McCormack on 12/09/16.
//  Copyright (c) 2016 The Mental Faculty B.V. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <Ensembles/Ensembles.h>

@class CDEDropboxV2CloudFileSystem;
@class DBUserClient;


@protocol CDEDropboxV2CloudFileSystemDelegate <NSObject>

/// Use the Dropbox SDK to link the session.
- (void)linkSessionForDropboxCloudFileSystem:(nonnull CDEDropboxV2CloudFileSystem *)fileSystem completion:(nonnull CDECompletionBlock)completion;

@optional

/// This will be called if the `subscribeForRemoteFileChangeNotificationsWithCompletion:` method has been invoked to detect remote changes.
- (void)dropboxCloudFileSystemDidDetectRemoteFileChanges:(CDEDropboxV2CloudFileSystem * _Nonnull)fileSystem;

@end


@interface CDEDropboxV2CloudFileSystem : NSObject <CDECloudFileSystem>

/// You can provide your own custom client instance for working with Dropbox API. By default [DBClientsManager authorizedClient] is used.
@property (nonatomic, readwrite, nullable) DBUserClient *client;
@property (nonatomic, readwrite, nullable, weak) id <CDEDropboxV2CloudFileSystemDelegate> delegate;

/// When this is YES, subfolders are added to the 'data' folder to prevent exceeding of the Dropbox folder contents limit (10000).
/// This should only be a problem for apps with very many data blobs. You should not change this setting once your app is in production. Default is NO.
@property (nonatomic, readwrite) BOOL partitionDataFilesBetweenSubdirectories;

/// Stipulate a subfolder in Dropbox. Default nil (root)
@property (nonatomic, readwrite, copy, nullable) NSString *relativePathToRootInDropbox;


/// This will use Dropbox longpolling to detect remote changes in the cloud. When they are detected, the
/// `dropboxCloudFileSystemDidDetectRemoteFileChanges:` delegate method fires. That is a good time to merge, in order
/// to download the new changes.
- (void)subscribeForRemoteFileChangeNotificationsWithCompletion:(nullable CDECompletionBlock)completion;

@end
