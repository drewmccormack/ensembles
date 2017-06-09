//
//  CDEDropboxV2CloudFileSystem.m
//
//  Created by Drew McCormack on 12/09/16.
//  Copyright (c) 2016 The Mental Faculty B.V. All rights reserved.
//

#import "CDEDropboxV2CloudFileSystem.h"
#import <ObjectiveDropboxOfficial/ObjectiveDropboxOfficial.h>

static const NSUInteger kCDENumberOfRetriesForFailedAttempt = 5;

#pragma mark - Main Class

@interface CDEDropboxV2CloudFileSystem ()
@end


@implementation CDEDropboxV2CloudFileSystem

@synthesize client;

- (instancetype)init
{
    if ((self = [super init])) {
        client = [DBClientsManager authorizedClient];
    }
    return self;
}

- (NSError *)errorForRouteError:(NSObject * _Nullable)routeError requestError:(DBRequestError * _Nullable)requestError result:(NSObject * _Nullable)result
{
    NSError *error = nil;
    // It's not likely that no error will arrive if result is nil. However, we handle this case as well (where all params are nil) to stay on the safe side. (so we leave no scneario where we miss an error, even when no error is reported)
    if (routeError || requestError || !result) {
        if (requestError.nsError) {
            error = [requestError.nsError copy];
        }
        else {
            NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
            if (routeError) [userInfo setObject:routeError.description forKey:@"routeError"];
            if (requestError) [userInfo setObject:requestError.description forKey:@"requestError"];
            error = [[NSError alloc] initWithDomain:CDEErrorDomain code:CDEErrorCodeNetworkError userInfo:userInfo];
        }
    }
    return error;
}

- (nullable DBUserClient *)authorizedClient
{
    // Always fallback to the most recently authorized client
    return client ?: [DBClientsManager authorizedClient];
}

+ (NSError *)genericAuthorizationError
{
    return [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeAuthenticationFailure userInfo:nil];
}

+ (NSError *)unknownError
{
    return [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeUnknown userInfo:nil];
}

#pragma mark Paths

- (void)setRelativePathToRootInDropbox:(NSString *)newPath
{
    if ([newPath hasPrefix:@"/"]) {
        _relativePathToRootInDropbox = newPath;
    }
    else {
        _relativePathToRootInDropbox = [@"/" stringByAppendingString:newPath];
    }
}

- (NSString *)pathIncludingSubfolderForFilePath:(NSString *)path
{
    NSString *newPath = path;

    // Check if path ends with a GUID (32 characters) and located under the 'data' folder
    NSString *dirName = [[path stringByDeletingLastPathComponent] lastPathComponent];
    BOOL isInData = [dirName isEqualToString:@"data"];
    if (path.lastPathComponent.length == 32 && isInData) {
        NSString *guid = path.lastPathComponent;
        NSString *dataSubFolder = [guid substringToIndex:2];
        NSString *dataDir = [path stringByDeletingLastPathComponent];
        NSString *subDir = [dataDir stringByAppendingPathComponent:dataSubFolder];
        newPath = [subDir stringByAppendingPathComponent:guid];
    }

    return newPath;
}

- (NSString *)fullDropboxPathForPath:(NSString *)path
{
    if (self.relativePathToRootInDropbox) {
        path = [self.relativePathToRootInDropbox stringByAppendingPathComponent:path];
    }

    if (self.partitionDataFilesBetweenSubdirectories) {
        path = [self pathIncludingSubfolderForFilePath:path];
    }
    
    if ([path isEqualToString:@"/"]) {
        path = @""; // API expects empty string here
    }

    return path;
}

- (NSArray<NSString *> *)fullDropboxPathsForPaths:(NSArray *)paths
{
    if (self.relativePathToRootInDropbox) {
        paths = [paths cde_arrayByTransformingObjectsWithBlock:^(NSString *path) {
            return [self fullDropboxPathForPath:path];
        }];
    }
    return paths;
}


#pragma mark Connecting

- (BOOL)isConnected
{
    return [self authorizedClient] != nil;
}

- (void)connect:(CDECompletionBlock)completion
{
    if (self.isConnected) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(nil);
        });
    }
    else if ([self.delegate respondsToSelector:@selector(linkSessionForDropboxCloudFileSystem:completion:)]) {
        [self.delegate linkSessionForDropboxCloudFileSystem:self completion:completion];
    }
    else {
        NSError *error = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeConnectionError userInfo:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(error);
        });
    }
}


#pragma mark User Identity

- (id <NSObject, NSCopying, NSCoding>) identityToken {
    // Tried to get proper account name, but it is an async call, and troublesome with this API.
    return @"DropboxUser";
}


#pragma mark Checking File Existence

- (void)fileExistsAtPath:(NSString *)path completion:(CDEFileExistenceCallback)block
{
    DBUserClient *authorizedClient = [self authorizedClient];
    if (!authorizedClient) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (block) block(NO, NO, [[self class] genericAuthorizationError]);
        });
        return;
    }
    DBRpcTask *task = [authorizedClient.filesRoutes getMetadata:[self fullDropboxPathForPath:path]];
    task.retryCount = kCDENumberOfRetriesForFailedAttempt;
    [task setResponseBlock:^(DBFILESMetadata * _Nullable metadata, DBFILESGetMetadataError * _Nullable routeError, DBRequestError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (metadata) {
                if ([metadata isKindOfClass:[DBFILESFileMetadata class]]) {
                    if (block) block(/*exist*/YES, /*isDirectory*/NO, /*error*/nil);
                } else if ([metadata isKindOfClass:[DBFILESFolderMetadata class]]) {
                    if (block) block(/*exist*/YES, /*isDirectory*/YES, /*error*/nil);
                } else if ([metadata isKindOfClass:[DBFILESDeletedMetadata class]]) {
                    if (block) block(/*exist*/NO, /*isDirectory*/NO, /*error*/nil);
                }
            } else {
                if ([routeError isPath] && routeError.path.isNotFound) {
                    if (block) block(/*exist*/NO, /*isDirectory*/NO, /*error*/nil);
                } else {
                    if (block) block(/*exist*/NO, /*isDirectory*/NO, /*error*/[self errorForRouteError:routeError requestError:error result:metadata]);
                }
            }
        });
    }];
}


#pragma mark Getting Directory Contents

- (void)contentsOfDirectoryAtPath:(NSString *)path completion:(CDEDirectoryContentsCallback)block
{
    DBUserClient *authorizedClient = [self authorizedClient];
    if (!authorizedClient) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (block) block(nil, [[self class] genericAuthorizationError]);
        });
        return;
    }
    BOOL recursive = self.partitionDataFilesBetweenSubdirectories && [path.lastPathComponent isEqualToString:@"data"];
    DBRpcTask *task = [authorizedClient.filesRoutes listFolder:[self fullDropboxPathForPath:path]
                                                     recursive:@(recursive)
                                              includeMediaInfo:@(NO)
                                                includeDeleted:@(NO)
                               includeHasExplicitSharedMembers:@(NO)];
    task.retryCount = kCDENumberOfRetriesForFailedAttempt;
    [task setResponseBlock:^(DBFILESListFolderResult * _Nullable result, DBFILESListFolderError * _Nullable routeError, DBRequestError * _Nullable error) {
        if (routeError) CDELog(CDELoggingLevelError, @"Dropbox: routeError in listFolder: %@\npath: %@", routeError, path);
        else if (error) CDELog(CDELoggingLevelError, @"Dropbox: error in listFolder: %@\npath: %@", error, path);
        if (!result) {
            [self handleLoadContentOfDirectoryFailedWithCompletion:block error:[self errorForRouteError:routeError requestError:error result:result]];
            return;
        }
        // Load directory content
        CDECloudDirectory *directory = [CDECloudDirectory new];
        directory.contents = @[];
        [self loadContentOfDirectory:directory withEntries:result.entries atDirectoryfullDropboxPath:[self fullDropboxPathForPath:path]];
        
        // Check if more content is available
        if (result.hasMore.boolValue) {
            // More content is available - get it
            [self listFolderContinueWithAuthorizedClient:authorizedClient
                                               directory:directory
                              atDirectoryfullDropboxPath:[self fullDropboxPathForPath:path]
                                                  cursor:result.cursor
                                              completion:block];
        }
        else {
            // list folder is completed
            [self handleLoadContentOfDirectory:directory finishedWithCompletion:block];
        }
    }];
}

- (void)listFolderContinueWithAuthorizedClient:(DBUserClient *)authorizedClient directory:(CDECloudDirectory *)directory atDirectoryfullDropboxPath:(NSString *)directoryfullDropboxPath cursor:(NSString *)cursor completion:(CDEDirectoryContentsCallback)block
{
    DBRpcTask *task = [authorizedClient.filesRoutes listFolderContinue:cursor];
    task.retryCount = kCDENumberOfRetriesForFailedAttempt;
    [task setResponseBlock:^(DBFILESListFolderResult *result, DBFILESListFolderContinueError * _Nullable routeError, DBRequestError * _Nullable error) {
        if (routeError) CDELog(CDELoggingLevelError, @"Dropbox: routeError in listFolderContinue: %@\ndirectoryfullDropboxPath: %@", routeError, directoryfullDropboxPath);
        else if (error) CDELog(CDELoggingLevelError, @"Dropbox: error in listFolderContinue: %@\ndirectoryfullDropboxPath: %@", error, directoryfullDropboxPath);
        if (!result) {
            [self handleLoadContentOfDirectoryFailedWithCompletion:block error:[self errorForRouteError:routeError requestError:error result:result]];
            return;
        }
        // Load directory content
        [self loadContentOfDirectory:directory withEntries:result.entries atDirectoryfullDropboxPath:directoryfullDropboxPath];
        
        // Check if more content is available
        if (result.hasMore.boolValue) {
            // More content is available - get it recursively
            [self listFolderContinueWithAuthorizedClient:authorizedClient
                                               directory:directory
                              atDirectoryfullDropboxPath:directoryfullDropboxPath
                                                  cursor:result.cursor
                                              completion:block];
        }
        else {
            // List folder content completed
            [self handleLoadContentOfDirectory:directory finishedWithCompletion:block];
        }
    }];
}

- (void)loadContentOfDirectory:(CDECloudDirectory *)directory withEntries:(NSArray<DBFILESMetadata *> *)entries atDirectoryfullDropboxPath:(NSString *)directoryfullDropboxPath
{
    for (DBFILESMetadata *child in entries) {
        // Dropbox inserts parenthesized indexes when two files with
        // same name are uploaded. Ignore these files.
        if ([child.name rangeOfString:@")"].location != NSNotFound) continue;
        
        // When partitionDataFilesBetweenSubdirectories flag is set, two-letter subfolders under "data" are used to hold the actual data files.
        // Ignore these subfolders.
        if (self.partitionDataFilesBetweenSubdirectories) {
            NSString *parentDirPath = [child.pathLower stringByDeletingLastPathComponent].lastPathComponent;
            if ([parentDirPath isEqualToString:@"data"]) continue;
        }
        id item = nil;
        if ([child isKindOfClass:[DBFILESFolderMetadata class]]) {
            CDECloudDirectory *subdir = [CDECloudDirectory new];
            subdir.name = child.name;
            // Use pathLower rather than pathDisplay property since we need path for functionality rather than display purposes (see property documentation)
            subdir.path = child.pathLower;
            item = subdir;
        } else if ([child isKindOfClass:[DBFILESFileMetadata class]]) {
            CDECloudFile *file = [CDECloudFile new];
            file.name = child.name;
            // Use pathLower rather than pathDisplay property since we need path for functionality rather than display purposes (see property documentation)
            file.path = child.pathLower;
            file.size = ((DBFILESFileMetadata *)child).size.unsignedLongLongValue;
            item = file;
        } else {
            // Even though includeDeleted is NO in the previously invoked [listFolder] method, DBFILESDeletedMetadata objects are still expected in case files were deleted after method invokation. See https://www.dropboxforum.com/t5/API-support/DBFILESUserAuthRoutes-listFolderContinue-returns-deleted-files/m-p/221985#M11817
            continue;
        }
        // Detect the topmost directory (use lowercase strings to avoid case sensitive compare issues)
        if ([[item path].lowercaseString isEqualToString:directoryfullDropboxPath.lowercaseString]) {
            [directory setName:[item name]];
            [directory setPath:[item path]];
            continue;
        }
        directory.contents = [directory.contents arrayByAddingObject:item];
    }
}

- (void)handleLoadContentOfDirectory:(CDECloudDirectory *)directory finishedWithCompletion:(CDEDirectoryContentsCallback)block
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (block) block(directory.contents, nil);
    });
}

- (void)handleLoadContentOfDirectoryFailedWithCompletion:(CDEDirectoryContentsCallback)block error:(NSError * _Nullable)error
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (block) block(nil, error);
    });
}


#pragma mark Creating Directories

- (void)createDirectoryAtPath:(NSString *)path completion:(CDECompletionBlock)block
{
    DBUserClient *authorizedClient = [self authorizedClient];
    if (!authorizedClient) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (block) block([[self class] genericAuthorizationError]);
        });
        return;
    }
    DBRpcTask *task = [authorizedClient.filesRoutes createFolder:[self fullDropboxPathForPath:path]];
    task.retryCount = kCDENumberOfRetriesForFailedAttempt;
    [task setResponseBlock:^(DBFILESFolderMetadata * _Nullable metadata, DBFILESCreateFolderError * _Nullable routeError, DBRequestError * _Nullable error) {
        if (routeError) CDELog(CDELoggingLevelError, @"Dropbox: routeError in createFolder: %@\npath: %@", routeError, path);
        else if (error) CDELog(CDELoggingLevelError, @"Dropbox: error in createFolder: %@\npath: %@", error, path);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (block) block([self errorForRouteError:routeError requestError:error result:metadata]);
        });
    }];
}


#pragma mark Deleting

- (void)removeItemsAtPaths:(NSArray *)paths completion:(CDECompletionBlock)block
{
    DBUserClient *authorizedClient = [self authorizedClient];
    if (!authorizedClient) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (block) block([[self class] genericAuthorizationError]);
        });
        return;
    }
    if (paths.count == 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            block(nil);
        });
        return;
    }
    NSMutableArray<DBFILESDeleteArg *> *filesToDelete = [NSMutableArray array];
    for (NSString *path in paths) {
        DBFILESDeleteArg *fileToDelete = [[DBFILESDeleteArg alloc] initWithPath:[self fullDropboxPathForPath:path]];
        [filesToDelete addObject:fileToDelete];
    }
    DBRpcTask *task = [authorizedClient.filesRoutes deleteBatch:filesToDelete];
    task.retryCount = kCDENumberOfRetriesForFailedAttempt;
    [task setResponseBlock:^(DBFILESDeleteBatchLaunch * _Nullable result, DBNilObject * _Nullable routeError, DBRequestError * _Nullable error) {
        if (error) CDELog(CDELoggingLevelError, @"Dropbox: error in deleteBatch: %@\nfilesToDelete: %@", error, filesToDelete);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (block) block([self errorForRouteError:nil requestError:error result:result]);
        });
    }];
}

- (void)removeItemAtPath:(NSString *)path completion:(CDECompletionBlock)block
{
    DBUserClient *authorizedClient = [self authorizedClient];
    if (!authorizedClient) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (block) block([[self class] genericAuthorizationError]);
        });
        return;
    }
    DBRpcTask *task = [authorizedClient.filesRoutes delete_:[self fullDropboxPathForPath:path]];
    task.retryCount = kCDENumberOfRetriesForFailedAttempt;
    [task setResponseBlock:^(DBFILESMetadata * _Nullable metadata, DBFILESDeleteError * _Nullable routeError, DBRequestError * _Nullable error) {
        if (routeError) CDELog(CDELoggingLevelError, @"Dropbox: routeError in delete_: %@\npath: %@", routeError, [self fullDropboxPathForPath:path]);
        else if (error) CDELog(CDELoggingLevelError, @"Dropbox: error in delete_: %@\npath: %@", error, [self fullDropboxPathForPath:path]);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (block) block([self errorForRouteError:routeError requestError:error result:metadata]);
        });
    }];
}


#pragma mark Uploading and Downloading

- (void)uploadLocalFiles:(NSArray *)fromPaths toPaths:(NSArray *)toPaths completion:(CDECompletionBlock)block
{
    DBUserClient *authorizedClient = [self authorizedClient];
    if (!authorizedClient) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (block) block([[self class] genericAuthorizationError]);
        });
        return;
    }
    if (fromPaths.count == 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            block(nil);
        });
        return;
    }
    // DBBatchUploadTask doesn't have retryCount property. Therefore we implement it ourselves.
    [self uploadLocalFiles:fromPaths toPaths:toPaths retryCounter:0 completion:block];
}

- (void)uploadLocalFiles:(NSArray *)fromPaths toPaths:(NSArray *)toPaths retryCounter:(NSUInteger)retryCounter completion:(CDECompletionBlock)block
{
    DBUserClient *authorizedClient = [self authorizedClient];
    if (!authorizedClient) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (block) block([[self class] genericAuthorizationError]);
        });
        return;
    }
    
    NSMutableArray<DBFILESCommitInfo *> *commitInfoFiles = [NSMutableArray array];
    NSMutableArray<NSURL *> *clientSideFileURLs = [NSMutableArray array];
    
    // Build the commit info array of dropbox files
    NSArray<NSString *> *toFullDropboxPaths = [self fullDropboxPathsForPaths:toPaths];
    for (NSString *toFullDropboxPath in toFullDropboxPaths) {
        DBFILESCommitInfo *commitInfo = [[DBFILESCommitInfo alloc] initWithPath:toFullDropboxPath mode:nil autorename:nil clientModified:nil mute:@(YES)];
        [commitInfoFiles addObject:commitInfo];
    }
    // Build the URL array of client side files
    for (NSString *fromPath in fromPaths) {
        NSURL *fromPathURL = [NSURL fileURLWithPath:fromPath];
        [clientSideFileURLs addObject:fromPathURL];
    }
    // Create a dictionary of client side file URLs to commit info files
    NSDictionary<NSURL *, DBFILESCommitInfo *> *clientSideFileURLsToCommitInfoFiles = [NSDictionary dictionaryWithObjects:commitInfoFiles forKeys:clientSideFileURLs];
    [authorizedClient.filesRoutes batchUploadFiles:clientSideFileURLsToCommitInfoFiles
                                   queue:nil
                           progressBlock:nil
                           responseBlock:^(NSDictionary<NSURL *, DBFILESUploadSessionFinishBatchResultEntry *> *fileUrlsToBatchResultEntries, DBASYNCPollError *finishBatchRouteError, DBRequestError *finishBatchRequestError, NSDictionary<NSURL *, DBRequestError *> *fileUrlsToRequestErrors) {
                               if (finishBatchRouteError) CDELog(CDELoggingLevelWarning, @"Dropbox: finishBatchRouteError in batchUploadFiles: %@", finishBatchRouteError);
                               else if (finishBatchRequestError) CDELog(CDELoggingLevelWarning, @"Dropbox: finishBatchRequestError in batchUploadFiles: %@", finishBatchRequestError);
                               else if (fileUrlsToRequestErrors.count > 0) CDELog(CDELoggingLevelWarning, @"Dropbox: fileUrlsToRequestErrors in batchUploadFiles: %@", fileUrlsToRequestErrors);
                               // Check if there are failures
                               BOOL hasFailures = NO;
                               if (fileUrlsToBatchResultEntries) {
                                   for (NSURL *clientSideFileUrl in fileUrlsToBatchResultEntries) {
                                       DBFILESUploadSessionFinishBatchResultEntry *resultEntry = fileUrlsToBatchResultEntries[clientSideFileUrl];
                                       if ([resultEntry isFailure]) {
                                           CDELog(CDELoggingLevelWarning, @"Dropbox: found isFailure in batchUploadFiles");
                                           hasFailures = YES;
                                           break;
                                       }
                                   }
                               }
                               // Check the result
                               if (finishBatchRouteError || finishBatchRequestError || hasFailures || (fileUrlsToRequestErrors.count > 0)) {
                                   // Upload failed
                                   [self handleBatchUploadFailedWithLocalFiles:fromPaths
                                                                       toPaths:toPaths
                                                                  retryCounter:retryCounter
                                                  fileUrlsToBatchResultEntries:fileUrlsToBatchResultEntries
                                                         finishBatchRouteError:finishBatchRouteError
                                                       finishBatchRequestError:finishBatchRequestError
                                                       fileUrlsToRequestErrors:fileUrlsToRequestErrors
                                                                    completion:block];
                               }
                               else {
                                   // Upload succeded
                                   if (retryCounter) {
                                       CDELog(CDELoggingLevelWarning, @"Dropbox: batch upload succeeded: attempt %ld", (long)retryCounter);
                                   }
                                   dispatch_async(dispatch_get_main_queue(), ^{
                                       if (block) block(nil);
                                   });
                               }
                           }];
    
}

- (void)handleBatchUploadFailedWithLocalFiles:(NSArray *)fromPaths toPaths:(NSArray *)toPaths retryCounter:(NSUInteger)retryCounter fileUrlsToBatchResultEntries:(NSDictionary<NSURL *, DBFILESUploadSessionFinishBatchResultEntry *> *)fileUrlsToBatchResultEntries finishBatchRouteError:(DBASYNCPollError *)finishBatchRouteError finishBatchRequestError:(DBRequestError *)finishBatchRequestError fileUrlsToRequestErrors:(NSDictionary<NSURL *, DBRequestError *> *)fileUrlsToRequestErrors completion:(CDECompletionBlock)block
{
    NSMutableOrderedSet<NSString *> *fromPathsToRetry = nil;
    NSMutableOrderedSet<NSString *> *toPathsToRetry = nil;
    
    // Check if we should retry uploading
    NSUInteger updatedRetryCounter = retryCounter + 1;
    if (updatedRetryCounter <= kCDENumberOfRetriesForFailedAttempt) {
        // We should retry uploading - determine which files to upload
        if (finishBatchRouteError || finishBatchRequestError) {
            // All files failed to upload
            fromPathsToRetry = [NSMutableOrderedSet orderedSetWithArray:fromPaths];
            toPathsToRetry = [NSMutableOrderedSet orderedSetWithArray:toPaths];
        }
        else {
            // Only some files failed to upload
            fromPathsToRetry = [NSMutableOrderedSet orderedSet];
            toPathsToRetry = [NSMutableOrderedSet orderedSet];
            NSDictionary<NSString *, NSString *> *clientSideFilePathsToDropboxFilePaths = [NSDictionary dictionaryWithObjects:toPaths forKeys:fromPaths];
            
            // All files in fileUrlsToRequestErrors failed to upload
            if (fileUrlsToRequestErrors.count > 0) {
                for (NSURL *sourceFileURL in fileUrlsToRequestErrors) {
                    [fromPathsToRetry addObject:sourceFileURL.path];
                    [toPathsToRetry addObject:clientSideFilePathsToDropboxFilePaths[sourceFileURL.path]];
                }
            }
            // Need to iterate all entries to determine which file failed to upload (in fileUrlsToBatchResultEntries there are both successful and failure uploads)
            if (fileUrlsToBatchResultEntries) {
                for (NSURL *clientSideFileUrl in fileUrlsToBatchResultEntries) {
                    DBFILESUploadSessionFinishBatchResultEntry *resultEntry = fileUrlsToBatchResultEntries[clientSideFileUrl];
                    if ([resultEntry isFailure]) {
                        [fromPathsToRetry addObject:clientSideFileUrl.path];
                        [toPathsToRetry addObject:clientSideFilePathsToDropboxFilePaths[clientSideFileUrl.path]];
                    }
                }
            }
        }
        CDELog(CDELoggingLevelWarning, @"Dropbox: batch upload failed: attempt %ld. Retrying...\nfromPathsToRetry: %@\ntoPathsToRetry: %@", (long)updatedRetryCounter, fromPathsToRetry, toPathsToRetry);
        [self uploadLocalFiles:fromPathsToRetry.array toPaths:toPathsToRetry.array retryCounter:updatedRetryCounter completion:block];
    }
    else {
        // Retry attempts exceeded maximum allowed - report failure
        CDELog(CDELoggingLevelError, @"Dropbox: batch upload failed completely: attempt %ld", (long)updatedRetryCounter);
        NSError *error = nil;
        if (finishBatchRequestError.nsError) {
            error = finishBatchRequestError.nsError;
        }
        else {
            error = [[NSError alloc] initWithDomain:CDEErrorDomain code:CDEErrorCodeNetworkError userInfo:nil];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (block) block(error);
        });
    }
}

- (void)uploadLocalFile:(NSString *)fromPath toPath:(NSString *)toPath completion:(CDECompletionBlock)block
{
    DBUserClient *authorizedClient = [self authorizedClient];
    if (!authorizedClient) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (block) block([[self class] genericAuthorizationError]);
        });
        return;
    }
    DBUploadTask *task = [authorizedClient.filesRoutes uploadUrl:[self fullDropboxPathForPath:toPath] mode:nil autorename:nil clientModified:nil mute:@(YES) inputUrl:fromPath];
    task.retryCount = kCDENumberOfRetriesForFailedAttempt;
    [task setResponseBlock:^(DBFILESFileMetadata * _Nullable metadata, DBFILESUploadError * _Nullable routeError, DBRequestError * _Nullable error) {
        if (routeError) CDELog(CDELoggingLevelError, @"Dropbox: routeError in uploadUrl: %@\nfromPath: %@\ntoPath: %@", routeError, fromPath, [self fullDropboxPathForPath:toPath]);
        else if (error) CDELog(CDELoggingLevelError, @"Dropbox: error in uploadUrl: %@\nfromPath: %@\ntoPath: %@", error, fromPath, [self fullDropboxPathForPath:toPath]);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (block) block([self errorForRouteError:routeError requestError:error result:metadata]);
        });
    }];
}

- (void)downloadFromPaths:(NSArray *)fromPaths toLocalFiles:(NSArray *)toPaths completion:(CDECompletionBlock)block
{
    DBUserClient *authorizedClient = [self authorizedClient];
    if (!authorizedClient) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (block) block([[self class] genericAuthorizationError]);
        });
        return;
    }
    NSArray <NSString *> *dropboxURLs = [self fullDropboxPathsForPaths:fromPaths];
    NSArray <NSURL *> *localURLs = [toPaths cde_arrayByTransformingObjectsWithBlock:^id(NSString *path) {
        return [NSURL fileURLWithPath:path];
    }];
    NSDictionary *routes = [NSDictionary dictionaryWithObjects:localURLs forKeys:dropboxURLs];

    __block NSError *lastError = nil;
    dispatch_group_t group = dispatch_group_create();

    for (__unused id job in routes) {
        dispatch_group_enter(group);
    }
    [routes enumerateKeysAndObjectsUsingBlock:^(NSString *dropboxURL, NSURL *localURL, BOOL *stop) {
        DBDownloadUrlTask *task = [authorizedClient.filesRoutes downloadUrl:dropboxURL overwrite:YES destination:localURL];
        task.retryCount = kCDENumberOfRetriesForFailedAttempt;
        [task setResponseBlock:^(DBFILESFileMetadata *metadata, DBFILESDownloadError *routeError, DBRequestError *error, NSURL *actualLocalURL) {
            if (routeError) CDELog(CDELoggingLevelError, @"Dropbox: routeError in downloadUrl: %@\ndropboxURL: %@\nlocalURL: %@", routeError, dropboxURL, localURL);
            else if (error) CDELog(CDELoggingLevelError, @"Dropbox: error in downloadUrl: %@\ndropboxURL: %@\nlocalURL: %@", error, dropboxURL, localURL);
            if (!metadata) {
                lastError = [self errorForRouteError:routeError requestError:error result:metadata];
            }
            dispatch_group_leave(group);
        }];
    }];

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        if (block) block(lastError);
    });
}

- (void)downloadFromPath:(NSString *)fromPath toLocalFile:(NSString *)toPath completion:(CDECompletionBlock)block
{
    return [self downloadFromPaths:@[fromPath] toLocalFiles:@[toPath] completion:block];
}

#pragma mark - Long Poll notifications

- (void)subscribeForRemoteFileChangeNotificationsWithCompletion:(nullable CDECompletionBlock)completion
{
    DBUserClient *authorizedClient = self.authorizedClient;
    if (!authorizedClient) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion([[self class] genericAuthorizationError]);
        });
    }
    else {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(nil);
        });
        [self monitorCloudFileChanges];
    }
}

- (void)monitorCloudFileChanges
{
    [self recursivelyListAllFilesWithCompletion:^(DBFILESListFolderGetLatestCursorResult *result, NSError *error) {
        __weak typeof(self) weakSelf = self;

        if (!result) {
            CDELog(CDELoggingLevelError, @"Dropbox: error in recursivelyListAllFilesWithCompletion: %@. Retrying in 30 seconds.", error);
            
            // Reschedule, but don't retain self, so that we allow the file system to be dealloced if needed.
            dispatch_time_t time = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30.0 * NSEC_PER_SEC));
            dispatch_after(time, dispatch_get_main_queue(), ^{
                typeof(self) strongSelf = weakSelf;
                [strongSelf monitorCloudFileChanges];
            });
            
            return;
        }
        
        // Long poll can take a long time, so make sure we don't retain self during the operation. Use weak self.
        [self longPollListFolderResult:result withCompletion:^(NSError *error, BOOL longPollChanges) {
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (longPollChanges) {
                if ([strongSelf.delegate respondsToSelector:@selector(dropboxCloudFileSystemDidDetectRemoteFileChanges:)]) {
                    [strongSelf.delegate dropboxCloudFileSystemDidDetectRemoteFileChanges:strongSelf];
                }
            }
            [strongSelf monitorCloudFileChanges];
        }];
    }];
}

- (void)recursivelyListAllFilesWithCompletion:(void(^)(DBFILESListFolderGetLatestCursorResult *result, NSError *error))completion {
    DBUserClient *authorizedClient = self.authorizedClient;
    if (!authorizedClient) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(nil, [[self class] genericAuthorizationError]);
        });
        return;
    }
    
    DBRpcTask *routes = [authorizedClient.filesRoutes listFolderGetLatestCursor:[self fullDropboxPathForPath:@"/"] recursive:@(YES) includeMediaInfo:@(NO) includeDeleted:@(NO) includeHasExplicitSharedMembers:@(NO)];
    routes.retryCount = kCDENumberOfRetriesForFailedAttempt;
    [routes setResponseBlock:^(DBFILESListFolderGetLatestCursorResult *result, DBFILESListFolderError *routeError,DBRequestError *error) {
        if (routeError) CDELog(CDELoggingLevelError, @"Dropbox: routeError in listFolder before longpoll: %@", routeError);
        else if (error) CDELog(CDELoggingLevelError, @"Dropbox: requestError in listFolder before longpoll: %@", error);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(result, result ? nil : [self errorForRouteError:routeError requestError:error result:result]);
        });
    }];
}

- (void)longPollListFolderResult:(DBFILESListFolderGetLatestCursorResult *)result withCompletion:(CDEBooleanQueryBlock)completion
{
    DBUserClient *authorizedClient = self.authorizedClient;
    if (!authorizedClient) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion([[self class] genericAuthorizationError], false);
        });
        return;
    }
    
    __weak typeof(self) weakSelf = self;
    DBRpcTask *task = [authorizedClient.filesRoutes listFolderLongpoll:[result cursor] timeout:@(300)];
    task.retryCount = kCDENumberOfRetriesForFailedAttempt;
    [task setResponseBlock:^(DBFILESListFolderLongpollResult * _Nullable longPollResult, DBFILESListFolderLongpollError *_Nullable longPollRouteError, DBRequestError * _Nullable longPollError) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        CDELog(CDELoggingLevelVerbose, @"Dropbox: longPollListFolderResult: changes=%@, backoff=%@", [longPollResult changes], [longPollResult backoff]);
        
        if (longPollRouteError) CDELog(CDELoggingLevelError, @"Dropbox: routeError in listFolderLongpoll: %@", longPollRouteError);
        else if (longPollError) CDELog(CDELoggingLevelError, @"Dropbox: requestError in listFolderLongpoll: %@", longPollError);
        
        NSError *error = longPollResult ? nil : [self errorForRouteError:longPollRouteError requestError:longPollError result:longPollResult];
        BOOL longPollChanges = [longPollResult changes].integerValue > 0;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(error, longPollChanges);
        });
    }];
}

@end

