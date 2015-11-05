//
//  CDEICloudFileSystem.m
//  Ensembles
//
//  Created by Drew McCormack on 20/09/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import "CDEICloudFileSystem.h"
#import "CDECloudDirectory.h"
#import "CDECloudFile.h"
#import "CDEAvailabilityMacros.h"
#import "NSFileCoordinator+CDEAdditions.h"

NSString * const CDEICloudFileSystemDidDownloadFilesNotification = @"CDEICloudFileSystemDidUpdateFilesNotification";
NSString * const CDEICloudFileSystemDidMakeDownloadProgressNotification = @"CDEICloudFileSystemDidMakeDownloadProgressNotification";

@interface CDEICloudFileSystem ()

@property (atomic, readwrite) unsigned long long bytesRemainingToDownload;

@end


@implementation CDEICloudFileSystem {
    NSFileManager *fileManager;
    NSURL *rootDirectoryURL;
    NSMetadataQuery *metadataQuery;
    NSOperationQueue *operationQueue;
    NSOperationQueue *presenterQueue;
    NSString *ubiquityContainerIdentifier;
    dispatch_queue_t timeOutQueue;
    dispatch_queue_t initiatingDownloadsQueue;
    id ubiquityIdentityObserver;
    NSOperationQueue *downloadTrackingQueue;
    NSDate *lastProgressNotificationDate;
    NSMutableSet *downloadingURLs, *handlingURLs;
    NSMutableSet *locallyModifiedPaths;
}

@synthesize relativePathToRootInContainer = relativePathToRootInContainer;
@synthesize bytesRemainingToDownload = bytesRemainingToDownload;
@synthesize isConnected = isConnected;

- (instancetype)initWithUbiquityContainerIdentifier:(NSString *)newIdentifier
{
    return [self initWithUbiquityContainerIdentifier:newIdentifier relativePathToRootInContainer:nil];
}

- (instancetype)initWithUbiquityContainerIdentifier:(NSString *)newIdentifier relativePathToRootInContainer:(NSString *)rootSubPath
{
    self = [super init];
    if (self) {
        fileManager = [[NSFileManager alloc] init];
        
        isConnected = NO;
        
        operationQueue = [[NSOperationQueue alloc] init];
        operationQueue.maxConcurrentOperationCount = 1;
        if ([operationQueue respondsToSelector:@selector(setQualityOfService:)]) {
            [operationQueue setQualityOfService:NSQualityOfServiceUtility];
        }
        
        presenterQueue = [[NSOperationQueue alloc] init];
        presenterQueue.maxConcurrentOperationCount = 1;
        if ([presenterQueue respondsToSelector:@selector(setQualityOfService:)]) {
            [presenterQueue setQualityOfService:NSQualityOfServiceUtility];
        }
        
        downloadTrackingQueue = [[NSOperationQueue alloc] init];
        downloadTrackingQueue.maxConcurrentOperationCount = 1;
        if ([downloadTrackingQueue respondsToSelector:@selector(setQualityOfService:)]) {
            [downloadTrackingQueue setQualityOfService:NSQualityOfServiceUtility];
        }
        
        timeOutQueue = dispatch_queue_create("com.mentalfaculty.ensembles.queue.icloudtimeout", DISPATCH_QUEUE_SERIAL);
        initiatingDownloadsQueue = dispatch_queue_create("com.mentalfaculty.ensembles.queue.initiatedownloads", DISPATCH_QUEUE_SERIAL);
        
        rootDirectoryURL = nil;
        relativePathToRootInContainer = [rootSubPath copy] ? : @"com.mentalfaculty.ensembles.clouddata";
        metadataQuery = nil;
        ubiquityContainerIdentifier = [newIdentifier copy];
        ubiquityIdentityObserver = nil;
        
        bytesRemainingToDownload = 0;
        lastProgressNotificationDate = nil;
        
        downloadingURLs = [NSMutableSet set];
        handlingURLs = [NSMutableSet set];
        locallyModifiedPaths = [NSMutableSet set];
        
        [operationQueue addOperationWithBlock:^{
            [self updateRootDirectoryURL];
        }];
        
        [operationQueue addOperationWithBlock:^{
            [self updateRootDirectoryURL];
        }];
        
        [self performInitialPreparation:^(NSError *error) {
            if (error) CDELog(CDELoggingLevelError, @"Error setting up iCloud container: %@", error);
        }];
    }
    return self;
}

- (instancetype)init
{
    @throw [NSException exceptionWithName:CDEException reason:@"iCloud initializer requires container identifier" userInfo:nil];
    return nil;
}

- (void)dealloc
{
    [self removeUbiquityContainerNotificationObservers];
    [self stopMonitoring];
    [operationQueue cancelAllOperations];
}

#pragma mark - User Identity

- (id <NSObject, NSCoding, NSCopying>)identityToken
{
    if ([fileManager respondsToSelector:@selector(ubiquityIdentityToken)]) {
        return [fileManager ubiquityIdentityToken];
    }
    return @"User";
}

#pragma mark - Initial Preparation

- (void)checkUserIsLoggedIn:(CDEBooleanQueryBlock)completion
{
    [operationQueue addOperationWithBlock:^{
        BOOL loggedIn = NO;
        if ([fileManager respondsToSelector:@selector(ubiquityIdentityToken)]) {
            loggedIn = [fileManager ubiquityIdentityToken] != nil && ([fileManager URLForUbiquityContainerIdentifier:ubiquityContainerIdentifier] != nil);
        }
        else {
            loggedIn = [fileManager URLForUbiquityContainerIdentifier:ubiquityContainerIdentifier] != nil;
        }
        
        isConnected = loggedIn;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(nil, loggedIn);
        });
    }];
}

- (void)performInitialPreparation:(CDECompletionBlock)completion
{
    [self checkUserIsLoggedIn:^(NSError *error, BOOL loggedIn) {
        if (loggedIn) {
            [self setupRootDirectory:^(NSError *error) {
                [self startMonitoringMetadata];
                [self addUbiquityContainerNotificationObservers];
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completion) completion(error);
                });
            }];
        }
        else {
            [self addUbiquityContainerNotificationObservers];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(nil);
            });
        }
    }];
}

#pragma mark - Repair

- (void)repairEnsembleDirectory:(NSString *)ensembleDir completion:(CDECompletionBlock)completion
{
    CDELog(CDELoggingLevelVerbose, @"Checking if repairs are needed in iCloud Drive");
    
    // This repair looks for duplicates of the root directory, or ensemble directory. These are generated by
    // iCloud Drive when a conflict occurs. The repair is to merge the duplicate directory trees
    // back into the original.
    [operationQueue addOperationWithBlock:^{
        NSError *error = nil;
        
        // Root directory
        NSString *rootDirectory = rootDirectoryURL.path;
        NSArray *rootPathsToMerge = [self directoriesToMergeForDirectory:rootDirectory error:&error];
        if (!rootPathsToMerge) {
            [self dispatchCompletion:completion withError:error];
            return;
        }
        
        if (rootPathsToMerge.count > 0) {
            CDELog(CDELoggingLevelWarning, @"Discovered duplicate root directories in iCloud Drive. Will merge back in: %@", rootPathsToMerge);
            error = [self mergeDirectory:rootDirectory withDirectories:rootPathsToMerge];
            if (error) {
                [self dispatchCompletion:completion withError:error];
                return;
            }
        }
        
        // Ensemble directory
        NSString *fullEnsembleDirPath = [self fullPathForPath:ensembleDir];
        NSArray *directoryPathsToMerge = [self directoriesToMergeForDirectory:fullEnsembleDirPath error:&error];
        if (!directoryPathsToMerge) {
            [self dispatchCompletion:completion withError:error];
            return;
        }
        
        if (directoryPathsToMerge.count > 0) {
            CDELog(CDELoggingLevelWarning, @"Discovered duplicate directories in iCloud Drive. Will merge back in: %@", directoryPathsToMerge);
            error = [self mergeDirectory:fullEnsembleDirPath withDirectories:directoryPathsToMerge];
            if (error) {
                [self dispatchCompletion:completion withError:error];
                return;
            }
        }
        
        [self dispatchCompletion:completion withError:nil];
    }];
}

- (NSError *)mergeDirectory:(NSString *)directoryPath withDirectories:(NSArray *)dirPathsToMerge
{
    for (NSString *dirToMerge in dirPathsToMerge) {
        CDELog(CDELoggingLevelVerbose, @"Merging iCloud duplicate directory into original: %@", dirToMerge);
        
        NSDirectoryEnumerator *dirEnum = [fileManager enumeratorAtPath:dirToMerge];
        
        // Copy duplicate directory tree into the original
        NSString *relativePath;
        while ( relativePath = [dirEnum nextObject] ) {
            NSString *pathInDirectory = [directoryPath stringByAppendingPathComponent:relativePath];
            NSString *duplicatePath = [dirToMerge stringByAppendingPathComponent:relativePath];
            if ([fileManager fileExistsAtPath:pathInDirectory]) continue;
            
            NSURL *ensembleURL = [NSURL fileURLWithPath:pathInDirectory];
            NSURL *duplicateURL = [NSURL fileURLWithPath:duplicatePath];
            
            NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:self];
            
            NSError *fileCoordinatorError = nil;
            __block NSError *fileManagerError = nil;
            if ([dirEnum.fileAttributes.fileType isEqualToString:NSFileTypeDirectory]) {
                [coordinator cde_coordinateWritingItemAtURL:ensembleURL options:0 timeout:CDEFileCoordinatorTimeOut error:&fileCoordinatorError byAccessor:^(NSURL *newURL) {
                    NSError *error = nil;
                    BOOL success = [fileManager createDirectoryAtURL:newURL withIntermediateDirectories:YES attributes:nil error:&error];
                    if (!success) fileManagerError = error;
                }];
            }
            else if ([dirEnum.fileAttributes.fileType isEqualToString:NSFileTypeRegular]) {
                [coordinator cde_coordinateReadingItemAtURL:duplicateURL options:0 writingItemAtURL:ensembleURL options:NSFileCoordinatorWritingForReplacing timeout:CDEFileCoordinatorTimeOut error:&fileCoordinatorError byAccessor:^(NSURL *newReadingURL, NSURL *newWritingURL) {
                    NSError *error = nil;
                    BOOL success = [fileManager copyItemAtURL:newReadingURL toURL:newWritingURL error:&error];
                    if (!success) fileManagerError = error;
                }];
            }
            
            if (fileCoordinatorError || fileManagerError) {
                return fileCoordinatorError ? : fileManagerError;
            }
        }
        
        // Delete the duplicate directory
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:self];
        
        NSURL *dirToMergeURL = [NSURL fileURLWithPath:dirToMerge];
        NSError *coordinatorError = nil;
        __block NSError *fileManagerError = nil;
        [coordinator cde_coordinateWritingItemAtURL:dirToMergeURL options:NSFileCoordinatorWritingForDeleting timeout:CDEFileCoordinatorTimeOut error:&coordinatorError byAccessor:^(NSURL *newURL) {
            NSError *error = nil;
            BOOL success = [fileManager removeItemAtURL:newURL error:&error];
            if (!success) fileManagerError = error;
        }];
        
        if (coordinatorError || fileManagerError) {
            return coordinatorError ? : fileManagerError;
        }
    }
    return nil;
}

- (NSArray *)directoriesToMergeForDirectory:(NSString *)directory error:(NSError * __autoreleasing *)returnError
{
    if (!directory) return @[];
    
    NSMutableArray *directoriesForMerging = [[NSMutableArray alloc] init];
    NSString *rootDir = [directory stringByDeletingLastPathComponent];
    NSString *ensembleName = [directory lastPathComponent];
    for (NSUInteger i = 2; i < 10; i++) {
        NSString *duplicateName = [NSString stringWithFormat:@"%@ %d", ensembleName, (int)i];
        NSString *duplicatePath = [rootDir stringByAppendingPathComponent:duplicateName];
        NSURL *duplicateURL = [NSURL fileURLWithPath:duplicatePath];
        
        BOOL isDir;
        if ([fileManager fileExistsAtPath:duplicateURL.path isDirectory:&isDir] && isDir) {
            [directoriesForMerging addObject:duplicateURL.path];
        }
    }
    
    return directoriesForMerging;
}

#pragma mark - Root Directory

- (void)updateRootDirectoryURL
{
    NSURL *newURL = [fileManager URLForUbiquityContainerIdentifier:ubiquityContainerIdentifier];
    newURL = [newURL URLByAppendingPathComponent:relativePathToRootInContainer];
    rootDirectoryURL = newURL;
}

- (void)setupRootDirectory:(CDECompletionBlock)completion
{
    [operationQueue addOperationWithBlock:^{
        [self updateRootDirectoryURL];
        if (!rootDirectoryURL) {
            NSError *error = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeServerError userInfo:@{NSLocalizedDescriptionKey : @"Could not retrieve URLForUbiquityContainerIdentifier. Check container id for iCloud."}];
            CDELog(CDELoggingLevelError, @"Failed to get the URL of the iCloud ubiquity container: %@", error);
            [self dispatchCompletion:completion withError:error];
            return;
        }
        
        NSError *error = nil;
        __block BOOL fileExistsAtPath = NO;
        __block BOOL existingFileIsDirectory = NO;
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:self];
        [coordinator cde_coordinateReadingItemAtURL:rootDirectoryURL options:NSFileCoordinatorReadingWithoutChanges timeout:CDEFileCoordinatorTimeOut error:&error byAccessor:^(NSURL *newURL) {
            fileExistsAtPath = [fileManager fileExistsAtPath:newURL.path isDirectory:&existingFileIsDirectory];
        }];
        if (error) {
            CDELog(CDELoggingLevelWarning, @"File coordinator error: %@", error);
            [self dispatchCompletion:completion withError:error];
            return;
        }
        
        __block NSError *fileManagerError = nil;
        if (!fileExistsAtPath) {
            [coordinator cde_coordinateWritingItemAtURL:rootDirectoryURL options:0 timeout:CDEFileCoordinatorTimeOut error:&error byAccessor:^(NSURL *newURL) {
                NSError *error;
                BOOL success = [fileManager createDirectoryAtURL:newURL withIntermediateDirectories:YES attributes:nil error:&error];
                if (!success) fileManagerError = error;
            }];
        }
        else if (fileExistsAtPath && !existingFileIsDirectory) {
            [coordinator cde_coordinateWritingItemAtURL:rootDirectoryURL options:NSFileCoordinatorWritingForReplacing timeout:CDEFileCoordinatorTimeOut error:&error byAccessor:^(NSURL *newURL) {
                NSError *error;
                [fileManager removeItemAtURL:newURL error:NULL];
                BOOL success = [fileManager createDirectoryAtURL:newURL withIntermediateDirectories:YES attributes:nil error:&error];
                if (!success) fileManagerError = error;
            }];
        }
        
        if (!error && fileManagerError) error = fileManagerError;
        if (error) CDELog(CDELoggingLevelWarning, @"File error: %@", error);
        
        [self dispatchCompletion:completion withError:error];
    }];
}

- (void)dispatchCompletion:(CDECompletionBlock)completion withError:(NSError *)error
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (completion) completion(error);
    });
}

- (NSString *)fullPathForPath:(NSString *)path
{
    return [rootDirectoryURL.path stringByAppendingPathComponent:path];
}

#pragma mark - Notifications

- (void)removeUbiquityContainerNotificationObservers
{
    if (ubiquityIdentityObserver) [[NSNotificationCenter defaultCenter] removeObserver:ubiquityIdentityObserver];
    ubiquityIdentityObserver = nil;
}

- (void)addUbiquityContainerNotificationObservers
{
    [self removeUbiquityContainerNotificationObservers];
    
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wtautological-pointer-compare"
    if (&NSUbiquityIdentityDidChangeNotification != NULL) {
#pragma clang diagnostic pop
        __weak typeof(self) weakSelf = self;
        ubiquityIdentityObserver = [[NSNotificationCenter defaultCenter] addObserverForName:NSUbiquityIdentityDidChangeNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            [strongSelf stopMonitoring];
            [strongSelf willChangeValueForKey:@"identityToken"];
            [strongSelf didChangeValueForKey:@"identityToken"];
        }];
    }
}

#pragma mark - Connection

- (void)connect:(CDECompletionBlock)completion
{
    [self checkUserIsLoggedIn:^(NSError *error, BOOL loggedIn) {
        if (loggedIn) {
            [self setupRootDirectory:^(NSError *error) {
                [self startMonitoringMetadata];
                [self addUbiquityContainerNotificationObservers];
                if (completion) completion(error);
            }];
        }
        else {
            error = loggedIn && !error ? nil : [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeAuthenticationFailure userInfo:@{NSLocalizedDescriptionKey : NSLocalizedString(@"User is not logged into iCloud.", @"")} ];
            if (completion) completion(error);
        }
    }];
}

#pragma mark - Metadata Query to download new files

- (void)startMonitoringMetadata
{
    [self stopMonitoring];
    if (!rootDirectoryURL) return;
    
    // Determine downloading key and set the appropriate predicate. This is OS dependent.
    NSPredicate *metadataPredicate = nil;
    
#if (__IPHONE_OS_VERSION_MIN_REQUIRED < __IPHONE_7_0) && (__MAC_OS_X_VERSION_MIN_REQUIRED < __MAC_10_9)
    metadataPredicate = [NSPredicate predicateWithFormat:@"%K = FALSE AND %K = FALSE AND %K BEGINSWITH %@",
                         NSMetadataUbiquitousItemIsDownloadedKey, NSMetadataUbiquitousItemIsDownloadingKey, NSMetadataItemPathKey, rootDirectoryURL.path];
#else
    metadataPredicate = [NSPredicate predicateWithFormat:@"%K != %@ AND %K = FALSE AND %K BEGINSWITH %@",
                         NSMetadataUbiquitousItemDownloadingStatusKey, NSMetadataUbiquitousItemDownloadingStatusCurrent, NSMetadataUbiquitousItemIsDownloadingKey, NSMetadataItemPathKey, rootDirectoryURL.path];
#endif
    
    metadataQuery = [[NSMetadataQuery alloc] init];
    metadataQuery.searchScopes = [NSArray arrayWithObject:NSMetadataQueryUbiquitousDataScope];
    metadataQuery.predicate = metadataPredicate;
    metadataQuery.notificationBatchingInterval = 0.0;
    
    NSNotificationCenter *notifationCenter = [NSNotificationCenter defaultCenter];
    [notifationCenter addObserver:self selector:@selector(metadataQueryDidFinishGathering:) name:NSMetadataQueryDidFinishGatheringNotification object:metadataQuery];
    [notifationCenter addObserver:self selector:@selector(metadataQueryDidUpdate:) name:NSMetadataQueryDidUpdateNotification object:metadataQuery];
    
    [metadataQuery startQuery];
    
    [NSFileCoordinator addFilePresenter:self];
}

- (void)stopMonitoring
{
    if (!metadataQuery) return;
    
    [metadataQuery disableUpdates];
    [metadataQuery stopQuery];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSMetadataQueryDidFinishGatheringNotification object:metadataQuery];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSMetadataQueryDidUpdateNotification object:metadataQuery];
    
    metadataQuery = nil;
    
    [presenterQueue cancelAllOperations];
    [NSFileCoordinator removeFilePresenter:self];
}

- (void)metadataQueryDidFinishGathering:(NSNotification *)notif
{
    [metadataQuery disableUpdates];
    [self initiateDownloads];
    [metadataQuery enableUpdates];
}

- (void)metadataQueryDidUpdate:(NSNotification *)notif
{
    [metadataQuery disableUpdates];
    [self initiateDownloads];
    [metadataQuery enableUpdates];
}

- (void)initiateDownloads
{
    NSUInteger count = [metadataQuery resultCount];
    for ( NSUInteger i = 0; i < count; i++ ) {
        @autoreleasepool {
            NSURL *url = [metadataQuery valueOfAttribute:NSMetadataItemURLKey forResultAtIndex:i];
            @synchronized(self) {
                if ([downloadingURLs containsObject:url] || [handlingURLs containsObject:url]) continue;
                [handlingURLs addObject:url];
            }
            
            NSNumber *percentDownloaded = [metadataQuery valueOfAttribute:NSMetadataUbiquitousItemPercentDownloadedKey forResultAtIndex:i];
            NSNumber *fileSizeNumber = [metadataQuery valueOfAttribute:NSMetadataItemFSSizeKey forResultAtIndex:i];

#if (__IPHONE_OS_VERSION_MIN_REQUIRED < __IPHONE_7_0) && (__MAC_OS_X_VERSION_MIN_REQUIRED < __MAC_10_9)
            NSNumber *downloaded = [metadataQuery valueOfAttribute:NSMetadataUbiquitousItemIsDownloadedKey forResultAtIndex:i];
#else
            NSString *downloadingStatus = [metadataQuery valueOfAttribute:NSMetadataUbiquitousItemDownloadingStatusKey forResultAtIndex:i];
            NSNumber *downloaded = @([downloadingStatus isEqualToString:NSMetadataUbiquitousItemDownloadingStatusNotDownloaded]);
#endif
            
            dispatch_async(initiatingDownloadsQueue, ^{
                NSError *error;
                BOOL startedDownload = [fileManager startDownloadingUbiquitousItemAtURL:url error:&error];
                if ( startedDownload ) {
                    unsigned long long bytesRemainingForThisFile = 0;
                    
                    @synchronized(self) {
                        [downloadingURLs addObject:url];
                        [handlingURLs removeObject:url];
                        
                        unsigned long long fileSize = fileSizeNumber ? fileSizeNumber.unsignedLongLongValue : 0;
                        if ( downloaded && !downloaded.boolValue ) {
                            double percentage = percentDownloaded ? percentDownloaded.doubleValue : 0.0;
                            bytesRemainingForThisFile = (1.0 - percentage / 100.0) * fileSize;
                            self.bytesRemainingToDownload += bytesRemainingForThisFile;
                        }
                        
                        [self postProgressNotificationIfNecessary];
                    }
                    
                    [downloadTrackingQueue addOperationWithBlock:^{
                        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:self];
                        NSError *error = nil;
                        __block BOOL complete = NO;
                        [coordinator cde_coordinateReadingItemAtURL:url options:0 timeout:CDEFileCoordinatorTimeOut error:&error byAccessor:^(NSURL *newURL) {
                            @synchronized(self) {
                                complete = [self removeDownloadingURL:url bytes:bytesRemainingForThisFile];
                                [self postProgressNotificationIfNecessary];
                            }
                        }];
                        
                        if (error) {
                            @synchronized(self) {
                                complete = [self removeDownloadingURL:url bytes:bytesRemainingForThisFile];
                                [self postProgressNotificationIfNecessary];
                            }
                        }
                        
                        // If there were downloads, and aren't anymore, fire notification
                        // Use a delay to coalesce, because there often seems to be many small
                        // metadata updates in a row
                        if (complete) {
                            dispatch_async(dispatch_get_main_queue(), ^{
                                [self.class cancelPreviousPerformRequestsWithTarget:self selector:@selector(postDidDownloadNotification) object:nil];
                                [self performSelector:@selector(postDidDownloadNotification) withObject:nil afterDelay:5.0];
                            });
                        }
                    }];
                } else {
                    @synchronized(self) {
                        [handlingURLs removeObject:url];
                    }
                    CDELog(CDELoggingLevelWarning, @"Error starting download: %@", error);
                }
            });
        }
    }
}

- (BOOL)removeDownloadingURL:(NSURL *)url bytes:(unsigned long long)bytes
{
    BOOL complete = NO;
    [downloadingURLs removeObject:url];
    self.bytesRemainingToDownload -= bytes;
    if (downloadingURLs.count == 0) {
        complete = YES;
        self.bytesRemainingToDownload = 0;
    }
    return complete;
}

- (void)postProgressNotificationIfNecessary
{
    @synchronized(self) {
        NSDate *now = [NSDate date];
        if (!lastProgressNotificationDate || [now timeIntervalSinceDate:lastProgressNotificationDate] > 5.0) {
            lastProgressNotificationDate = now;
            dispatch_async(dispatch_get_main_queue(), ^{
                [self postDidMakeDownloadProgressNotification];
            });
        }
    }
}

- (void)postDidDownloadNotification
{
    @synchronized(self) {
        [self postDidMakeDownloadProgressNotification];
        lastProgressNotificationDate = nil;
        
        [[NSNotificationCenter defaultCenter] postNotificationName:CDEICloudFileSystemDidDownloadFilesNotification object:self];
        
        [self startMonitoringMetadata]; // Refresh query, which often gets 'stuck'
    }
}

- (void)postDidMakeDownloadProgressNotification
{
    [[NSNotificationCenter defaultCenter] postNotificationName:CDEICloudFileSystemDidMakeDownloadProgressNotification object:self];
}

#pragma mark - File Presentation

- (NSURL *)presentedItemURL
{
    return rootDirectoryURL;
}

- (NSOperationQueue *)presentedItemOperationQueue
{
    return presenterQueue;
}

- (void)presentedSubitemDidChangeAtURL:(NSURL *)url
{
    @synchronized(self) {
        NSString *path = [url.path stringByStandardizingPath];
        BOOL local = [locallyModifiedPaths containsObject:path];
        [locallyModifiedPaths removeObject:path];
        if (local) return;
 
        // If metadata query has not fired, schedule a notification.
        // Really only an issue on Mac, which can download files
        // without them being requested.
        if (downloadingURLs.count > 0) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.class cancelPreviousPerformRequestsWithTarget:self selector:@selector(postDidDownloadNotification) object:nil];
            [self performSelector:@selector(postDidDownloadNotification) withObject:nil afterDelay:5.0];
        });
    }
}

#pragma mark - File Operations

static const NSTimeInterval CDEFileCoordinatorTimeOut = 10.0;

- (NSError *)specializedErrorForCocoaError:(NSError *)cocoaError
{
    NSError *error = cocoaError;
    if ([cocoaError.domain isEqualToString:NSCocoaErrorDomain] && cocoaError.code == NSUserCancelledError) {
        error = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeFileCoordinatorTimedOut userInfo:nil];
    }
    return error;
}

- (NSError *)notConnectedError
{
    NSError *error = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeConnectionError userInfo:@{NSLocalizedDescriptionKey : @"Attempted to access iCloud when not connected."}];
    return error;
}

- (void)fileExistsAtPath:(NSString *)path completion:(void(^)(BOOL exists, BOOL isDirectory, NSError *error))block
{
    [operationQueue addOperationWithBlock:^{
        if (!self.isConnected || !rootDirectoryURL) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (block) block(NO, NO, [self notConnectedError]);
            });
            return;
        }
        
        NSError *fileCoordinatorError = nil;
        __block BOOL isDirectory = NO;
        __block BOOL exists = NO;
        
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:self];
        
        NSString *fullPath = [self fullPathForPath:path];
        NSURL *url = [NSURL fileURLWithPath:fullPath];
        [coordinator cde_coordinateReadingItemAtURL:url options:0 timeout:CDEFileCoordinatorTimeOut error:&fileCoordinatorError byAccessor:^(NSURL *newURL) {
            exists = [fileManager fileExistsAtPath:newURL.path isDirectory:&isDirectory];
        }];
        
        NSError *error = fileCoordinatorError ? : nil;
        error = [self specializedErrorForCocoaError:error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (block) block(exists, isDirectory, error);
        });
    }];
}

- (void)contentsOfDirectoryAtPath:(NSString *)path completion:(void(^)(NSArray *contents, NSError *error))block
{
    [operationQueue addOperationWithBlock:^{
        if (!self.isConnected || !rootDirectoryURL) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (block) block(nil, [self notConnectedError]);
            });
            return;
        }
        
        NSError *fileCoordinatorError = nil;
        __block NSError *fileManagerError = nil;
        
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:self];
        
        __block NSArray *contents = nil;
        NSURL *url = [NSURL fileURLWithPath:[self fullPathForPath:path]];
        [coordinator cde_coordinateReadingItemAtURL:url options:0 timeout:CDEFileCoordinatorTimeOut error:&fileCoordinatorError byAccessor:^(NSURL *newURL) {
            NSDirectoryEnumerator *dirEnum = [fileManager enumeratorAtPath:[self fullPathForPath:path]];
            NSDictionary *info = @{NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Couldn't create directory enumerator for path: %@", path]};
            if (!dirEnum) fileManagerError = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeFileAccessFailed userInfo:info];
            
            NSString *filename;
            NSMutableArray *mutableContents = [[NSMutableArray alloc] init];
            while ((filename = [dirEnum nextObject])) {
                if ([filename hasPrefix:@"."]) continue; // Skip .DS_Store and other system files
                NSString *filePath = [path stringByAppendingPathComponent:filename];
                if ([dirEnum.fileAttributes.fileType isEqualToString:NSFileTypeDirectory]) {
                    [dirEnum skipDescendants];
                    
                    CDECloudDirectory *dir = [[CDECloudDirectory alloc] init];
                    dir.name = filename;
                    dir.path = filePath;
                    [mutableContents addObject:dir];
                }
                else {
                    CDECloudFile *file = [CDECloudFile new];
                    file.name = filename;
                    file.path = filePath;
                    file.size = dirEnum.fileAttributes.fileSize;
                    [mutableContents addObject:file];
                }
            }
            
            if (!fileManagerError) contents = mutableContents;
        }];
        
        NSError *error = fileCoordinatorError ? : fileManagerError ? : nil;
        error = [self specializedErrorForCocoaError:error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (block) block(contents, error);
        });
    }];
    
}

- (void)createDirectoryAtPath:(NSString *)path completion:(CDECompletionBlock)block
{
    [operationQueue addOperationWithBlock:^{
        if (!self.isConnected || !rootDirectoryURL) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (block) block([self notConnectedError]);
            });
            return;
        }
        
        NSError *fileCoordinatorError = nil;
        __block NSError *fileManagerError = nil;
        
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:self];
        
        NSURL *url = [NSURL fileURLWithPath:[self fullPathForPath:path]];
        NSString *path = [url.path stringByStandardizingPath];
        [locallyModifiedPaths addObject:path];
        
        [coordinator cde_coordinateWritingItemAtURL:url options:0 timeout:CDEFileCoordinatorTimeOut error:&fileCoordinatorError byAccessor:^(NSURL *newURL) {
            [fileManager createDirectoryAtPath:newURL.path withIntermediateDirectories:NO attributes:nil error:&fileManagerError];
        }];
        
        NSError *error = fileCoordinatorError ? : fileManagerError ? : nil;
        error = [self specializedErrorForCocoaError:error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (block) block(error);
        });
    }];
}

- (void)removeItemAtPath:(NSString *)path completion:(CDECompletionBlock)block
{
    [operationQueue addOperationWithBlock:^{
        if (!self.isConnected || !rootDirectoryURL) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (block) block([self notConnectedError]);
            });
            return;
        }
        
        NSError *fileCoordinatorError = nil;
        __block NSError *fileManagerError = nil;
        
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:self];
        
        NSURL *url = [NSURL fileURLWithPath:[self fullPathForPath:path]];
        NSString *path = [url.path stringByStandardizingPath];
        [locallyModifiedPaths addObject:path];
        
        [coordinator cde_coordinateWritingItemAtURL:url options:NSFileCoordinatorWritingForDeleting timeout:CDEFileCoordinatorTimeOut error:&fileCoordinatorError byAccessor:^(NSURL *newURL) {
            [fileManager removeItemAtPath:newURL.path error:&fileManagerError];
        }];
        
        NSError *error = fileCoordinatorError ? : fileManagerError ? : nil;
        error = [self specializedErrorForCocoaError:error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (block) block(error);
        });
    }];
}

- (void)uploadLocalFile:(NSString *)fromPath toPath:(NSString *)toPath completion:(CDECompletionBlock)block
{
    [operationQueue addOperationWithBlock:^{
        if (!self.isConnected || !rootDirectoryURL) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (block) block([self notConnectedError]);
            });
            return;
        }
        
        NSError *fileCoordinatorError = nil;
        __block NSError *fileManagerError = nil;
        
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:self];
        
        NSURL *fromURL = [NSURL fileURLWithPath:fromPath];
        NSURL *toURL = [NSURL fileURLWithPath:[self fullPathForPath:toPath]];
        NSString *path = [toURL.path stringByStandardizingPath];
        [locallyModifiedPaths addObject:path];
        
        [coordinator cde_coordinateReadingItemAtURL:fromURL options:0 writingItemAtURL:toURL options:NSFileCoordinatorWritingForReplacing timeout:CDEFileCoordinatorTimeOut error:&fileCoordinatorError byAccessor:^(NSURL *newReadingURL, NSURL *newWritingURL) {
            [fileManager removeItemAtPath:newWritingURL.path error:NULL];
            [fileManager copyItemAtPath:newReadingURL.path toPath:newWritingURL.path error:&fileManagerError];
        }];
        
        NSError *error = fileCoordinatorError ? : fileManagerError ? : nil;
        error = [self specializedErrorForCocoaError:error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (block) block(error);
        });
    }];
}

- (void)downloadFromPath:(NSString *)fromPath toLocalFile:(NSString *)toPath completion:(CDECompletionBlock)block
{
    [operationQueue addOperationWithBlock:^{
        if (!self.isConnected || !rootDirectoryURL) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (block) block([self notConnectedError]);
            });
            return;
        }
        
        NSError *fileCoordinatorError = nil;
        __block NSError *fileManagerError = nil;
        
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:self];
        
        NSURL *fromURL = [NSURL fileURLWithPath:[self fullPathForPath:fromPath]];
        NSURL *toURL = [NSURL fileURLWithPath:toPath];
        [coordinator cde_coordinateReadingItemAtURL:fromURL options:0 writingItemAtURL:toURL options:NSFileCoordinatorWritingForReplacing timeout:CDEFileCoordinatorTimeOut error:&fileCoordinatorError byAccessor:^(NSURL *newReadingURL, NSURL *newWritingURL) {
            [fileManager removeItemAtPath:newWritingURL.path error:NULL];
            [fileManager copyItemAtPath:newReadingURL.path toPath:newWritingURL.path error:&fileManagerError];
        }];
        
        NSError *error = fileCoordinatorError ? : fileManagerError ? : nil;
        error = [self specializedErrorForCocoaError:error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (block) block(error);
        });
    }];
}

@end
