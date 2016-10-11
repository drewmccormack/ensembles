//
//  CDECloudManager.m
//  Test App iOS
//
//  Created by Drew McCormack on 5/29/13.
//  Copyright (c) 2013 The Mental Faculty B.V. All rights reserved.
//

#import "CDECloudManager.h"
#import "CDEEventFile.h"
#import "CDEFoundationAdditions.h"
#import "CDEEventStore.h"
#import "CDECloudFileSystem.h"
#import "CDEAsynchronousTaskQueue.h"
#import "CDEStoreModificationEvent.h"
#import "CDEEventRevision.h"
#import "CDERevision.h"
#import "CDEEventMigrator.h"

@interface CDECloudManager ()

@property (nonatomic, strong, readwrite) NSSet *snapshotBaselineFilenames;
@property (nonatomic, strong, readwrite) NSSet *snapshotEventFilenames;
@property (nonatomic, strong, readwrite) NSSet *snapshotDataFilenames;

@property (nonatomic, strong, readonly) NSString *localEnsembleDirectory;

@property (nonatomic, strong, readonly) NSString *localDownloadDirectory;
@property (nonatomic, strong, readonly) NSString *localUploadDirectory;

@property (nonatomic, strong, readonly) NSString *remoteStoresDirectory;
@property (nonatomic, strong, readonly) NSString *remoteEventsDirectory;
@property (nonatomic, strong, readonly) NSString *remoteBaselinesDirectory;
@property (nonatomic, strong, readonly) NSString *remoteDataDirectory;

@end

@implementation CDECloudManager {
    NSString *localFileRoot;
    NSFileManager *fileManager;
    NSOperationQueue *operationQueue;
}

@synthesize eventStore = eventStore;
@synthesize cloudFileSystem = cloudFileSystem;
@synthesize snapshotBaselineFilenames = snapshotBaselineFilenames;
@synthesize snapshotEventFilenames = snapshotEventFilenames;
@synthesize snapshotDataFilenames = snapshotDataFilenames;

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
        if ([operationQueue respondsToSelector:@selector(setQualityOfService:)]) {
            [operationQueue setQualityOfService:NSQualityOfServiceUtility];
        }
        
        [self setup];
    }
    return self;
}

- (void)setup
{
    [self createTransitCacheDirectories];
}


#pragma mark Snapshotting Remote Files

- (void)snapshotRemoteFilesWithCompletion:(CDECompletionBlock)completion
{
    [self clearSnapshot];
    
    CDEAsynchronousTaskBlock baselinesTask = ^(CDEAsynchronousTaskCallbackBlock next) {
        [self.cloudFileSystem contentsOfDirectoryAtPath:self.remoteBaselinesDirectory completion:^(NSArray *baselineContents, NSError *error) {
            if (!error) snapshotBaselineFilenames = [NSSet setWithArray:[baselineContents valueForKeyPath:@"name"]];
            next(error, NO);
        }];
    };
    
    CDEAsynchronousTaskBlock eventsTask = ^(CDEAsynchronousTaskCallbackBlock next) {
        [self.cloudFileSystem contentsOfDirectoryAtPath:self.remoteEventsDirectory completion:^(NSArray *eventContents, NSError *error) {
            if (!error) snapshotEventFilenames = [NSSet setWithArray:[eventContents valueForKeyPath:@"name"]];
            next(error, NO);
        }];
    };
    
    CDEAsynchronousTaskBlock dataTask = ^(CDEAsynchronousTaskCallbackBlock next) {
        [self.cloudFileSystem contentsOfDirectoryAtPath:self.remoteDataDirectory completion:^(NSArray *dataContents, NSError *error) {
            if (!error) snapshotDataFilenames = [NSSet setWithArray:[dataContents valueForKeyPath:@"name"]];
            next(error, NO);
        }];
    };
    
    NSArray *tasks = @[baselinesTask, eventsTask, dataTask];
    CDEAsynchronousTaskQueue *taskQueue = [[CDEAsynchronousTaskQueue alloc] initWithTasks:tasks terminationPolicy:CDETaskQueueTerminationPolicyStopOnError completion:^(NSError *error) {
        if (error) [self clearSnapshot];
        if (completion) completion(error);
    }];
    [operationQueue addOperation:taskQueue];
}

- (void)clearSnapshot
{
    snapshotEventFilenames = nil;
    snapshotBaselineFilenames = nil;
    snapshotDataFilenames = nil;
}


#pragma mark Importing Remote Files

- (void)importNewRemoteNonBaselineEventsWithCompletion:(CDECompletionBlock)completion
{
    NSAssert([NSThread isMainThread], @"importNewRemote... called off the main thread");
    
    CDELog(CDELoggingLevelVerbose, @"Transferring new events from cloud to event store");
    
    [self transferNewRemoteEventFilesToTransitCacheWithCompletion:^(NSError *error) {
        if (error) {
            if (completion) completion(error);
            return;
        }
        NSArray *types = @[@(CDEStoreModificationEventTypeMerge), @(CDEStoreModificationEventTypeSave)];
        [self migrateNewEventsWithAllowedTypes:types fromTransitCacheWithCompletion:completion];
    }];
}

- (void)importNewBaselineEventsWithCompletion:(CDECompletionBlock)completion
{
    NSAssert([NSThread isMainThread], @"importNewBaselineEventsWithCompletion... called off the main thread");
    
    CDELog(CDELoggingLevelVerbose, @"Transferring new baselines from cloud to event store");
    
    [self transferNewRemoteBaselineFilesToTransitCacheWithCompletion:^(NSError *error) {
        if (error) {
            if (completion) completion(error);
            return;
        }
        NSArray *types = @[@(CDEStoreModificationEventTypeBaseline)];
        [self migrateNewEventsWithAllowedTypes:types fromTransitCacheWithCompletion:completion];
    }];
}

- (void)importNewDataFilesWithCompletion:(CDECompletionBlock)completion
{
    NSAssert([NSThread isMainThread], @"importNewDataFilesWithCompletion... called off the main thread");
    
    CDELog(CDELoggingLevelVerbose, @"Transferring new data files from cloud to event store");
    
    [self transferNewRemoteDataFilesToTransitCacheWithCompletion:^(NSError *error) {
        if (error) {
            if (completion) completion(error);
            return;
        }
        
        BOOL success = [self migrateNewDataFilesFromTransitCache:&error];
        if (completion) completion(success ? nil : error);
    }];
}


#pragma mark Downloading Remote Files

- (void)transferNewFilesToTransitCacheFromRemoteDirectory:(NSString *)remoteDirectory availableFilenames:(NSArray *)filenames forEventTypes:(NSArray *)eventTypes completion:(CDECompletionBlock)completion
{
        NSArray *filenamesToRetrieve = [self filesRequiringRetrievalFromAvailableRemoteFiles:filenames allowedEventTypes:eventTypes];
        [self transferRemoteFiles:filenamesToRetrieve fromRemoteDirectory:remoteDirectory withCompletion:completion];
}

- (void)transferNewRemoteEventFilesToTransitCacheWithCompletion:(CDECompletionBlock)completion
{
    NSAssert(snapshotEventFilenames, @"No snapshot files");
    NSArray *types = @[@(CDEStoreModificationEventTypeSave), @(CDEStoreModificationEventTypeMerge)];
    [self transferNewFilesToTransitCacheFromRemoteDirectory:self.remoteEventsDirectory availableFilenames:snapshotEventFilenames.allObjects forEventTypes:types completion:completion];
}

- (void)transferNewRemoteBaselineFilesToTransitCacheWithCompletion:(CDECompletionBlock)completion
{
    NSAssert(snapshotBaselineFilenames, @"No snapshot files");
    NSArray *types = @[@(CDEStoreModificationEventTypeBaseline)];
    [self transferNewFilesToTransitCacheFromRemoteDirectory:self.remoteBaselinesDirectory availableFilenames:snapshotBaselineFilenames.allObjects forEventTypes:types completion:completion];
}

- (void)transferRemoteFiles:(NSArray *)filenames fromRemoteDirectory:(NSString *)remoteDirectory withCompletion:(CDECompletionBlock)completion
{
    // Remove any existing files in the cache first
    NSError *error = nil;
    BOOL success = [self removeFilesInDirectory:self.localDownloadDirectory error:&error];
    if (!success) {
        if (completion) completion(error);
        return;
    }
    
    NSMutableArray *taskBlocks = [NSMutableArray array];
    for (NSString *filename in filenames) {
        NSString *remotePath = [remoteDirectory stringByAppendingPathComponent:filename];
        NSString *localPath = [self.localDownloadDirectory stringByAppendingPathComponent:filename];
        CDEAsynchronousTaskBlock block = ^(CDEAsynchronousTaskCallbackBlock next) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.cloudFileSystem downloadFromPath:remotePath toLocalFile:localPath completion:^(NSError *error) {
                    next(error, NO);
                }];
            });
        };
        [taskBlocks addObject:block];
    }
    
    CDEAsynchronousTaskQueue *taskQueue = [[CDEAsynchronousTaskQueue alloc] initWithTasks:taskBlocks terminationPolicy:CDETaskQueueTerminationPolicyStopOnError completion:completion];
    [operationQueue addOperation:taskQueue];
}

- (NSArray *)filesRequiringRetrievalFromAvailableRemoteFiles:(NSArray *)remoteFiles allowedEventTypes:(NSArray *)eventTypes
{
    NSMutableSet *toRetrieve = [NSMutableSet setWithArray:remoteFiles];
    NSSet *eventFiles = [self eventFilesForEventsWithAllowedTypes:eventTypes createdInStore:nil];
    for (CDEEventFile *eventFile in eventFiles) {
        [toRetrieve minusSet:eventFile.aliases];
    }
    return [self sortFilenamesByGlobalCount:toRetrieve.allObjects];
}

- (void)transferNewRemoteDataFilesToTransitCacheWithCompletion:(CDECompletionBlock)completion
{
    NSAssert(snapshotDataFilenames, @"No snapshot files");
    NSMutableSet *toRetrieve = [self.snapshotDataFilenames mutableCopy];
    NSSet *storeFilenames = self.eventStore.allDataFilenames;
    [toRetrieve minusSet:storeFilenames];
    [self transferRemoteFiles:toRetrieve.allObjects fromRemoteDirectory:self.remoteDataDirectory withCompletion:completion];
}


#pragma mark Migrating Data In

- (void)migrateNewEventsWithAllowedTypes:(NSArray *)types fromTransitCacheWithCompletion:(CDECompletionBlock)completion
{
    NSError *error = nil;
    NSArray *files = [fileManager contentsOfDirectoryAtPath:self.localDownloadDirectory error:&error];
    
    NSManagedObjectContext *moc = self.eventStore.managedObjectContext;
    CDEEventMigrator *migrator = [[CDEEventMigrator alloc] initWithEventStore:self.eventStore];
    
    NSMutableArray *tasks = [[NSMutableArray alloc] initWithCapacity:files.count];
    for (NSString *file in files) {
        NSString *path = [self.localDownloadDirectory stringByAppendingPathComponent:file];
        
        CDEAsynchronousTaskBlock block = ^(CDEAsynchronousTaskCallbackBlock next) {
            CDEEventFile *eventFile = [[CDEEventFile alloc] initWithFilename:file];
            if (eventFile == nil) {
                next(nil, NO);
                return;
            }
            
            // Check for a pre-existing event first. Skip if we find one.
            __block BOOL eventsExist = NO;
            [moc performBlockAndWait:^{
                NSError *error;
                NSFetchRequest *fetch = [[NSFetchRequest alloc] initWithEntityName:@"CDEStoreModificationEvent"];
                fetch.predicate = eventFile.eventFetchPredicate;
                NSArray *events = [moc executeFetchRequest:fetch error:&error];
                if (!events) CDELog(CDELoggingLevelError, @"Could not fetch events: %@", error);
                eventsExist = events.count > 0;
            }];
            
            if (eventsExist && eventFile.eventShouldBeUnique) {
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
    
    CDEAsynchronousTaskQueue *taskQueue = [[CDEAsynchronousTaskQueue alloc] initWithTasks:tasks terminationPolicy:CDETaskQueueTerminationPolicyCompleteAll completion:completion];
    [operationQueue addOperation:taskQueue];
}

- (BOOL)migrateNewDataFilesFromTransitCache:(NSError * __autoreleasing *)error
{
    NSArray *files = [fileManager contentsOfDirectoryAtPath:self.localDownloadDirectory error:error];
    if (!files) return NO;
    
    for (NSString *file in files) {
        NSString *path = [self.localDownloadDirectory stringByAppendingPathComponent:file];
        BOOL success = [self.eventStore importDataFile:path];
        if (!success) {
            if (error) *error = [[NSError alloc] initWithDomain:CDEErrorDomain code:CDEErrorCodeFileAccessFailed userInfo:nil];
            return NO;
        }
    }
    
    return YES;
}


#pragma mark Uploading Local Events

- (void)exportNewLocalNonBaselineEventsWithCompletion:(CDECompletionBlock)completion
{
    NSAssert(snapshotEventFilenames, @"No snapshot");
    CDELog(CDELoggingLevelVerbose, @"Transferring events from event store to cloud");

    NSArray *types = @[@(CDEStoreModificationEventTypeMerge), @(CDEStoreModificationEventTypeSave)];
    [self migrateNewLocalEventsToTransitCacheWithRemoteDirectory:self.remoteEventsDirectory existingRemoteFilenames:snapshotEventFilenames.allObjects allowedTypes:types completion:^(NSError *error) {
        if (error) CDELog(CDELoggingLevelWarning, @"Error migrating out events: %@", error);
        [self transferFilesInTransitCacheToRemoteDirectory:self.remoteEventsDirectory completion:completion];
    }];
}

- (void)exportNewLocalBaselineWithCompletion:(CDECompletionBlock)completion
{
    NSAssert(snapshotBaselineFilenames, @"No snapshot");
    CDELog(CDELoggingLevelVerbose, @"Transferring baseline from event store to cloud");
    
    NSArray *types = @[@(CDEStoreModificationEventTypeBaseline)];
    [self migrateNewLocalEventsToTransitCacheWithRemoteDirectory:self.remoteBaselinesDirectory existingRemoteFilenames:snapshotBaselineFilenames.allObjects allowedTypes:types completion:^(NSError *error) {
        if (error) CDELog(CDELoggingLevelWarning, @"Error migrating out baseline: %@", error);
        [self transferFilesInTransitCacheToRemoteDirectory:self.remoteBaselinesDirectory completion:completion];
    }];
}

- (void)exportDataFilesWithCompletion:(CDECompletionBlock)completion
{
    NSAssert(snapshotDataFilenames, @"No snapshot");
    CDELog(CDELoggingLevelVerbose, @"Transferring data files from event store to cloud");

    NSError *error;
    BOOL success = [self migrateNewLocalDataFilesToTransitCache:&error];
    if (!success) {
        if (completion) completion(error);
        return;
    }
    
    [self transferFilesInTransitCacheToRemoteDirectory:self.remoteDataDirectory completion:completion];
}

- (void)migrateNewLocalEventsToTransitCacheWithRemoteDirectory:(NSString *)remoteDirectory existingRemoteFilenames:(NSArray *)filenames allowedTypes:(NSArray *)types completion:(CDECompletionBlock)completion
{
    NSArray *filenamesToUpload = [self localEventFilesMissingFromRemoteCloudFiles:filenames allowedTypes:types];
    [self migrateLocalEventsToTransitCacheForFilenames:filenamesToUpload allowedTypes:types completion:completion];
}

- (void)migrateLocalEventsToTransitCacheForFilenames:(NSArray *)filesToUpload allowedTypes:(NSArray *)types completion:(CDECompletionBlock)completion
{
    // Remove any existing files in the cache first
    NSError *error = nil;
    BOOL success = [self removeFilesInDirectory:self.localUploadDirectory error:&error];
    if (!success) {
        if (completion) completion(error);
        return;
    }
    
    // Migrate events to file
    CDEEventMigrator *migrator = [[CDEEventMigrator alloc] initWithEventStore:self.eventStore];
    NSMutableArray *tasks = [[NSMutableArray alloc] initWithCapacity:filesToUpload.count];
    for (NSString *file in filesToUpload) {
        NSString *path = [self.localUploadDirectory stringByAppendingPathComponent:file];
        
        CDEAsynchronousTaskBlock block = ^(CDEAsynchronousTaskCallbackBlock next) {
            CDEEventFile *eventFile = [[CDEEventFile alloc] initWithFilename:file];
            NSAssert(eventFile, @"Invalid filename");

            // Migrate data to file
            dispatch_async(dispatch_get_main_queue(), ^{
                BOOL isDir;
                if ([fileManager fileExistsAtPath:path isDirectory:&isDir]) {
                    NSError *error;
                    if (![fileManager removeItemAtPath:path error:&error]) {
                        next(error, NO);
                        return;
                    }
                }
                
                if (eventFile.isBaseline) {
                    [migrator migrateLocalBaselineWithUniqueIdentifier:eventFile.uniqueIdentifier globalCount:eventFile.globalCount persistentStorePrefix:eventFile.persistentStorePrefix toFile:path completion:^(NSError *error) {
                        next(error, NO);
                    }];
                }
                else {
                    [migrator migrateLocalEventWithRevision:eventFile.revisionNumber toFile:path allowedTypes:types completion:^(NSError *error) {
                        next(error, NO);
                    }];
                }
            });
        };
        
        [tasks addObject:block];
    }
    
    CDEAsynchronousTaskQueue *taskQueue = [[CDEAsynchronousTaskQueue alloc] initWithTasks:tasks terminationPolicy:CDETaskQueueTerminationPolicyCompleteAll completion:completion];
    [operationQueue addOperation:taskQueue];
}

- (BOOL)migrateNewLocalDataFilesToTransitCache:(NSError * __autoreleasing *)error
{
    // Remove any existing files in the cache first
    BOOL success = [self removeFilesInDirectory:self.localUploadDirectory error:error];
    if (!success) return NO;
    
    NSMutableSet *toTransfer = [self.eventStore.previouslyReferencedDataFilenames mutableCopy];
    [toTransfer minusSet:snapshotDataFilenames];
    
    for (NSString *file in toTransfer) {
        BOOL success = [self.eventStore exportDataFile:file toDirectory:self.localUploadDirectory];
        if (!success) {
            if (error) *error = [[NSError alloc] initWithDomain:CDEErrorDomain code:CDEErrorCodeFileAccessFailed userInfo:nil];
            return NO;
        }
    }
    
    return YES;
}


- (void)transferFilesInTransitCacheToRemoteDirectory:(NSString *)remoteDirectory completion:(CDECompletionBlock)completion
{
    NSError *error = nil;
    NSArray *files = [fileManager contentsOfDirectoryAtPath:self.localUploadDirectory error:&error];
    files = [self sortFilenamesByGlobalCount:files];
    
    NSMutableArray *taskBlocks = [NSMutableArray array];
    for (NSString *filename in files) {
        NSString *remotePath = [remoteDirectory stringByAppendingPathComponent:filename];
        NSString *localPath = [self.localUploadDirectory stringByAppendingPathComponent:filename];
        CDEAsynchronousTaskBlock block = ^(CDEAsynchronousTaskCallbackBlock next) {
            dispatch_async(dispatch_get_main_queue(), ^{
                CDELog(CDELoggingLevelVerbose, @"Uploading file to remote path: %@", remotePath);
                [self.cloudFileSystem uploadLocalFile:localPath toPath:remotePath completion:^(NSError *error) {
                    [fileManager removeItemAtPath:localPath error:NULL];
                    if (error) CDELog(CDELoggingLevelError, @"Failed file upload with error: %@", error);
                    next(error, NO);
                }];
            });
        };
        [taskBlocks addObject:block];
    }
    
    CDEAsynchronousTaskQueue *taskQueue = [[CDEAsynchronousTaskQueue alloc] initWithTasks:taskBlocks terminationPolicy:CDETaskQueueTerminationPolicyStopOnError completion:completion];
    [operationQueue addOperation:taskQueue];
}


#pragma mark Event Files

- (NSArray *)localEventFilesMissingFromRemoteCloudFiles:(NSArray *)remoteFiles allowedTypes:(NSArray *)types
{
    NSString *persistentStoreId = self.eventStore.persistentStoreIdentifier;
    NSSet *eventFiles = [self eventFilesForEventsWithAllowedTypes:types createdInStore:persistentStoreId];
    
    NSSet *remoteSet = [NSSet setWithArray:remoteFiles];
    NSMutableSet *filenames = [[NSMutableSet alloc] init];
    for (CDEEventFile *eventFile in eventFiles) {
        if (![remoteSet intersectsSet:eventFile.aliases]) {
            [filenames addObject:eventFile.preferredFilename];
        }
    }
    
    return [self sortFilenamesByGlobalCount:filenames.allObjects];
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

- (NSSet *)eventFilesForEventsWithAllowedTypes:(NSArray *)types createdInStore:(NSString *)persistentStoreIdentifier
{
    NSManagedObjectContext *moc = self.eventStore.managedObjectContext;
    __block NSMutableSet *eventFiles = [NSMutableSet set];
    [moc performBlockAndWait:^{
        NSArray *events = [CDEStoreModificationEvent fetchStoreModificationEventsWithTypes:types persistentStoreIdentifier:persistentStoreIdentifier inManagedObjectContext:moc];
        if (!events) {
            CDELog(CDELoggingLevelError, @"Could not retrieve local events");
        }

        for (CDEStoreModificationEvent *event in events) {
            CDEEventFile *eventFile = [[CDEEventFile alloc] initWithStoreModificationEvent:event];
            [eventFiles addObject:eventFile];
        }
    }];
    return eventFiles;
}


#pragma mark Local Directories

- (NSString *)localEnsembleDirectory
{
    return [localFileRoot stringByAppendingPathComponent:self.eventStore.ensembleIdentifier];
}

- (NSString *)localUploadDirectory
{
    return [self.localEnsembleDirectory stringByAppendingPathComponent:@"upload"];
}

- (NSString *)localDownloadDirectory
{
    return [self.localEnsembleDirectory stringByAppendingPathComponent:@"download"];
}


#pragma mark Local Directory Structure

- (void)createTransitCacheDirectories
{
    NSArray *dirs = @[localFileRoot, self.localDownloadDirectory, self.localUploadDirectory];
    for (NSString *dir in dirs) {
        [fileManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    }
}

- (BOOL)removeFilesInDirectory:(NSString *)dir error:(NSError * __autoreleasing *)error
{
    NSArray *files = [fileManager contentsOfDirectoryAtPath:dir error:error];
    if (!files) return NO;
    
    for (NSString *file in files) {
        if ([file hasPrefix:@"."]) continue; // Ignore system files
        NSString *path = [dir stringByAppendingPathComponent:file];
        
        NSError *localError = nil;
        BOOL success = [fileManager removeItemAtPath:path error:&localError];
        if (!success) {
            BOOL noSuchFileError = [localError.domain isEqualToString:NSCocoaErrorDomain] && localError.code == NSFileReadNoSuchFileError;
            if (!noSuchFileError) {
                if (error) *error = localError;
                return NO;
            }
        }
    }
    
    return YES;
}


#pragma mark Removing Outdated Files

- (BOOL)removeOutOfDateNewlyImportedFiles:(NSError * __autoreleasing *)error
{
    // Remove files that are found locally but no longer found remotely.
    NSMutableSet *filesToRemove = [self.eventStore.newlyImportedDataFilenames mutableCopy];
    [filesToRemove minusSet:snapshotDataFilenames];
    for (NSString *file in filesToRemove) {
        BOOL success = [self.eventStore removeNewlyImportedDataFile:file];
        if (!success) {
            NSDictionary *info = @{NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Could not remove data file: %@", file]};
            if (error) *error = [[NSError alloc] initWithDomain:CDEErrorDomain code:CDEErrorCodeFileAccessFailed userInfo:info];
            return NO;
        }
    }
    return YES;
}

// Requires a snapshot already exist
- (void)removeOutdatedRemoteFilesWithCompletion:(CDECompletionBlock)completion
{
    NSAssert([NSThread isMainThread], @"removeOutdatedRemoteFilesWithCompletion... called off the main thread");
    
    CDELog(CDELoggingLevelVerbose, @"Removing outdated files");
    
    if (!snapshotBaselineFilenames || !snapshotEventFilenames) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSError *error = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeMissingCloudSnapshot userInfo:nil];
            if (completion) completion(error);
        });
        return;
    }
    
    // Determine corresponding files for data still in event store
    NSArray *nonBaselineTypes = @[@(CDEStoreModificationEventTypeSave), @(CDEStoreModificationEventTypeMerge)];
    NSArray *baselineTypes = @[@(CDEStoreModificationEventTypeBaseline)];
    
    // Determine baselines to remove
    NSMutableSet *baselinesToRemove = [snapshotBaselineFilenames mutableCopy];
    NSSet *baselineEventFilesForStore = [self eventFilesForEventsWithAllowedTypes:baselineTypes createdInStore:nil];
    NSSet *baselineAliasesForStore = [baselineEventFilesForStore valueForKeyPath:@"@distinctUnionOfSets.aliases"];
    [baselinesToRemove minusSet:baselineAliasesForStore];
    CDELog(CDELoggingLevelVerbose, @"Baseline files in cloud: %@", snapshotBaselineFilenames);
    CDELog(CDELoggingLevelVerbose, @"Aliases for baseline files in store: %@", baselineAliasesForStore);
    CDELog(CDELoggingLevelVerbose, @"Baseline files to remove: %@", baselinesToRemove);
    
    // Determine non-baselines to remove
    NSMutableSet *nonBaselinesToRemove = [snapshotEventFilenames mutableCopy];
    NSSet *nonBaselineEventFilesForStore = [self eventFilesForEventsWithAllowedTypes:nonBaselineTypes createdInStore:nil];
    NSSet *nonBaselineAliasesForStore = [nonBaselineEventFilesForStore valueForKeyPath:@"@distinctUnionOfSets.aliases"];
    [nonBaselinesToRemove minusSet:nonBaselineAliasesForStore];
    CDELog(CDELoggingLevelVerbose, @"Event files in cloud: %@", snapshotEventFilenames);
    CDELog(CDELoggingLevelVerbose, @"Aliases for event files in store: %@", nonBaselineAliasesForStore);
    CDELog(CDELoggingLevelVerbose, @"Event files to remove: %@", nonBaselinesToRemove);
    
    // Determine data files to remove
    NSSet *dataFilesForEventStore = self.eventStore.allDataFilenames;
    NSMutableSet *dataFilesToRemove = [snapshotDataFilenames mutableCopy];
    [dataFilesToRemove minusSet:dataFilesForEventStore];
    CDELog(CDELoggingLevelVerbose, @"Data files in cloud: %@", snapshotDataFilenames);
    CDELog(CDELoggingLevelVerbose, @"Data files in store: %@", dataFilesForEventStore);
    CDELog(CDELoggingLevelVerbose, @"Data files to remove: %@", dataFilesToRemove);
    
    // Queue up removals
    NSMutableArray *pathsToRemove = [NSMutableArray array];
    [baselinesToRemove enumerateObjectsUsingBlock:^(NSString *file, BOOL *stop) {
        [pathsToRemove addObject:[self.remoteBaselinesDirectory stringByAppendingPathComponent:file]];
    }];
    [nonBaselinesToRemove enumerateObjectsUsingBlock:^(NSString *file, BOOL *stop) {
        [pathsToRemove addObject:[self.remoteEventsDirectory stringByAppendingPathComponent:file]];
    }];
    [dataFilesToRemove enumerateObjectsUsingBlock:^(NSString *file, BOOL *stop) {
        [pathsToRemove addObject:[self.remoteDataDirectory stringByAppendingPathComponent:file]];
    }];
    CDELog(CDELoggingLevelVerbose, @"Removing cloud files: %@", [pathsToRemove componentsJoinedByString:@"\n"]);
    
    // Queue up tasks
    NSMutableArray *tasks = [[NSMutableArray alloc] initWithCapacity:pathsToRemove.count];
    for (NSString *path in pathsToRemove) {
        CDEAsynchronousTaskBlock block = ^(CDEAsynchronousTaskCallbackBlock next) {
            [self.cloudFileSystem removeItemAtPath:path completion:^(NSError *error) {
                next(error, NO);
            }];
        };
        [tasks addObject:block];
    }
    
    CDEAsynchronousTaskQueue *taskQueue = [[CDEAsynchronousTaskQueue alloc] initWithTasks:tasks terminationPolicy:CDETaskQueueTerminationPolicyCompleteAll completion:completion];
    [operationQueue addOperation:taskQueue];
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

- (NSString *)remoteBaselinesDirectory
{
    return [self.remoteEnsembleDirectory stringByAppendingPathComponent:@"baselines"];
}

- (NSString *)remoteDataDirectory
{
    return [self.remoteEnsembleDirectory stringByAppendingPathComponent:@"data"];
}

- (void)createRemoteDirectoryStructureWithCompletion:(CDECompletionBlock)completion
{
    NSArray *dirs = @[self.remoteEnsembleDirectory, self.remoteStoresDirectory, self.remoteEventsDirectory, self.remoteBaselinesDirectory, self.remoteDataDirectory];
    [self createRemoteDirectories:dirs withCompletion:completion];
}

- (void)createRemoteDirectories:(NSArray *)paths withCompletion:(CDECompletionBlock)completion
{
    CDELog(CDELoggingLevelVerbose, @"Creating remote directories");

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
    
    CDEAsynchronousTaskQueue *taskQueue = [[CDEAsynchronousTaskQueue alloc] initWithTasks:taskBlocks terminationPolicy:CDETaskQueueTerminationPolicyStopOnError completion:completion];
    [operationQueue addOperation:taskQueue];
}


#pragma mark Store Registration Info

- (void)retrieveRegistrationInfoForStoreWithIdentifier:(NSString *)identifier completion:(void(^)(NSDictionary *info, NSError *error))completion
{
    CDELog(CDELoggingLevelVerbose, @"Retrieving registration info");
    
    // Remove any existing files in the cache first
    NSError *error = nil;
    BOOL success = [self removeFilesInDirectory:self.localDownloadDirectory error:&error];
    if (!success) {
        if (completion) completion(nil, error);
        return;
    }
    
    NSString *remotePath = [self.remoteStoresDirectory stringByAppendingPathComponent:identifier];
    NSString *localPath = [self.localDownloadDirectory stringByAppendingPathComponent:identifier];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.cloudFileSystem fileExistsAtPath:remotePath completion:^(BOOL exists, BOOL isDirectory, NSError *error) {
            if (error || !exists) {
                if (completion) completion(nil, error);
                return;
            }
            
            CDELog(CDELoggingLevelVerbose, @"Downloading file at remote path: %@", remotePath);
            [self.cloudFileSystem downloadFromPath:remotePath toLocalFile:localPath completion:^(NSError *error) {
                NSDictionary *info = nil;
                if (!error) {
                    info = [NSDictionary dictionaryWithContentsOfFile:localPath];
                    [fileManager removeItemAtPath:localPath error:NULL];
                }
                if (error) CDELog(CDELoggingLevelError, @"Download failed for with error: %@", error);
                if (completion) completion(info, error);
            }];
        }];
    });
}

- (void)setRegistrationInfo:(NSDictionary *)info forStoreWithIdentifier:(NSString *)identifier completion:(CDECompletionBlock)completion
{
    // Remove any existing files in the cache first
    NSError *error = nil;
    BOOL success = [self removeFilesInDirectory:self.localUploadDirectory error:&error];
    if (!success) {
        if (completion) completion(error);
        return;
    }
    
    NSString *localPath = [self.localUploadDirectory stringByAppendingPathComponent:identifier];
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
