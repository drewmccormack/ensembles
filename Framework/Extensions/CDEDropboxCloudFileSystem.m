//
//  CDEDropboxCloudFileSystem.m
//  Test App iOS
//
//  Created by Drew McCormack on 4/12/13.
//  Copyright (c) 2013 The Mental Faculty B.V. All rights reserved.
//

#import "CDEDropboxCloudFileSystem.h"
#import "DBMetadata.h"
#import "CDEDefines.h"
#import "CDEAsynchronousTaskQueue.h"
#import "CDECloudFile.h"
#import "CDECloudDirectory.h"

typedef void (^CDEFileExistenceCallback)(BOOL exists, BOOL isDirectory, NSError *error);
typedef void (^CDEDirectoryContentsCallback)(NSArray *contents, NSError *error);

const NSUInteger kCDENumberOfRetriesForFailedAttempt = 5;

@implementation CDEDropboxCloudFileSystem {
    DBRestClient *restClient;
    NSCache *cache;
    CDEDirectoryContentsCallback directoryContentsCallback;
    CDECompletionBlock  completionCallback;
    CDEAsynchronousTaskCallbackBlock retryCallbackBlock;
    CDEFileExistenceCallback fileExistenceCallback;
    CDEAsynchronousTaskQueue *taskQueue;
    BOOL fileExists, isDirectory;
    NSDictionary *existingResults;
}

@synthesize session = session;

- (instancetype)initWithSession:(DBSession *)newSession
{
    self = [super init];
    if (self) {
        session = newSession;
        restClient = [[DBRestClient alloc] initWithSession:[DBSession sharedSession]];
        restClient.delegate = self;
        cache = [[NSCache alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [restClient cancelAllRequests];
}

#pragma mark Connecting

- (BOOL)isConnected
{
    return self.session.isLinked;
}

- (void)connect:(CDECompletionBlock)completion
{
    if (self.isConnected) {
        if (completion) completion(nil);
    }
    else if ([self.delegate respondsToSelector:@selector(linkSessionForDropboxCloudFileSystem:completion:)]) {
        [self.delegate linkSessionForDropboxCloudFileSystem:self completion:completion];
    }
    else {
        NSError *error = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeConnectionError userInfo:nil];
        if (completion) completion(error);
    }
}

#pragma mark - User Identity

- (id <NSObject, NSCoding, NSCopying>)identityToken
{
    return self.session.userIds > 0 ? self.session.userIds[0] : nil;
}

#pragma mark Checking File Existence

- (void)fileExistsAtPath:(NSString *)path completion:(CDEFileExistenceCallback)block
{
    fileExists = NO;
    isDirectory = NO;
    fileExistenceCallback = [block copy];
    taskQueue = [[CDEAsynchronousTaskQueue alloc] initWithTask:^(CDEAsynchronousTaskCallbackBlock next) {
            retryCallbackBlock = [next copy];
            [restClient loadMetadata:path];
        }
        repeatCount:kCDENumberOfRetriesForFailedAttempt
        terminationPolicy:CDETaskQueueTerminationPolicyStopOnSuccess
        completion:^(NSError *error) {
            fileExistenceCallback(fileExists, isDirectory, error);
            retryCallbackBlock = NULL;
        }
    ];
    [taskQueue start];
}

#pragma mark Getting Directory Contents

- (void)contentsOfDirectoryAtPath:(NSString *)path completion:(void(^)(NSArray *contents, NSError *error))block
{
    directoryContentsCallback = [block copy];
    existingResults = [cache objectForKey:@"path"];
    NSString *hash = existingResults[@"hash"];
    if (hash) {
        [restClient loadMetadata:path withHash:hash];
    }
    else {
        [restClient loadMetadata:path];
    }
}

#pragma mark Creating Directories

- (void)createDirectoryAtPath:(NSString *)path completion:(CDECompletionBlock)block
{
    completionCallback = [block copy];
    [restClient createFolder:path];
}

#pragma mark Moving and Copying

- (void)moveItemAtPath:(NSString *)fromPath toPath:(NSString *)toPath completion:(CDECompletionBlock)block
{
    completionCallback = [block copy];
    [restClient moveFrom:fromPath toPath:toPath];
}

- (void)copyItemAtPath:(NSString *)fromPath toPath:(NSString *)toPath completion:(CDECompletionBlock)block
{
    completionCallback = [block copy];
    [restClient copyFrom:fromPath toPath:toPath];
}

#pragma mark Deleting

- (void)removeItemAtPath:(NSString *)path completion:(CDECompletionBlock)block
{
    completionCallback = [block copy];
    [restClient deletePath:path];
}

#pragma mark Uploading and Downloading

- (void)uploadLocalFile:(NSString *)fromPath toPath:(NSString *)toPath completion:(CDECompletionBlock)block
{
    completionCallback = [block copy];
    [restClient uploadFile:[toPath lastPathComponent] toPath:[toPath stringByDeletingLastPathComponent] withParentRev:nil fromPath:fromPath];
}

- (void)downloadFromPath:(NSString *)fromPath toLocalFile:(NSString *)toPath completion:(CDECompletionBlock)block
{
    completionCallback = [block copy];
    [restClient loadFile:fromPath atRev:nil intoPath:toPath];
}

#pragma DBRestClientDelegate methods

- (void)restClient:(DBRestClient *)client loadedMetadata:(DBMetadata *)metadata
{
    if (fileExistenceCallback) {
        fileExists = !metadata.isDeleted;
        isDirectory = metadata.isDirectory;
        retryCallbackBlock(nil, YES);
    }
    else if (directoryContentsCallback) {
        CDECloudDirectory *directory = [CDECloudDirectory new];
        directory.path = metadata.path;
        directory.name = metadata.filename;
        
        NSMutableArray *contents = [[NSMutableArray alloc] initWithCapacity:metadata.contents.count];
        for (DBMetadata *child in metadata.contents) {
            if (child.isDirectory) {
                CDECloudDirectory *dir = [CDECloudDirectory new];
                dir.name = child.filename;
                dir.path = child.path;
                [contents addObject:dir];
            }
            else {
                CDECloudFile *file = [CDECloudFile new];
                file.name = child.filename;
                file.path = child.path;
                file.size = child.totalBytes;
                [contents addObject:file];
            }
        }
        directory.contents = contents;
    
        NSDictionary *dict = @{@"hash":metadata.hash, @"directory":directory};
        [cache setObject:dict forKey:directory.path];
        
        [self performDirectoryContentsCallbackWithResults:directory.contents error:nil];
    }
}

- (void)restClient:(DBRestClient *)client metadataUnchangedAtPath:(NSString *)path
{
    if (directoryContentsCallback) {
        CDECloudDirectory *directory = existingResults[@"directory"];
        [self performDirectoryContentsCallbackWithResults:directory.contents error:nil];
    }
}

- (void)restClient:(DBRestClient *)client loadMetadataFailedWithError:(NSError *)error
{
    if (fileExistenceCallback) {
        if (error.code == 404) {
            fileExists = NO;
            isDirectory = NO;
            retryCallbackBlock(nil, YES);
        }
        else {
            retryCallbackBlock(error, NO);
        }
    }
    else if (directoryContentsCallback) {
        [self performDirectoryContentsCallbackWithResults:nil error:error];
    }
}

- (void)restClient:(DBRestClient *)client createdFolder:(DBMetadata *)folder
{
    [self performCompletionCallbackWithError:nil];
}

- (void)restClient:(DBRestClient *)client createFolderFailedWithError:(NSError *)error
{
    [self performCompletionCallbackWithError:error];
}

- (void)restClient:(DBRestClient *)client deletedPath:(NSString *)path
{
    [self performCompletionCallbackWithError:nil];
}

- (void)restClient:(DBRestClient *)client deletePathFailedWithError:(NSError *)error
{
    [self performCompletionCallbackWithError:error];
}

- (void)restClient:(DBRestClient *)client movedPath:(NSString *)from_path to:(DBMetadata *)result
{
    [self performCompletionCallbackWithError:nil];
}

- (void)restClient:(DBRestClient *)client movePathFailedWithError:(NSError *)error
{
    [self performCompletionCallbackWithError:error];
}

- (void)restClient:(DBRestClient *)client copiedPath:(NSString *)fromPath to:(DBMetadata *)to
{
    [self performCompletionCallbackWithError:nil];
}

- (void)restClient:(DBRestClient *)client copyPathFailedWithError:(NSError *)error
{
    [self performCompletionCallbackWithError:error];
}

- (void)restClient:(DBRestClient *)client uploadedFile:(NSString *)destPath from:(NSString *)srcPath
{
    [self performCompletionCallbackWithError:nil];
}

- (void)restClient:(DBRestClient *)client uploadFileFailedWithError:(NSError *)error
{
    [self performCompletionCallbackWithError:error];
}

- (void)restClient:(DBRestClient *)client loadedFile:(NSString *)destPath
{
    [self performCompletionCallbackWithError:nil];
}

- (void)restClient:(DBRestClient *)client loadFileFailedWithError:(NSError *)error
{
    [self performCompletionCallbackWithError:error];
}

- (void)performCompletionCallbackWithError:(NSError *)error
{
    // Use a local, in case callback schedules another operation
    // and causes completionCallback to be reassigned
    CDECompletionBlock block = completionCallback;
    completionCallback = NULL;
    if (block) block(error);
}

- (void)performDirectoryContentsCallbackWithResults:(id)results error:(NSError *)error
{
    // Use a local var to prevent premature release of block
    CDEDirectoryContentsCallback block = directoryContentsCallback;
    directoryContentsCallback = NULL;
    if (block) block(results, error);
    existingResults = nil;
}

@end
