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

/**
 A cloud file system facilitates data transfer between devices.
 
 Any backend that can store files at paths can be used. This could be a key-value store like S3, or a true file system like WebDAV. Even direct connections like the multipeer connectivity in iOS 7 can be used as a cloud file system when coupled with a local cache of files.
 */
@protocol CDECloudFileSystem <NSObject>

@required

///
/// @name Connection
///

/**
 Whether ensembles is considered to be connected to the file system, and thereby can make requests. 
 
 Different backends may interpret this differently. What should be true is that if `isConnected` returns `YES`, ensembles can attempt to make file transactions.
 
 If this property is `NO`, ensembles will invoke the `connect:` method before attempting further file operations.
 */
@property (nonatomic, assign, readonly) BOOL isConnected;

/**
 A token representing the user of the cloud file system.
 
 Often this will be the user or login name.
 
 When implementing a cloud file system class, it is important to fire KVO notifications when the identity changes. These are observed by the ensemble, and used to determine whether it is necessary to force a deleech.
 */
@property (nonatomic, strong, readonly) id <NSObject, NSCopying, NSCoding> identityToken; // Must fire KVO Notifications

/**
 Attempts to connect to the cloud backend.
 
 If successful, the completion block should be called on the main thread with argument of `nil`. If the connection fails, an `NSError` instance should be passed to the completion block.
 
 @param completion The completion block called when the connection succeeds or fails.
 */
- (void)connect:(CDECompletionBlock)completion;

///
/// @name File Existence
///

/**
 Determines whether a file exists in the cloud, and if so, whether it is a standard file or a directory.
 
 Upon determining whether the file exists, the completion block should be called on the main thread.
 
 @param block The completion block, which takes `BOOL` arguments for whether the file exists and whether it is a directory. The last argument is an `NSError`, which should be `nil` if successful.
 */
- (void)fileExistsAtPath:(NSString *)path completion:(CDEFileExistenceCallback)block;

///
/// @name Working with Directories
///

/**
 Creates a directory at a given path.
 
 The completion block should be called on the main thread when the creation concludes, passing an error or `nil`.
 
 @param block The completion block, which takes one argument, an `NSError`. It should be `nil` upon success.
 */
- (void)createDirectoryAtPath:(NSString *)path completion:(CDECompletionBlock)block;

/**
 Determines the contents of a directory at a given path.
 
 The completion block has an `NSArray` as its first parameter. The array should contain `CDECloudFile` and `CDECloudDirectory` objects. The completion block should should be called on the main thread.
 
 @param block The completion block, which takes two arguments. The first is an array of file/directory objects, and the second is an `NSError`. It should be `nil` upon success.
 */
- (void)contentsOfDirectoryAtPath:(NSString *)path completion:(CDEDirectoryContentsCallback)block;

///
/// @name Deleting Files and Directories
///

/**
 Deletes a file or directory.
 
 The completion block takes and `NSError`, which should be `nil` upon successful completion. The block should be called on the main thread.
 
 @param block The completion block, which takes one argument, an `NSError`.
 */
- (void)removeItemAtPath:(NSString *)fromPath completion:(CDECompletionBlock)block;

///
/// @name Transferring Files
///

/**
 Uploads a local file to the cloud file system.
 
 The completion block takes an `NSError`, which should be `nil` upon successful completion. The block should be called on the main thread.
 
 @param fromPath The path to the file on the device.
 @param toPath The path of the file in the cloud file system.
 @param block The completion block, which takes one argument, an `NSError`.
 */
- (void)uploadLocalFile:(NSString *)fromPath toPath:(NSString *)toPath completion:(CDECompletionBlock)block;

/**
 Downloads a cloud file to the local file system.
 
 The completion block takes an `NSError`, which should be `nil` upon successful completion. The block should be called on the main thread.
 
 @param fromPath The path of the file in the cloud file system.
 @param toPath The path to the file on the device.
 @param block The completion block, which takes one argument, an `NSError`.
 */
- (void)downloadFromPath:(NSString *)fromPath toLocalFile:(NSString *)toPath completion:(CDECompletionBlock)block;

@optional

///
/// @name Initial Setup
///

/**
 An optional method which can be implemented to perform initialization when the ensemble leeches.
 
 For example, if the root directory of the file system needs to be created, this would be a good time to do that.
 
 The completion block takes an `NSError`, which should be `nil` upon successful completion. The block should be called on the main thread.

 @param completion The completion block, which takes one argument, an `NSError`.
 */
- (void)performInitialPreparation:(CDECompletionBlock)completion;


///
/// @name Repair
///

/**
 An optional method which can be implemented to perform any repairs that are needed prior to merging.
 
 Eg. Systems like iCloud and Dropbox can sometimes create duplicate files or folders. This is a good place to 'fix' that.
 
 The completion block takes an `NSError`, which should be `nil` upon successful completion. The block should be called on the main thread.
 
 @param ensembleDir Path to the directory of the ensemble.
 @param completion The completion block, which takes one argument, an `NSError`.
 */
- (void)repairEnsembleDirectory:(NSString *)ensembleDir completion:(CDECompletionBlock)completion;


@end
