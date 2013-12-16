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

@implementation CDEICloudFileSystem {
    NSFileManager *fileManager;
    NSURL *rootDirectoryURL;
    NSMetadataQuery *metadataQuery;
    NSOperationQueue *operationQueue;
    NSString *ubiquityContainerIdentifier;
    dispatch_queue_t timeOutQueue;
    id ubiquityIdentityObserver;
}

- (instancetype)initWithUbiquityContainerIdentifier:(NSString *)newIdentifier
{
    self = [super init];
    if (self) {
        fileManager = [[NSFileManager alloc] init];
        
        operationQueue = [[NSOperationQueue alloc] init];
        operationQueue.maxConcurrentOperationCount = 1;
        
        timeOutQueue = dispatch_queue_create("com.mentalfaculty.ensembles.queue.icloudtimeout", DISPATCH_QUEUE_SERIAL);
        
        rootDirectoryURL = nil;
        metadataQuery = nil;
        ubiquityContainerIdentifier = [newIdentifier copy];
        ubiquityIdentityObserver = nil;
        
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
    return [fileManager ubiquityIdentityToken];
}

#pragma mark - Initial Preparation

- (void)performInitialPreparation:(CDECompletionBlock)completion
{
    if (fileManager.ubiquityIdentityToken) {
        [self setupRootDirectory:^{
            [self startMonitoringMetadata];
            [self addUbiquityContainerNotificationObservers];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(nil);
            });
        }];
    }
    else {
        [self addUbiquityContainerNotificationObservers];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(nil);
        });
    }
}

#pragma mark - Root Directory

- (void)setupRootDirectory:(CDECodeBlock)completion
{
    [operationQueue addOperationWithBlock:^{
        NSURL *newURL = [fileManager URLForUbiquityContainerIdentifier:ubiquityContainerIdentifier];
        newURL = [newURL URLByAppendingPathComponent:@"com.mentalfaculty.ensembles.clouddata"];
        rootDirectoryURL = newURL;
        NSAssert(rootDirectoryURL, @"Could not retrieve URLForUbiquityContainerIdentifier. Check container id for iCloud");
                 
        NSError *error = nil;
        __block BOOL fileExistsAtPath = NO;
        __block BOOL existingFileIsDirectory = NO;
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        [coordinator coordinateReadingItemAtURL:rootDirectoryURL options:NSFileCoordinatorReadingWithoutChanges error:&error byAccessor:^(NSURL *newURL) {
            fileExistsAtPath = [fileManager fileExistsAtPath:newURL.path isDirectory:&existingFileIsDirectory];
        }];
        if (error) CDELog(CDELoggingLevelWarning, @"File coordinator error: %@", error);
        
        error = nil;
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
        
        dispatch_sync(dispatch_get_main_queue(), ^{
            if (completion) completion();
        });
    }];
}

- (NSString *)fullPathForPath:(NSString *)path
{
    return [rootDirectoryURL.path stringByAppendingPathComponent:path];
}

#pragma mark - Notifications

- (void)removeUbiquityContainerNotificationObservers
{
    [[NSNotificationCenter defaultCenter] removeObserver:ubiquityIdentityObserver];
    ubiquityIdentityObserver = nil;
}

- (void)addUbiquityContainerNotificationObservers
{
    [self removeUbiquityContainerNotificationObservers];
    
    __weak typeof(self) weakSelf = self;
    ubiquityIdentityObserver = [[NSNotificationCenter defaultCenter] addObserverForName:NSUbiquityIdentityDidChangeNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf stopMonitoring];
        [strongSelf willChangeValueForKey:@"identityToken"];
        [strongSelf didChangeValueForKey:@"identityToken"];
    }];
}

#pragma mark - Connection

- (BOOL)isConnected
{
    return fileManager.ubiquityIdentityToken != nil;
}

- (void)connect:(CDECompletionBlock)completion
{
    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL loggedIn = fileManager.ubiquityIdentityToken != nil;
        NSError *error = loggedIn ? nil : [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeAuthenticationFailure userInfo:@{NSLocalizedDescriptionKey : NSLocalizedString(@"User is not logged into iCloud.", @"")} ];
        if (completion) completion(error);
    });
}

#pragma mark - Metadata Query to download new files

- (void)startMonitoringMetadata
{
    [self stopMonitoring];
 
    if (!rootDirectoryURL) return;
    
    // Determine downloading key. This is OS dependent.
    NSString *isDownloadedKey = nil;
    
    #if (__IPHONE_OS_VERSION_MIN_REQUIRED < 30000) && (__MAC_OS_X_VERSION_MIN_REQUIRED < 1090)
        isDownloadedKey = NSMetadataUbiquitousItemIsDownloadedKey;
    #else
        isDownloadedKey = NSMetadataUbiquitousItemDownloadingStatusDownloaded;
    #endif
    
    metadataQuery = [[NSMetadataQuery alloc] init];
    metadataQuery.notificationBatchingInterval = 10.0;
    metadataQuery.searchScopes = [NSArray arrayWithObject:NSMetadataQueryUbiquitousDataScope];
    metadataQuery.predicate = [NSPredicate predicateWithFormat:@"%K = FALSE AND %K = FALSE AND %K ENDSWITH '.cdeevent' AND %K BEGINSWITH %@",
        isDownloadedKey, NSMetadataUbiquitousItemIsDownloadingKey, NSMetadataItemFSNameKey, NSMetadataItemPathKey, rootDirectoryURL.path];
    
    NSNotificationCenter *notifationCenter = [NSNotificationCenter defaultCenter];
    [notifationCenter addObserver:self selector:@selector(initiateDownloads:) name:NSMetadataQueryDidFinishGatheringNotification object:metadataQuery];
    [notifationCenter addObserver:self selector:@selector(initiateDownloads:) name:NSMetadataQueryDidUpdateNotification object:metadataQuery];
    
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

- (void)initiateDownloads:(NSNotification *)notif
{
    [metadataQuery disableUpdates];
    
    NSUInteger count = [metadataQuery resultCount];
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0);
    for ( NSUInteger i = 0; i < count; i++ ) {
        @autoreleasepool {
            NSURL *url = [metadataQuery valueOfAttribute:NSMetadataItemURLKey forResultAtIndex:i];
            dispatch_async(queue, ^{
                NSError *error;
                BOOL startedDownload = [fileManager startDownloadingUbiquitousItemAtURL:url error:&error];
                if ( !startedDownload ) CDELog(CDELoggingLevelWarning, @"Error starting download: %@", error);
            });
        }
    }

    [metadataQuery enableUpdates];
}

#pragma mark - File Operations

static const NSTimeInterval CDEFileCoordinatorTimeOut = 2.0;

- (void)startTimeOutForCoordinator:(NSFileCoordinator *)coordinator hasExecuted:(BOOL *)coordinatorExecuted isTimedOut:(BOOL *)timedOut
{
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, CDEFileCoordinatorTimeOut * NSEC_PER_SEC);
    dispatch_after(popTime, timeOutQueue, ^{
        if (!(*coordinatorExecuted)) {
            [coordinator cancel];
            *timedOut = YES;
        }
    });
}

- (BOOL)beginExecutingCoordinatorBlockWithHasExecuted:(BOOL *)coordinatorExecuted isTimedOut:(BOOL *)timedOut error:(NSError * __autoreleasing *)error
{
    dispatch_sync(timeOutQueue, ^{
        *coordinatorExecuted = YES;
    });
    BOOL result = !(*timedOut);
    if (!result && error) *error = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeFileCoordinatorTimedOut userInfo:nil];
    return result;
}

- (void)fileExistsAtPath:(NSString *)path completion:(void(^)(BOOL exists, BOOL isDirectory, NSError *error))block
{
    [operationQueue addOperationWithBlock:^{
        NSError *fileCoordinatorError = nil;
        __block NSError *timeoutError = nil;
        
        NSURL *url = [NSURL fileURLWithPath:[self fullPathForPath:path]];
        
        __block BOOL coordinatorExecuted = NO;
        __block BOOL timedOut = NO;
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        [self startTimeOutForCoordinator:coordinator hasExecuted:&coordinatorExecuted isTimedOut:&timedOut];

        __block BOOL isDirectory = NO;
        __block BOOL exists = NO;
        [coordinator coordinateReadingItemAtURL:url options:0 error:&fileCoordinatorError byAccessor:^(NSURL *newURL) {
            if (![self beginExecutingCoordinatorBlockWithHasExecuted:&coordinatorExecuted isTimedOut:&timedOut error:&timeoutError]) return;
            exists = [fileManager fileExistsAtPath:newURL.path isDirectory:&isDirectory];
        }];
        
        NSError *error = fileCoordinatorError ? : timeoutError ? : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (block) block(exists, isDirectory, error);
        });
    }];
}

- (void)contentsOfDirectoryAtPath:(NSString *)path completion:(void(^)(NSArray *contents, NSError *error))block
{
    [operationQueue addOperationWithBlock:^{
        NSError *fileCoordinatorError = nil;
        __block NSError *timeoutError = nil;
        __block NSError *fileManagerError = nil;
        
        NSURL *url = [NSURL fileURLWithPath:[self fullPathForPath:path]];
        
        __block BOOL coordinatorExecuted = NO;
        __block BOOL timedOut = NO;
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        [self startTimeOutForCoordinator:coordinator hasExecuted:&coordinatorExecuted isTimedOut:&timedOut];
        
        __block NSArray *contents = nil;
        [coordinator coordinateReadingItemAtURL:url options:0 error:&fileCoordinatorError byAccessor:^(NSURL *newURL) {
            if (![self beginExecutingCoordinatorBlockWithHasExecuted:&coordinatorExecuted isTimedOut:&timedOut error:&timeoutError]) return;
            
            NSDirectoryEnumerator *dirEnum = [fileManager enumeratorAtPath:[self fullPathForPath:path]];
            if (!dirEnum) fileManagerError = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeFileAccessFailed userInfo:nil];
            
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
        dispatch_async(dispatch_get_main_queue(), ^{
            if (block) block(contents, error);
        });
    }];

}

- (void)createDirectoryAtPath:(NSString *)path completion:(CDECompletionBlock)block
{
    [operationQueue addOperationWithBlock:^{
        NSError *fileCoordinatorError = nil;
        __block NSError *timeoutError = nil;
        __block NSError *fileManagerError = nil;
        
        NSURL *url = [NSURL fileURLWithPath:[self fullPathForPath:path]];
        
        __block BOOL coordinatorExecuted = NO;
        __block BOOL timedOut = NO;
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        [self startTimeOutForCoordinator:coordinator hasExecuted:&coordinatorExecuted isTimedOut:&timedOut];
        
        [coordinator coordinateWritingItemAtURL:url options:0 error:&fileCoordinatorError byAccessor:^(NSURL *newURL) {
            if (![self beginExecutingCoordinatorBlockWithHasExecuted:&coordinatorExecuted isTimedOut:&timedOut error:&timeoutError]) return;
            [fileManager createDirectoryAtPath:newURL.path withIntermediateDirectories:NO attributes:nil error:&fileManagerError];
        }];
        
        NSError *error = fileCoordinatorError ? : timeoutError ? : fileManagerError ? : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (block) block(error);
        });
    }];
}

- (void)removeItemAtPath:(NSString *)path completion:(CDECompletionBlock)block
{
    [operationQueue addOperationWithBlock:^{
        NSError *fileCoordinatorError = nil;
        __block NSError *timeoutError = nil;
        __block NSError *fileManagerError = nil;
        
        NSURL *url = [NSURL fileURLWithPath:[self fullPathForPath:path]];
        
        __block BOOL coordinatorExecuted = NO;
        __block BOOL timedOut = NO;
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        [self startTimeOutForCoordinator:coordinator hasExecuted:&coordinatorExecuted isTimedOut:&timedOut];
        
        [coordinator coordinateWritingItemAtURL:url options:NSFileCoordinatorWritingForDeleting error:&fileCoordinatorError byAccessor:^(NSURL *newURL) {
            if (![self beginExecutingCoordinatorBlockWithHasExecuted:&coordinatorExecuted isTimedOut:&timedOut error:&timeoutError]) return;
            [fileManager removeItemAtPath:newURL.path error:&fileManagerError];
        }];
        
        NSError *error = fileCoordinatorError ? : timeoutError ? : fileManagerError ? : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (block) block(error);
        });
    }];
}

- (void)uploadLocalFile:(NSString *)fromPath toPath:(NSString *)toPath completion:(CDECompletionBlock)block
{
    [operationQueue addOperationWithBlock:^{
        NSError *fileCoordinatorError = nil;
        __block NSError *timeoutError = nil;
        __block NSError *fileManagerError = nil;
        
        NSURL *fromURL = [NSURL fileURLWithPath:fromPath];
        NSURL *toURL = [NSURL fileURLWithPath:[self fullPathForPath:toPath]];

        __block BOOL coordinatorExecuted = NO;
        __block BOOL timedOut = NO;
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        [self startTimeOutForCoordinator:coordinator hasExecuted:&coordinatorExecuted isTimedOut:&timedOut];
        
        [coordinator coordinateReadingItemAtURL:fromURL options:0 writingItemAtURL:toURL options:NSFileCoordinatorWritingForReplacing error:&fileCoordinatorError byAccessor:^(NSURL *newReadingURL, NSURL *newWritingURL) {
            if (![self beginExecutingCoordinatorBlockWithHasExecuted:&coordinatorExecuted isTimedOut:&timedOut error:&timeoutError]) return;
            
            [fileManager removeItemAtPath:newWritingURL.path error:NULL];
            [fileManager copyItemAtPath:newReadingURL.path toPath:newWritingURL.path error:&fileManagerError];
        }];
        
        NSError *error = fileCoordinatorError ? : timeoutError ? : fileManagerError ? : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (block) block(error);
        });
    }];
}

- (void)downloadFromPath:(NSString *)fromPath toLocalFile:(NSString *)toPath completion:(CDECompletionBlock)block
{
    [operationQueue addOperationWithBlock:^{
        NSError *fileCoordinatorError = nil;
        __block NSError *timeoutError = nil;
        __block NSError *fileManagerError = nil;
        
        NSURL *fromURL = [NSURL fileURLWithPath:[self fullPathForPath:fromPath]];
        NSURL *toURL = [NSURL fileURLWithPath:toPath];
        
        __block BOOL coordinatorExecuted = NO;
        __block BOOL timedOut = NO;
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        [self startTimeOutForCoordinator:coordinator hasExecuted:&coordinatorExecuted isTimedOut:&timedOut];
        
        [coordinator coordinateReadingItemAtURL:fromURL options:0 writingItemAtURL:toURL options:NSFileCoordinatorWritingForReplacing error:&fileCoordinatorError byAccessor:^(NSURL *newReadingURL, NSURL *newWritingURL) {
            if (![self beginExecutingCoordinatorBlockWithHasExecuted:&coordinatorExecuted isTimedOut:&timedOut error:&timeoutError]) return;

            [fileManager removeItemAtPath:newWritingURL.path error:NULL];
            [fileManager copyItemAtPath:newReadingURL.path toPath:newWritingURL.path error:&fileManagerError];
        }];
        
        NSError *error = fileCoordinatorError ? : timeoutError ? : fileManagerError ? : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (block) block(error);
        });
    }];
}

@end
