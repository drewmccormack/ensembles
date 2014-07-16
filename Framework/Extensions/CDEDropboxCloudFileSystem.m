//
//  CDEDropboxCloudFileSystem.m
//
//  Created by Drew McCormack on 4/12/13.
//  Copyright (c) 2013 The Mental Faculty B.V. All rights reserved.
//

#import "CDEDropboxCloudFileSystem.h"
#import "DBMetadata.h"
#import "DBRestClient.h"

static const NSUInteger kCDENumberOfRetriesForFailedAttempt = 5;

#pragma mark - File Operations

@interface CDEDropboxOperation : CDEAsynchronousOperation <DBRestClientDelegate>

@property (readonly) DBSession *session;
@property (readonly) DBRestClient *restClient;

- (id)initWithSession:(DBSession *)newSession;

- (void)prepareForNetworkRequests;
- (void)initiateNetworkRequest; // Abstract
- (void)completeWithError:(NSError *)error; // Abstract

@end


@interface CDEDropboxFileExistenceOperation : CDEDropboxOperation

@property (readonly) NSString *path;
@property (readonly) CDEFileExistenceCallback fileExistenceCallback;

- (id)initWithSession:(DBSession *)newSession path:(NSString *)newPath fileExistenceCallback:(CDEFileExistenceCallback)callback;

@end

@interface CDEDropboxDirectoryContentsOperation : CDEDropboxOperation

@property (readonly) NSString *path;
@property (readonly) CDEDirectoryContentsCallback directoryContentsCallback;

- (id)initWithSession:(DBSession *)newSession path:(NSString *)newPath directoryContentsCallback:(CDEDirectoryContentsCallback)block;

@end

@interface CDEDropboxCreateDirectoryOperation : CDEDropboxOperation

@property (readonly) NSString *path;
@property (readonly) CDECompletionBlock completionCallback;

- (id)initWithSession:(DBSession *)newSession path:(NSString *)newPath completionCallback:(CDECompletionBlock)block;

@end

@interface CDEDropboxRemoveItemOperation : CDEDropboxOperation

@property (readonly) NSString *path;
@property (readonly) CDECompletionBlock completionCallback;

- (id)initWithSession:(DBSession *)newSession path:(NSString *)newPath completionCallback:(CDECompletionBlock)block;

@end

@interface CDEDropboxUploadOperation : CDEDropboxOperation

@property (readonly) NSString *localPath, *toPath;
@property (readonly) CDECompletionBlock completionCallback;

- (id)initWithSession:(DBSession *)newSession localPath:(NSString *)newLocalPath toPath:(NSString *)newToPath completionCallback:(CDECompletionBlock)block;

@end

@interface CDEDropboxDownloadOperation : CDEDropboxOperation

@property (readonly) NSString *localPath, *fromPath;
@property (readonly) CDECompletionBlock completionCallback;

- (id)initWithSession:(DBSession *)newSession fromPath:(NSString *)fromPath localPath:(NSString *)newLocalPath completionCallback:(CDECompletionBlock)block;

@end


#pragma mark - Main Class

@implementation CDEDropboxCloudFileSystem {
    NSOperationQueue *queue;
}

@synthesize session = session;

- (instancetype)initWithSession:(DBSession *)newSession
{
    self = [super init];
    if (self) {
        session = newSession;
        queue = [[NSOperationQueue alloc] init];
        queue.maxConcurrentOperationCount = 1;
    }
    return self;
}

- (void)dealloc
{
    [queue cancelAllOperations];
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
    return self.session.userIds.count > 0 ? self.session.userIds[0] : nil;
}

#pragma mark Checking File Existence

- (void)fileExistsAtPath:(NSString *)path completion:(CDEFileExistenceCallback)block
{
    CDEDropboxFileExistenceOperation *operation = [[CDEDropboxFileExistenceOperation alloc] initWithSession:session path:path fileExistenceCallback:block];
    [queue addOperation:operation];
}

#pragma mark Getting Directory Contents

- (void)contentsOfDirectoryAtPath:(NSString *)path completion:(CDEDirectoryContentsCallback)block
{
    CDEDropboxDirectoryContentsOperation *operation = [[CDEDropboxDirectoryContentsOperation alloc] initWithSession:session path:path directoryContentsCallback:block];
    [queue addOperation:operation];
}

#pragma mark Creating Directories

- (void)createDirectoryAtPath:(NSString *)path completion:(CDECompletionBlock)block
{
    CDEDropboxCreateDirectoryOperation *operation = [[CDEDropboxCreateDirectoryOperation alloc] initWithSession:session path:path completionCallback:block];
    [queue addOperation:operation];
}

#pragma mark Deleting

- (void)removeItemAtPath:(NSString *)path completion:(CDECompletionBlock)block
{
    CDEDropboxRemoveItemOperation *operation = [[CDEDropboxRemoveItemOperation alloc] initWithSession:session path:path completionCallback:block];
    [queue addOperation:operation];
}

#pragma mark Uploading and Downloading

- (void)uploadLocalFile:(NSString *)fromPath toPath:(NSString *)toPath completion:(CDECompletionBlock)block
{
    CDEDropboxUploadOperation *operation = [[CDEDropboxUploadOperation alloc] initWithSession:session localPath:fromPath toPath:toPath completionCallback:block];
    [queue addOperation:operation];
}

- (void)downloadFromPath:(NSString *)fromPath toLocalFile:(NSString *)toPath completion:(CDECompletionBlock)block
{
    CDEDropboxDownloadOperation *operation = [[CDEDropboxDownloadOperation alloc] initWithSession:session fromPath:fromPath localPath:toPath completionCallback:block];
    [queue addOperation:operation];
}

@end


@implementation CDEDropboxOperation {
    CDEAsynchronousTaskQueue *taskQueue;
    CDEAsynchronousTaskCallbackBlock retryCallbackBlock;
    BOOL isFinished, isExecuting;
}

@synthesize session = session;
@synthesize restClient = restClient;

- (instancetype)initWithSession:(DBSession *)newSession
{
    self = [super init];
    if (self) {
        session = newSession;
        restClient = [[DBRestClient alloc] initWithSession:newSession];;
        restClient.delegate = self;
    }
    return self;
}

- (void)beginAsynchronousTask
{
    [self prepareForNetworkRequests];
    taskQueue = [[CDEAsynchronousTaskQueue alloc] initWithTask:^(CDEAsynchronousTaskCallbackBlock next) {
            CDELog(CDELoggingLevelVerbose, @"Attempting network request for operation class: %@", NSStringFromClass(self.class));
            retryCallbackBlock = [next copy];
            [self initiateNetworkRequest];
        }
        repeatCount:kCDENumberOfRetriesForFailedAttempt
        terminationPolicy:CDETaskQueueTerminationPolicyStopOnSuccess
        completion:^(NSError *error) {
            if (error) CDELog(CDELoggingLevelVerbose, @"Cloud file system operation failed: %@ %@", NSStringFromClass(self.class), error);
            [self completeWithError:error];
            retryCallbackBlock = NULL;
            [self endAsynchronousTask];
        }];
    [taskQueue start];
}

- (void)endAsynchronousTask
{
    [restClient cancelAllRequests];
    [super endAsynchronousTask];
}

- (void)prepareForNetworkRequests
{
}

- (void)initiateNetworkRequest
{
    [self doesNotRecognizeSelector:_cmd];
}

- (void)completeNetworkRequestWithError:(NSError *)error
{
    if (error) CDELog(CDELoggingLevelVerbose, @"Network request failed with error: %@ %@", NSStringFromClass(self.class), error);
    retryCallbackBlock(error, NO);
}

- (void)completeWithError:(NSError *)error
{
    [self doesNotRecognizeSelector:_cmd];
}

@end


@implementation CDEDropboxFileExistenceOperation {
    BOOL fileExists, isDirectory;
}

@synthesize fileExistenceCallback = fileExistenceCallback;
@synthesize path = path;

- (instancetype)initWithSession:(DBSession *)newSession path:(NSString *)newPath fileExistenceCallback:(CDEFileExistenceCallback)newCallback
{
    self = [super initWithSession:newSession];
    if (self) {
        path = [newPath copy];
        fileExistenceCallback = [newCallback copy];
    }
    return self;
}

- (void)prepareForNetworkRequests
{
    fileExists = NO;
    isDirectory = NO;
}

- (void)initiateNetworkRequest
{
    [self.restClient loadMetadata:path];
}

- (void)completeWithError:(NSError *)error
{
    fileExistenceCallback(fileExists, isDirectory, error);
}

- (void)restClient:(DBRestClient *)client loadedMetadata:(DBMetadata *)metadata
{
    fileExists = !metadata.isDeleted;
    isDirectory = metadata.isDirectory;
    [self completeNetworkRequestWithError:nil];
}

- (void)restClient:(DBRestClient *)client loadMetadataFailedWithError:(NSError *)error
{
    if (error.code == 404) {
        fileExists = NO;
        isDirectory = NO;
        [self completeNetworkRequestWithError:nil];
    }
    else {
        [self completeNetworkRequestWithError:error];
    }
}

@end


@implementation CDEDropboxDirectoryContentsOperation {
    CDECloudDirectory *directory;
}

@synthesize path = path;
@synthesize directoryContentsCallback = directoryContentsCallback;

- (id)initWithSession:(DBSession *)newSession path:(NSString *)newPath directoryContentsCallback:(CDEDirectoryContentsCallback)newCallback
{
    self = [super initWithSession:newSession];
    if (self) {
        path = [newPath copy];
        directoryContentsCallback = [newCallback copy];
    }
    return self;
}

- (void)initiateNetworkRequest
{
    [self.restClient loadMetadata:path];
}

- (void)completeWithError:(NSError *)error
{
    directoryContentsCallback(directory.contents, error);
}

- (void)restClient:(DBRestClient *)client loadedMetadata:(DBMetadata *)metadata
{
    directory = [CDECloudDirectory new];
    directory.path = metadata.path;
    directory.name = metadata.filename;
    
    NSMutableArray *contents = [[NSMutableArray alloc] initWithCapacity:metadata.contents.count];
    for (DBMetadata *child in metadata.contents) {
        // Dropbox inserts parenthesized indexes when two files with
        // same name are uploaded. Ignore these files.
        if ([child.filename rangeOfString:@")"].location != NSNotFound) continue;
        
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
    [self completeNetworkRequestWithError:nil];
}

- (void)restClient:(DBRestClient *)client loadMetadataFailedWithError:(NSError *)error
{
    directory = nil;
    [self completeNetworkRequestWithError:error];
}

@end


@implementation CDEDropboxCreateDirectoryOperation

@synthesize path = path;
@synthesize completionCallback = completionCallback;

- (id)initWithSession:(DBSession *)newSession path:(NSString *)newPath completionCallback:(CDECompletionBlock)newCallback
{
    self = [super initWithSession:newSession];
    if (self) {
        path = [newPath copy];
        completionCallback = [newCallback copy];
    }
    return self;
}

- (void)initiateNetworkRequest
{
    [self.restClient createFolder:self.path];
}

- (void)completeWithError:(NSError *)error
{
    self.completionCallback(error);
}

- (void)restClient:(DBRestClient *)client createdFolder:(DBMetadata *)folder
{
    [self completeNetworkRequestWithError:nil];
}

- (void)restClient:(DBRestClient *)client createFolderFailedWithError:(NSError *)error
{
    [self completeNetworkRequestWithError:error];
}

@end


@implementation CDEDropboxRemoveItemOperation

@synthesize path = path;
@synthesize completionCallback = completionCallback;

- (id)initWithSession:(DBSession *)newSession path:(NSString *)newPath completionCallback:(CDECompletionBlock)newCallback
{
    self = [super initWithSession:newSession];
    if (self) {
        path = [newPath copy];
        completionCallback = [newCallback copy];
    }
    return self;
}

- (void)initiateNetworkRequest
{
    [self.restClient deletePath:self.path];
}

- (void)completeWithError:(NSError *)error
{
    self.completionCallback(error);
}

- (void)restClient:(DBRestClient *)client deletedPath:(NSString *)path
{
    [self completeNetworkRequestWithError:nil];
}

- (void)restClient:(DBRestClient *)client deletePathFailedWithError:(NSError *)error
{
    [self completeNetworkRequestWithError:error];
}

@end


@implementation CDEDropboxUploadOperation

@synthesize localPath = localPath;
@synthesize toPath = toPath;
@synthesize completionCallback = completionCallback;

- (id)initWithSession:(DBSession *)newSession localPath:(NSString *)newLocalPath toPath:(NSString *)newToPath completionCallback:(CDECompletionBlock)newCallback
{
    self = [super initWithSession:newSession];
    if (self) {
        localPath = [newLocalPath copy];
        toPath = [newToPath copy];
        completionCallback = [newCallback copy];
    }
    return self;
}

- (void)initiateNetworkRequest
{
    [self.restClient uploadFile:[toPath lastPathComponent] toPath:[toPath stringByDeletingLastPathComponent] withParentRev:nil fromPath:localPath];
}

- (void)completeWithError:(NSError *)error
{
    self.completionCallback(error);
}

- (void)restClient:(DBRestClient *)client uploadedFile:(NSString *)destPath from:(NSString *)srcPath
{
    [self completeNetworkRequestWithError:nil];
}

- (void)restClient:(DBRestClient *)client uploadFileFailedWithError:(NSError *)error
{
    [self completeNetworkRequestWithError:error];
}

@end


@implementation CDEDropboxDownloadOperation

@synthesize localPath = localPath;
@synthesize fromPath = fromPath;
@synthesize completionCallback = completionCallback;

- (id)initWithSession:(DBSession *)newSession fromPath:(NSString *)newFromPath localPath:(NSString *)newLocalPath completionCallback:(CDECompletionBlock)block
{
    self = [super initWithSession:newSession];
    if (self) {
        localPath = [newLocalPath copy];
        fromPath = [newFromPath copy];
        completionCallback = [block copy];
    }
    return self;
}

- (void)initiateNetworkRequest
{
    [self.restClient loadFile:fromPath atRev:nil intoPath:localPath];
}

- (void)completeWithError:(NSError *)error
{
    self.completionCallback(error);
}

- (void)restClient:(DBRestClient *)client loadedFile:(NSString *)destPath
{
    [self completeNetworkRequestWithError:nil];
}

- (void)restClient:(DBRestClient *)client loadFileFailedWithError:(NSError *)error
{
    [self completeNetworkRequestWithError:error];
}

@end



