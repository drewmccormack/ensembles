//
//  CDEDropboxCloudFileSystem.m
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


#pragma mark - File Operations

@interface CDEDropboxOperation : NSOperation <DBRestClientDelegate>

@property (readonly) DBSession *session;
@property (readonly) DBRestClient *restClient;

- (id)initWithSession:(DBSession *)newSession;

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

@interface CDEDropboxMoveItemOperation : CDEDropboxOperation

@property (readonly) NSString *fromPath, *toPath;
@property (readonly) CDECompletionBlock completionCallback;

- (id)initWithSession:(DBSession *)newSession fromPath:(NSString *)newFromPath toPath:(NSString *)newToPath completionCallback:(CDECompletionBlock)block;

@end

@interface CDEDropboxCopyItemOperation : CDEDropboxOperation

@property (readonly) NSString *fromPath, *toPath;
@property (readonly) CDECompletionBlock completionCallback;

- (id)initWithSession:(DBSession *)newSession fromPath:(NSString *)newFromPath toPath:(NSString *)newToPath completionCallback:(CDECompletionBlock)block;

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

#pragma mark Moving and Copying

- (void)moveItemAtPath:(NSString *)fromPath toPath:(NSString *)toPath completion:(CDECompletionBlock)block
{
    CDEDropboxMoveItemOperation *operation = [[CDEDropboxMoveItemOperation alloc] initWithSession:session fromPath:fromPath toPath:toPath completionCallback:block];
    [queue addOperation:operation];
}

- (void)copyItemAtPath:(NSString *)fromPath toPath:(NSString *)toPath completion:(CDECompletionBlock)block
{
    CDEDropboxCopyItemOperation *operation = [[CDEDropboxCopyItemOperation alloc] initWithSession:session fromPath:fromPath toPath:toPath completionCallback:block];
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

- (BOOL)isConcurrent
{
    return YES;
}

- (BOOL)isExecuting
{
    @synchronized (self) {
        return isExecuting;
    }
}

- (BOOL)isFinished
{
    @synchronized (self) {
        return isFinished;
    }
}

- (BOOL)setupForStart
{
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:@selector(start) withObject:nil waitUntilDone:NO];
        return NO;
    }
    
    @synchronized (self) {
        [self willChangeValueForKey:@"isFinished"];
        [self willChangeValueForKey:@"isExecuting"];
        isFinished = NO;
        isExecuting = YES;
        [self didChangeValueForKey:@"isExecuting"];
        [self didChangeValueForKey:@"isFinished"];
    }
    
    return YES;
}

- (void)tearDown
{
    [restClient cancelAllRequests];
    
    @synchronized (self) {
        [self willChangeValueForKey:@"isFinished"];
        [self willChangeValueForKey:@"isExecuting"];
        isFinished = YES;
        isExecuting = NO;
        [self didChangeValueForKey:@"isExecuting"];
        [self didChangeValueForKey:@"isFinished"];
    }
}

@end


@implementation CDEDropboxFileExistenceOperation {
    CDEAsynchronousTaskCallbackBlock retryCallbackBlock;
    CDEAsynchronousTaskQueue *taskQueue;
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

- (void)start
{
    BOOL setup = [self setupForStart];
    if (!setup) return;
    
    fileExists = NO;
    isDirectory = NO;
    taskQueue = [[CDEAsynchronousTaskQueue alloc] initWithTask:^(CDEAsynchronousTaskCallbackBlock next) {
            retryCallbackBlock = [next copy];
            [self.restClient loadMetadata:path];
        }
        repeatCount:kCDENumberOfRetriesForFailedAttempt
        terminationPolicy:CDETaskQueueTerminationPolicyStopOnSuccess
        completion:^(NSError *error) {
            fileExistenceCallback(fileExists, isDirectory, error);
            retryCallbackBlock = NULL;
            [self tearDown];
        }];
    [taskQueue start];
}

- (void)restClient:(DBRestClient *)client loadedMetadata:(DBMetadata *)metadata
{
    fileExists = !metadata.isDeleted;
    isDirectory = metadata.isDirectory;
    retryCallbackBlock(nil, YES);
}

- (void)restClient:(DBRestClient *)client loadMetadataFailedWithError:(NSError *)error
{
    if (error.code == 404) {
        fileExists = NO;
        isDirectory = NO;
        retryCallbackBlock(nil, YES);
    }
    else {
        retryCallbackBlock(error, NO);
    }
}

@end


@implementation CDEDropboxDirectoryContentsOperation

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

- (void)start
{
    BOOL setup = [self setupForStart];
    if (!setup) return;
    
    [self.restClient loadMetadata:path];
}

- (void)restClient:(DBRestClient *)client loadedMetadata:(DBMetadata *)metadata
{
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
    directoryContentsCallback(directory.contents, nil);
    
    [self tearDown];
}

- (void)restClient:(DBRestClient *)client loadMetadataFailedWithError:(NSError *)error
{
    directoryContentsCallback(nil, error);
    [self tearDown];
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

- (void)start
{
    BOOL setup = [self setupForStart];
    if (!setup) return;
    
    [self.restClient createFolder:self.path];
}

- (void)restClient:(DBRestClient *)client createdFolder:(DBMetadata *)folder
{
    self.completionCallback(nil);
    [self tearDown];
}

- (void)restClient:(DBRestClient *)client createFolderFailedWithError:(NSError *)error
{
    self.completionCallback(error);
    [self tearDown];
}

@end


@implementation CDEDropboxMoveItemOperation

@synthesize fromPath = fromPath;
@synthesize toPath = toPath;
@synthesize completionCallback = completionCallback;

- (id)initWithSession:(DBSession *)newSession fromPath:(NSString *)newFromPath toPath:(NSString *)newToPath completionCallback:(CDECompletionBlock)newCallback
{
    self = [super initWithSession:newSession];
    if (self) {
        fromPath = [newFromPath copy];
        toPath = [newToPath copy];
        completionCallback = [newCallback copy];
    }
    return self;
}

- (void)start
{
    BOOL setup = [self setupForStart];
    if (!setup) return;
    
    [self.restClient moveFrom:self.fromPath toPath:self.toPath];
}

- (void)restClient:(DBRestClient *)client movedPath:(NSString *)from_path to:(DBMetadata *)result
{
    self.completionCallback(nil);
    [self tearDown];
}

- (void)restClient:(DBRestClient *)client movePathFailedWithError:(NSError *)error
{
    self.completionCallback(error);
    [self tearDown];
}

@end


@implementation CDEDropboxCopyItemOperation

@synthesize fromPath = fromPath;
@synthesize toPath = toPath;
@synthesize completionCallback = completionCallback;

- (id)initWithSession:(DBSession *)newSession fromPath:(NSString *)newFromPath toPath:(NSString *)newToPath completionCallback:(CDECompletionBlock)newCallback
{
    self = [super initWithSession:newSession];
    if (self) {
        fromPath = [newFromPath copy];
        toPath = [newToPath copy];
        completionCallback = [newCallback copy];
    }
    return self;
}

- (void)start
{
    BOOL setup = [self setupForStart];
    if (!setup) return;
    
    [self.restClient copyFrom:self.fromPath toPath:self.toPath];
}

- (void)restClient:(DBRestClient *)client copiedPath:(NSString *)fromPath to:(DBMetadata *)to
{
    self.completionCallback(nil);
    [self tearDown];
}

- (void)restClient:(DBRestClient *)client copyPathFailedWithError:(NSError *)error
{
    self.completionCallback(error);
    [self tearDown];
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

- (void)start
{
    BOOL setup = [self setupForStart];
    if (!setup) return;
    
    [self.restClient deletePath:self.path];
}

- (void)restClient:(DBRestClient *)client deletedPath:(NSString *)path
{
    self.completionCallback(nil);
    [self tearDown];
}

- (void)restClient:(DBRestClient *)client deletePathFailedWithError:(NSError *)error
{
    self.completionCallback(error);
    [self tearDown];
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

- (void)start
{
    BOOL setup = [self setupForStart];
    if (!setup) return;
    
    [self.restClient uploadFile:[toPath lastPathComponent] toPath:[toPath stringByDeletingLastPathComponent] withParentRev:nil fromPath:localPath];
}

- (void)restClient:(DBRestClient *)client uploadedFile:(NSString *)destPath from:(NSString *)srcPath
{
    self.completionCallback(nil);
    [self tearDown];
}

- (void)restClient:(DBRestClient *)client uploadFileFailedWithError:(NSError *)error
{
    self.completionCallback(error);
    [self tearDown];
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

- (void)start
{
    BOOL setup = [self setupForStart];
    if (!setup) return;
    
    [self.restClient loadFile:fromPath atRev:nil intoPath:localPath];
}

- (void)restClient:(DBRestClient *)client loadedFile:(NSString *)destPath
{
    self.completionCallback(nil);
    [self tearDown];
}

- (void)restClient:(DBRestClient *)client loadFileFailedWithError:(NSError *)error
{
    self.completionCallback(error);
    [self tearDown];
}

@end



