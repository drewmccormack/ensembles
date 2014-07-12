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
    NSString *ubiquityContainerIdentifier;
    dispatch_queue_t timeOutQueue;
    dispatch_queue_t initiatingDownloadsQueue;
    id ubiquityIdentityObserver;
    NSOperationQueue *downloadTrackingQueue;
    NSDate *lastProgressNotificationDate;
    NSMutableSet *downloadingURLs, *handlingURLs;
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
        
        downloadTrackingQueue = [[NSOperationQueue alloc] init];
        downloadTrackingQueue.maxConcurrentOperationCount = 1;
        
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
        
        [self performInitialPreparation:NULL];
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
            loggedIn = [fileManager ubiquityIdentityToken] != nil;
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

#pragma mark - Root Directory

- (void)setupRootDirectory:(CDECompletionBlock)completion
{
    [operationQueue addOperationWithBlock:^{
        NSURL *newURL = [fileManager URLForUbiquityContainerIdentifier:ubiquityContainerIdentifier];
        newURL = [newURL URLByAppendingPathComponent:relativePathToRootInContainer];
        rootDirectoryURL = newURL;
        if (!rootDirectoryURL) {
            NSError *error = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeServerError userInfo:@{NSLocalizedDescriptionKey : @"Could not retrieve URLForUbiquityContainerIdentifier. Check container id for iCloud."}];
            CDELog(CDELoggingLevelError, @"Failed to get the URL of the iCloud ubiquity container: %@", error);
            [self dispatchCompletion:completion withError:error];
            return;
        }
        
        NSError *error = nil;
        __block BOOL fileExistsAtPath = NO;
        __block BOOL existingFileIsDirectory = NO;
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        [coordinator coordinateReadingItemAtURL:rootDirectoryURL options:NSFileCoordinatorReadingWithoutChanges error:&error byAccessor:^(NSURL *newURL) {
            fileExistsAtPath = [fileManager fileExistsAtPath:newURL.path isDirectory:&existingFileIsDirectory];
        }];
        if (error) {
            CDELog(CDELoggingLevelWarning, @"File coordinator error: %@", error);
            [self dispatchCompletion:completion withError:error];
            return;
        }
        
        if (!fileExistsAtPath) {
            [coordinator coordinateWritingItemAtURL:rootDirectoryURL options:0 error:&error byAccessor:^(NSURL *newURL) {
                [fileManager createDirectoryAtURL:newURL withIntermediateDirectories:YES attributes:nil error:NULL];
            }];
        }
        else if (fileExistsAtPath && !existingFileIsDirectory) {
            [coordinator coordinateWritingItemAtURL:rootDirectoryURL options:NSFileCoordinatorWritingForReplacing error:&error byAccessor:^(NSURL *newURL) {
                [fileManager removeItemAtURL:newURL error:NULL];
                [fileManager createDirectoryAtURL:newURL withIntermediateDirectories:YES attributes:nil error:NULL];
            }];
        }
        if (error) CDELog(CDELoggingLevelWarning, @"File coordinator error: %@", error);
        
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
    
    if (&NSUbiquityIdentityDidChangeNotification != NULL) {
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
        error = loggedIn && !error ? nil : [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeAuthenticationFailure userInfo:@{NSLocalizedDescriptionKey : NSLocalizedString(@"User is not logged into iCloud.", @"")} ];
        if (completion) completion(error);
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
}

- (void)stopMonitoring
{
    if (!metadataQuery) return;
    
    [metadataQuery disableUpdates];
    [metadataQuery stopQuery];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSMetadataQueryDidFinishGatheringNotification object:metadataQuery];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSMetadataQueryDidUpdateNotification object:metadataQuery];
    
    metadataQuery = nil;
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
            NSNumber *downloaded = [metadataQuery valueOfAttribute:NSMetadataUbiquitousItemIsDownloadedKey forResultAtIndex:i];
            NSNumber *fileSizeNumber = [metadataQuery valueOfAttribute:NSMetadataItemFSSizeKey forResultAtIndex:i];
            
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
                        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
                        NSError *error = nil;
                        __block BOOL complete = NO;
                        [coordinator coordinateReadingItemAtURL:url options:0 error:&error byAccessor:^(NSURL *newURL) {
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
                                [self performSelector:@selector(postDidDownloadNotification) withObject:nil afterDelay:2.0];
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
    NSDate *now = [NSDate date];
    if (!lastProgressNotificationDate || [now timeIntervalSinceDate:lastProgressNotificationDate] > 2.0) {
        lastProgressNotificationDate = now;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self postDidMakeDownloadProgressNotification];
        });
    }
}

- (void)postDidDownloadNotification
{
    [self postDidMakeDownloadProgressNotification];
    lastProgressNotificationDate = nil;
    
    [[NSNotificationCenter defaultCenter] postNotificationName:CDEICloudFileSystemDidDownloadFilesNotification object:self];
    
    [self startMonitoringMetadata]; // Refresh query, which often gets 'stuck'
}

- (void)postDidMakeDownloadProgressNotification
{
    [[NSNotificationCenter defaultCenter] postNotificationName:CDEICloudFileSystemDidMakeDownloadProgressNotification object:self];
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
        if (!self.isConnected) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (block) block(NO, NO, [self notConnectedError]);
            });
            return;
        }
        
        NSError *fileCoordinatorError = nil;
        __block NSError *timeoutError = nil;
        __block BOOL coordinatorExecuted = NO;
        __block BOOL isDirectory = NO;
        __block BOOL exists = NO;
        
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, CDEFileCoordinatorTimeOut * NSEC_PER_SEC);
        dispatch_after(popTime, timeOutQueue, ^{
            if (!coordinatorExecuted) {
                [coordinator cancel];
                timeoutError = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeFileCoordinatorTimedOut userInfo:nil];
            }
        });
        
        NSURL *url = [NSURL fileURLWithPath:[self fullPathForPath:path]];
        [coordinator coordinateReadingItemAtURL:url options:0 error:&fileCoordinatorError byAccessor:^(NSURL *newURL) {
            dispatch_sync(timeOutQueue, ^{ coordinatorExecuted = YES; });
            if (timeoutError) return;
            exists = [fileManager fileExistsAtPath:newURL.path isDirectory:&isDirectory];
        }];
        
        NSError *error = fileCoordinatorError ? : timeoutError ? : nil;
        error = [self specializedErrorForCocoaError:error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (block) block(exists, isDirectory, error);
        });
    }];
}

- (void)contentsOfDirectoryAtPath:(NSString *)path completion:(void(^)(NSArray *contents, NSError *error))block
{
    [operationQueue addOperationWithBlock:^{
        if (!self.isConnected) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (block) block(nil, [self notConnectedError]);
            });
            return;
        }
        
        NSError *fileCoordinatorError = nil;
        __block NSError *timeoutError = nil;
        __block NSError *fileManagerError = nil;
        __block BOOL coordinatorExecuted = NO;
        
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, CDEFileCoordinatorTimeOut * NSEC_PER_SEC);
        dispatch_after(popTime, timeOutQueue, ^{
            if (!coordinatorExecuted) {
                [coordinator cancel];
                timeoutError = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeFileCoordinatorTimedOut userInfo:nil];
            }
        });
        
        __block NSArray *contents = nil;
        NSURL *url = [NSURL fileURLWithPath:[self fullPathForPath:path]];
        [coordinator coordinateReadingItemAtURL:url options:0 error:&fileCoordinatorError byAccessor:^(NSURL *newURL) {
            dispatch_sync(timeOutQueue, ^{ coordinatorExecuted = YES; });
            if (timeoutError) return;
            
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
        
        NSError *error = fileCoordinatorError ? : timeoutError ? : fileManagerError ? : nil;
        error = [self specializedErrorForCocoaError:error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (block) block(contents, error);
        });
    }];
    
}

- (void)createDirectoryAtPath:(NSString *)path completion:(CDECompletionBlock)block
{
    [operationQueue addOperationWithBlock:^{
        if (!self.isConnected) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (block) block([self notConnectedError]);
            });
            return;
        }
        
        NSError *fileCoordinatorError = nil;
        __block NSError *timeoutError = nil;
        __block NSError *fileManagerError = nil;
        __block BOOL coordinatorExecuted = NO;
        
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, CDEFileCoordinatorTimeOut * NSEC_PER_SEC);
        dispatch_after(popTime, timeOutQueue, ^{
            if (!coordinatorExecuted) {
                [coordinator cancel];
                timeoutError = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeFileCoordinatorTimedOut userInfo:nil];
            }
        });
        
        NSURL *url = [NSURL fileURLWithPath:[self fullPathForPath:path]];
        [coordinator coordinateWritingItemAtURL:url options:0 error:&fileCoordinatorError byAccessor:^(NSURL *newURL) {
            dispatch_sync(timeOutQueue, ^{ coordinatorExecuted = YES; });
            if (timeoutError) return;
            [fileManager createDirectoryAtPath:newURL.path withIntermediateDirectories:NO attributes:nil error:&fileManagerError];
        }];
        
        NSError *error = fileCoordinatorError ? : timeoutError ? : fileManagerError ? : nil;
        error = [self specializedErrorForCocoaError:error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (block) block(error);
        });
    }];
}

- (void)removeItemAtPath:(NSString *)path completion:(CDECompletionBlock)block
{
    [operationQueue addOperationWithBlock:^{
        if (!self.isConnected) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (block) block([self notConnectedError]);
            });
            return;
        }
        
        NSError *fileCoordinatorError = nil;
        __block NSError *timeoutError = nil;
        __block NSError *fileManagerError = nil;
        __block BOOL coordinatorExecuted = NO;
        
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, CDEFileCoordinatorTimeOut * NSEC_PER_SEC);
        dispatch_after(popTime, timeOutQueue, ^{
            if (!coordinatorExecuted) {
                [coordinator cancel];
                timeoutError = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeFileCoordinatorTimedOut userInfo:nil];
            }
        });
        
        NSURL *url = [NSURL fileURLWithPath:[self fullPathForPath:path]];
        [coordinator coordinateWritingItemAtURL:url options:NSFileCoordinatorWritingForDeleting error:&fileCoordinatorError byAccessor:^(NSURL *newURL) {
            dispatch_sync(timeOutQueue, ^{ coordinatorExecuted = YES; });
            if (timeoutError) return;
            [fileManager removeItemAtPath:newURL.path error:&fileManagerError];
        }];
        
        NSError *error = fileCoordinatorError ? : timeoutError ? : fileManagerError ? : nil;
        error = [self specializedErrorForCocoaError:error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (block) block(error);
        });
    }];
}

- (void)uploadLocalFile:(NSString *)fromPath toPath:(NSString *)toPath completion:(CDECompletionBlock)block
{
    [operationQueue addOperationWithBlock:^{
        if (!self.isConnected) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (block) block([self notConnectedError]);
            });
            return;
        }
        
        NSError *fileCoordinatorError = nil;
        __block NSError *timeoutError = nil;
        __block NSError *fileManagerError = nil;
        __block BOOL coordinatorExecuted = NO;
        
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, CDEFileCoordinatorTimeOut * NSEC_PER_SEC);
        dispatch_after(popTime, timeOutQueue, ^{
            if (!coordinatorExecuted) {
                [coordinator cancel];
                timeoutError = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeFileCoordinatorTimedOut userInfo:nil];
            }
        });
        
        NSURL *fromURL = [NSURL fileURLWithPath:fromPath];
        NSURL *toURL = [NSURL fileURLWithPath:[self fullPathForPath:toPath]];
        [coordinator coordinateReadingItemAtURL:fromURL options:0 writingItemAtURL:toURL options:NSFileCoordinatorWritingForReplacing error:&fileCoordinatorError byAccessor:^(NSURL *newReadingURL, NSURL *newWritingURL) {
            dispatch_sync(timeOutQueue, ^{ coordinatorExecuted = YES; });
            if (timeoutError) return;
            [fileManager removeItemAtPath:newWritingURL.path error:NULL];
            [fileManager copyItemAtPath:newReadingURL.path toPath:newWritingURL.path error:&fileManagerError];
        }];
        
        NSError *error = fileCoordinatorError ? : timeoutError ? : fileManagerError ? : nil;
        error = [self specializedErrorForCocoaError:error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (block) block(error);
        });
    }];
}

- (void)downloadFromPath:(NSString *)fromPath toLocalFile:(NSString *)toPath completion:(CDECompletionBlock)block
{
    [operationQueue addOperationWithBlock:^{
        if (!self.isConnected) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (block) block([self notConnectedError]);
            });
            return;
        }
        
        NSError *fileCoordinatorError = nil;
        __block NSError *timeoutError = nil;
        __block NSError *fileManagerError = nil;
        __block BOOL coordinatorExecuted = NO;
        
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, CDEFileCoordinatorTimeOut * NSEC_PER_SEC);
        dispatch_after(popTime, timeOutQueue, ^{
            if (!coordinatorExecuted) {
                [coordinator cancel];
                timeoutError = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeFileCoordinatorTimedOut userInfo:nil];
            }
        });
        
        NSURL *fromURL = [NSURL fileURLWithPath:[self fullPathForPath:fromPath]];
        NSURL *toURL = [NSURL fileURLWithPath:toPath];
        [coordinator coordinateReadingItemAtURL:fromURL options:0 writingItemAtURL:toURL options:NSFileCoordinatorWritingForReplacing error:&fileCoordinatorError byAccessor:^(NSURL *newReadingURL, NSURL *newWritingURL) {
            dispatch_sync(timeOutQueue, ^{ coordinatorExecuted = YES; });
            if (timeoutError) return;
            [fileManager removeItemAtPath:newWritingURL.path error:NULL];
            [fileManager copyItemAtPath:newReadingURL.path toPath:newWritingURL.path error:&fileManagerError];
        }];
        
        NSError *error = fileCoordinatorError ? : timeoutError ? : fileManagerError ? : nil;
        error = [self specializedErrorForCocoaError:error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (block) block(error);
        });
    }];
}

@end
