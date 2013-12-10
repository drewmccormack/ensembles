//
//  CDECloudManager.m
//  Test App iOS
//
//  Created by Drew McCormack on 5/29/13.
//  Copyright (c) 2013 The Mental Faculty B.V. All rights reserved.
//

#import "CDECloudManager.h"
#import "CDEEventStore.h"
#import "CDECloudFileSystem.h"
#import "CDEAsynchronousTaskQueue.h"
#import "CDEStoreModificationEvent.h"
#import "CDEEventRevision.h"
#import "CDERevision.h"
#import "CDEEventMigrator.h"

@interface CDECloudManager ()

@property (nonatomic, strong, readonly) NSString *localEnsembleDirectory;

@property (nonatomic, strong, readonly) NSString *localDownloadRoot;
@property (nonatomic, strong, readonly) NSString *localStoresDownloadDirectory;
@property (nonatomic, strong, readonly) NSString *localEventsDownloadDirectory;

@property (nonatomic, strong, readonly) NSString *localUploadRoot;
@property (nonatomic, strong, readonly) NSString *localStoresUploadDirectory;
@property (nonatomic, strong, readonly) NSString *localEventsUploadDirectory;

@property (nonatomic, strong, readonly) NSString *remoteEnsembleDirectory;
@property (nonatomic, strong, readonly) NSString *remoteStoresDirectory;
@property (nonatomic, strong, readonly) NSString *remoteEventsDirectory;

@end

@implementation CDECloudManager {
    NSString *localFileRoot;
    NSFileManager *fileManager;
    NSOperationQueue *operationQueue;
}

@synthesize eventStore = eventStore;
@synthesize cloudFileSystem = cloudFileSystem;

#pragma mark Initialization

- (instancetype)initWithEventStore:(CDEEventStore *)newStore cloudFileSystem:(id <CDECloudFileSystem>)newSystem
{
    self = [super init];
    if (self) {
        fileManager = [[NSFileManager alloc] init];
        eventStore = newStore;
        cloudFileSystem = newSystem;
        localFileRoot = [eventStore.pathToEventDataRootDirectory stringByAppendingPathComponent:@"transitcache"];
        operationQueue = [[NSOperationQueue alloc] init];
        operationQueue.maxConcurrentOperationCount = 1;
        [self createTransitCacheDirectories];
    }
    return self;
}

#pragma mark Retrieving Remote Files

- (void)importNewRemoteEventsWithCompletion:(CDECompletionBlock)completion
{
    NSAssert([NSThread isMainThread], @"importNewRemote... called off the main thread");
    
    CDELog(CDELoggingLevelVerbose, @"Transferring new events from cloud to event store");

    [self transferNewRemoteFilesToTransitCacheWithCompletion:^(NSError *error) {
        if (error) {
            if (completion) completion(error);
            return;
        }
        [self migrateNewEventsFromTransitCacheWithCompletion:completion];
    }];
}

- (void)transferNewRemoteFilesToTransitCacheWithCompletion:(CDECompletionBlock)completion
{
    [self.cloudFileSystem contentsOfDirectoryAtPath:self.remoteEventsDirectory completion:^(NSArray *contents, NSError *error) {
        if (error) {
            if (completion) completion(error);
        }
        else {
            NSArray *filenames = [contents valueForKeyPath:@"name"];
            NSArray *filenamesToRetrieve = [self filesRequiringRetrievalFromAvailableRemoteFiles:filenames];
            [self transferRemoteEventFiles:filenamesToRetrieve toTransitCacheWithCompletion:completion];
        }
    }];
}

- (void)transferRemoteEventFiles:(NSArray *)filenames toTransitCacheWithCompletion:(CDECompletionBlock)completion
{
    // Remove any existing files in the cache first
    NSError *error = nil;
    BOOL success = [self removeFilesInDirectory:self.localEventsDownloadDirectory error:&error];
    if (!success) {
        if (completion) completion(error);
        return;
    }
    
    NSMutableArray *taskBlocks = [NSMutableArray array];
    for (NSString *filename in filenames) {
        NSString *remotePath = [self.remoteEventsDirectory stringByAppendingPathComponent:filename];
        NSString *localPath = [self.localEventsDownloadDirectory stringByAppendingPathComponent:filename];
        CDEAsynchronousTaskBlock block = ^(CDEAsynchronousTaskCallbackBlock next) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.cloudFileSystem downloadFromPath:remotePath toLocalFile:localPath completion:^(NSError *error) {
                    next(error, NO);
                }];
            });
        };
        [taskBlocks addObject:block];
    }
    
    CDEAsynchronousTaskQueue *taskQueue = [[CDEAsynchronousTaskQueue alloc] initWithTasks:taskBlocks terminationPolicy:CDETaskQueueTerminationPolicyStopOnError completion:CDEMainQueueCompletionFromCompletion(completion)];
    [operationQueue addOperation:taskQueue];
}

- (NSArray *)filesRequiringRetrievalFromAvailableRemoteFiles:(NSArray *)remoteFiles
{
    NSMutableSet *toRetrieve = [NSMutableSet setWithArray:remoteFiles];
    NSSet *storeFilenames = [self filenamesForAllStoreModificationEventsCreatedInStore:nil];
    [toRetrieve minusSet:storeFilenames];
    return [self sortFilenamesByGlobalCount:toRetrieve.allObjects];
}

- (void)migrateNewEventsFromTransitCacheWithCompletion:(CDECompletionBlock)completion
{
    NSError *error = nil;
    NSArray *files = [fileManager contentsOfDirectoryAtPath:self.localEventsDownloadDirectory error:&error];
    
    NSManagedObjectContext *moc = self.eventStore.managedObjectContext;
    CDEEventMigrator *migrator = [[CDEEventMigrator alloc] initWithEventStore:self.eventStore];
    
    NSMutableArray *tasks = [[NSMutableArray alloc] initWithCapacity:files.count];
    for (NSString *file in files) {
        NSString *path = [self.localEventsDownloadDirectory stringByAppendingPathComponent:file];
        
        CDEAsynchronousTaskBlock block = ^(CDEAsynchronousTaskCallbackBlock next) {
            CDEGlobalCount globalCount;
            CDERevision *revision;
            BOOL isEventFile = [self count:&globalCount andRevision:&revision fromFilename:file];
            if (!isEventFile) {
                next(nil, NO);
                return;
            }
            
            // Check for a pre-existing event first. Skip if we find one.
            __block BOOL eventExists = NO;
            [moc performBlockAndWait:^{
                CDEStoreModificationEvent *existingEvent = [CDEStoreModificationEvent fetchStoreModificationEventForPersistentStoreIdentifier:revision.persistentStoreIdentifier revisionNumber:revision.revisionNumber inManagedObjectContext:moc];
                eventExists = existingEvent != nil;
            }];
            
            if (eventExists) {
                [fileManager removeItemAtPath:path error:NULL];
                next(nil, NO);
                return;
            }
            
            // Migrate data into event store
            dispatch_async(dispatch_get_main_queue(), ^{
                [migrator migrateEventsInFromFiles:@[path] completion:^(NSError *error) {
                    [fileManager removeItemAtPath:path error:NULL];
                    next(error, NO);
                }];
            });
        };
        
        [tasks addObject:block];
    }
    
    CDEAsynchronousTaskQueue *taskQueue = [[CDEAsynchronousTaskQueue alloc] initWithTasks:tasks terminationPolicy:CDETaskQueueTerminationPolicyCompleteAll completion:CDEMainQueueCompletionFromCompletion(completion)];
    [operationQueue addOperation:taskQueue];
}


#pragma mark Uploading Local Events

- (void)exportNewLocalEventsWithCompletion:(CDECompletionBlock)completion
{
    CDELog(CDELoggingLevelVerbose, @"Transferring events from event store to cloud");

    [self migrateNewLocalEventsToTransitCacheWithCompletion:^(NSError *error) {
        if (error) CDELog(CDELoggingLevelWarning, @"Error migrating out events: %@", error);
        [self transferFilesInTransitCacheToCloudWithCompletion:completion];
    }];
}

- (void)migrateNewLocalEventsToTransitCacheWithCompletion:(CDECompletionBlock)completion
{
    [self.cloudFileSystem contentsOfDirectoryAtPath:self.remoteEventsDirectory completion:^(NSArray *contents, NSError *error) {
        if (error) {
            if (completion) completion(error);
        }
        else {
            NSArray *filenamesToUpload = [self localEventFilesMissingFromRemoteCloudFiles:contents];
            [self migrateLocalEventsForFilenames:filenamesToUpload toTransitCacheWithCompletion:completion];
        }
    }];
}

- (void)migrateLocalEventsForFilenames:(NSArray *)filesToUpload toTransitCacheWithCompletion:(CDECompletionBlock)completion
{
    // Remove any existing files in the cache first
    NSError *error = nil;
    BOOL success = [self removeFilesInDirectory:self.localEventsUploadDirectory error:&error];
    if (!success) {
        if (completion) completion(error);
        return;
    }
    
    // Migrate events to file
    CDEEventMigrator *migrator = [[CDEEventMigrator alloc] initWithEventStore:self.eventStore];
    
    NSMutableArray *tasks = [[NSMutableArray alloc] initWithCapacity:filesToUpload.count];
    for (NSString *file in filesToUpload) {
        NSString *path = [self.localEventsUploadDirectory stringByAppendingPathComponent:file];
        
        CDEAsynchronousTaskBlock block = ^(CDEAsynchronousTaskCallbackBlock next) {
            CDEGlobalCount globalCount;
            CDERevision *revision;
            BOOL isEventFile = [self count:&globalCount andRevision:&revision fromFilename:file];
            NSAssert(isEventFile, @"Filename was not in correct form");
            
            // Migrate data to file
            [fileManager removeItemAtPath:path error:NULL];
            dispatch_async(dispatch_get_main_queue(), ^{
                [migrator migrateLocalEventWithRevision:revision.revisionNumber toFile:path completion:^(NSError *error) {
                    next(error, NO);
                }];
            });
        };
        
        [tasks addObject:block];
    }
    
    CDEAsynchronousTaskQueue *taskQueue = [[CDEAsynchronousTaskQueue alloc] initWithTasks:tasks terminationPolicy:CDETaskQueueTerminationPolicyCompleteAll completion:CDEMainQueueCompletionFromCompletion(completion)];
    [operationQueue addOperation:taskQueue];
}

- (void)transferFilesInTransitCacheToCloudWithCompletion:(CDECompletionBlock)completion
{
    NSError *error = nil;
    NSArray *files = [fileManager contentsOfDirectoryAtPath:self.localEventsUploadDirectory error:&error];
    files = [self sortFilenamesByGlobalCount:files];
    
    NSMutableArray *taskBlocks = [NSMutableArray array];
    for (NSString *filename in files) {
        NSString *remotePath = [self.remoteEventsDirectory stringByAppendingPathComponent:filename];
        NSString *localPath = [self.localEventsUploadDirectory stringByAppendingPathComponent:filename];
        CDEAsynchronousTaskBlock block = ^(CDEAsynchronousTaskCallbackBlock next) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.cloudFileSystem uploadLocalFile:localPath toPath:remotePath completion:^(NSError *error) {
                    [fileManager removeItemAtPath:localPath error:NULL];
                    next(error, NO);
                }];
            });
        };
        [taskBlocks addObject:block];
    }
    
    CDEAsynchronousTaskQueue *taskQueue = [[CDEAsynchronousTaskQueue alloc] initWithTasks:taskBlocks terminationPolicy:CDETaskQueueTerminationPolicyStopOnError completion:CDEMainQueueCompletionFromCompletion(completion)];
    [operationQueue addOperation:taskQueue];
}

- (NSArray *)localEventFilesMissingFromRemoteCloudFiles:(NSArray *)remoteFiles
{
    NSString *persistentStoreId = self.eventStore.persistentStoreIdentifier;
    NSMutableSet *filenames = [[self filenamesForAllStoreModificationEventsCreatedInStore:persistentStoreId] mutableCopy];
    
    // Remove remote files to get the missing ones
    NSSet *remoteSet = [NSSet setWithArray:[remoteFiles valueForKeyPath:@"name"]];
    [filenames minusSet:remoteSet];
    
    return [self sortFilenamesByGlobalCount:filenames.allObjects];
}


#pragma mark File Naming

- (NSString *)filenameFromGlobalCount:(CDEGlobalCount)count revision:(CDERevision *)revision
{
    return [NSString stringWithFormat:@"%lli_%@_%lli.cdeevent", count, revision.persistentStoreIdentifier, revision.revisionNumber];
}

- (BOOL)count:(CDEGlobalCount *)count andRevision:(CDERevision * __autoreleasing *)revision fromFilename:(NSString *)filename
{
    NSArray *components = [[filename stringByDeletingPathExtension] componentsSeparatedByString:@"_"];
    if (components.count != 3) {
        *count = 0;
        *revision = nil;
        return NO;
    }
    
    *count = [components[0] longLongValue];
    
    CDERevisionNumber revNumber = [components[2] longLongValue];
    *revision = [[CDERevision alloc] initWithPersistentStoreIdentifier:components[1] revisionNumber:revNumber];
    
    return YES;
}

- (NSArray *)sortFilenamesByGlobalCount:(NSArray *)filenames
{
    NSArray *sortedResult = [filenames sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        CDEGlobalCount g1 = [obj1 longLongValue];
        CDEGlobalCount g2 = [obj2 longLongValue];
        return g1 < g2 ? NSOrderedAscending : (g1 > g2 ? NSOrderedDescending : NSOrderedSame);
    }];
    return sortedResult;
}

- (NSSet *)filenamesForAllStoreModificationEventsCreatedInStore:(NSString *)persistentStoreIdentifier
{
    NSMutableSet *filenames = [[NSMutableSet alloc] init];
    NSManagedObjectContext *moc = self.eventStore.managedObjectContext;
    [moc performBlockAndWait:^{
        NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"CDEStoreModificationEvent"];
        fetch.relationshipKeyPathsForPrefetching = @[@"eventRevision"];
        fetch.propertiesToFetch = @[@"globalCount"];
        
        if (persistentStoreIdentifier) {
            fetch.predicate = [NSPredicate predicateWithFormat:@"eventRevision.persistentStoreIdentifier = %@", persistentStoreIdentifier];
        }
        
        NSArray *events = [moc executeFetchRequest:fetch error:NULL];
        for (CDEStoreModificationEvent *event in events) {
            CDERevision *revision = event.eventRevision.revision;
            NSString *filename = [self filenameFromGlobalCount:event.globalCount revision:revision];
            [filenames addObject:filename];
        }
    }];
    return filenames;
}

#pragma mark Local Directories

- (NSString *)localEnsembleDirectory
{
    return [localFileRoot stringByAppendingPathComponent:self.eventStore.ensembleIdentifier];
}

- (NSString *)localUploadRoot
{
    return [self.localEnsembleDirectory stringByAppendingPathComponent:@"upload"];
}

- (NSString *)localDownloadRoot
{
    return [self.localEnsembleDirectory stringByAppendingPathComponent:@"download"];
}

- (NSString *)localStoresDownloadDirectory
{
    return [self.localDownloadRoot stringByAppendingPathComponent:@"stores"];
}

- (NSString *)localStoresUploadDirectory
{
    return [self.localUploadRoot stringByAppendingPathComponent:@"stores"];
}

- (NSString *)localEventsDownloadDirectory
{
    return [self.localDownloadRoot stringByAppendingPathComponent:@"events"];
}

- (NSString *)localEventsUploadDirectory
{
    return [self.localUploadRoot stringByAppendingPathComponent:@"events"];
}

#pragma mark Local Directory Structure

- (void)createTransitCacheDirectories
{
    [fileManager createDirectoryAtPath:localFileRoot withIntermediateDirectories:YES attributes:nil error:NULL];
    [fileManager createDirectoryAtPath:self.localEventsDownloadDirectory withIntermediateDirectories:YES attributes:nil error:NULL];
    [fileManager createDirectoryAtPath:self.localEventsUploadDirectory withIntermediateDirectories:YES attributes:nil error:NULL];
    [fileManager createDirectoryAtPath:self.localStoresDownloadDirectory withIntermediateDirectories:YES attributes:nil error:NULL];
    [fileManager createDirectoryAtPath:self.localStoresUploadDirectory withIntermediateDirectories:YES attributes:nil error:NULL];
}

- (BOOL)removeFilesInDirectory:(NSString *)dir error:(NSError * __autoreleasing *)error
{
    NSArray *files = [fileManager contentsOfDirectoryAtPath:dir error:error];
    if (!files) return NO;
    
    for (NSString *file in files) {
        if ([file hasPrefix:@"."]) continue; // Ignore system files
        NSString *path = [dir stringByAppendingPathComponent:file];
        BOOL success = [fileManager removeItemAtPath:path error:error];
        if (!success) return NO;
    }
    
    return YES;
}

#pragma mark Remote Directory Structure

- (NSString *)remoteEnsembleDirectory
{
    return [NSString stringWithFormat:@"/%@", self.eventStore.ensembleIdentifier];
}

- (NSString *)remoteStoresDirectory
{
    return [self.remoteEnsembleDirectory stringByAppendingPathComponent:@"stores"];
}

- (NSString *)remoteEventsDirectory
{
    return [self.remoteEnsembleDirectory stringByAppendingPathComponent:@"events"];
}

- (void)createRemoteDirectoryStructureWithCompletion:(CDECompletionBlock)completion
{
    NSArray *dirs = @[self.remoteEnsembleDirectory, self.remoteStoresDirectory, self.remoteEventsDirectory];
    [self createRemoteDirectories:dirs withCompletion:completion];
}

- (void)createRemoteDirectories:(NSArray *)paths withCompletion:(CDECompletionBlock)completion
{
    NSMutableArray *taskBlocks = [NSMutableArray array];
    for (NSString *path in paths) {
        CDEAsynchronousTaskBlock block = ^(CDEAsynchronousTaskCallbackBlock next) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.cloudFileSystem fileExistsAtPath:path completion:^(BOOL exists, BOOL isDirectory, NSError *error) {
                    if (error) {
                        next(error, NO);
                    }
                    else if (!exists) {
                        [self.cloudFileSystem createDirectoryAtPath:path completion:^(NSError *error) {
                            if (error)
                                next(error, NO);
                            else
                                next(nil, NO);
                        }];
                    }
                    else {
                        next(nil, NO);
                    }
                }];
            });
        };
        [taskBlocks addObject:block];
    }
    
    CDEAsynchronousTaskQueue *taskQueue = [[CDEAsynchronousTaskQueue alloc] initWithTasks:taskBlocks terminationPolicy:CDETaskQueueTerminationPolicyStopOnError completion:CDEMainQueueCompletionFromCompletion(completion)];
    [operationQueue addOperation:taskQueue];
}

#pragma mark Store Registration Info

- (void)retrieveRegistrationInfoForStoreWithIdentifier:(NSString *)identifier completion:(void(^)(NSDictionary *info, NSError *error))completion
{
    // Remove any existing files in the cache first
    NSError *error = nil;
    BOOL success = [self removeFilesInDirectory:self.localStoresDownloadDirectory error:&error];
    if (!success) {
        if (completion) completion(nil, error);
        return;
    }
    
    NSString *remotePath = [self.remoteStoresDirectory stringByAppendingPathComponent:identifier];
    NSString *localPath = [self.localStoresDownloadDirectory stringByAppendingPathComponent:identifier];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.cloudFileSystem fileExistsAtPath:remotePath completion:^(BOOL exists, BOOL isDirectory, NSError *error) {
            if (error || !exists) {
                if (completion) completion(nil, error);
                return;
            }
            
            [self.cloudFileSystem downloadFromPath:remotePath toLocalFile:localPath completion:^(NSError *error) {
                NSDictionary *info = nil;
                if (!error) {
                    info = [NSDictionary dictionaryWithContentsOfFile:localPath];
                    [fileManager removeItemAtPath:localPath error:NULL];
                }
                if (completion) completion(info, error);
            }];
        }];
    });
}

- (void)setRegistrationInfo:(NSDictionary *)info forStoreWithIdentifier:(NSString *)identifier completion:(CDECompletionBlock)completion
{
    // Remove any existing files in the cache first
    NSError *error = nil;
    BOOL success = [self removeFilesInDirectory:self.localStoresUploadDirectory error:&error];
    if (!success) {
        if (completion) completion(error);
        return;
    }
    
    NSString *localPath = [self.localStoresUploadDirectory stringByAppendingPathComponent:identifier];
    success = [info writeToFile:localPath atomically:YES];
    if (!success) {
        error = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeFailedToWriteFile userInfo:nil];
        if (completion) completion(error);
        return;
    }

    NSString *remotePath = [self.remoteStoresDirectory stringByAppendingPathComponent:identifier];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.cloudFileSystem uploadLocalFile:localPath toPath:remotePath completion:^(NSError *error) {
            [fileManager removeItemAtPath:localPath error:NULL];
            if (completion) completion(error);
        }];
    });
}

@end
