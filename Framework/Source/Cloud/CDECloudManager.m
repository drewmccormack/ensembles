//
//  CDECloudManager.m
//  Test App iOS
//
//  Created by Drew McCormack on 5/29/13.
//  Copyright (c) 2013 The Mental Faculty B.V. All rights reserved.
//

#import "CDECloudManager.h"
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

@property (nonatomic, strong, readonly) NSString *localDownloadRoot;
@property (nonatomic, strong, readonly) NSString *localStoresDownloadDirectory;
@property (nonatomic, strong, readonly) NSString *localEventsDownloadDirectory;
@property (nonatomic, strong, readonly) NSString *localDataDownloadDirectory;

@property (nonatomic, strong, readonly) NSString *localUploadRoot;
@property (nonatomic, strong, readonly) NSString *localStoresUploadDirectory;
@property (nonatomic, strong, readonly) NSString *localEventsUploadDirectory;
@property (nonatomic, strong, readonly) NSString *localDataUploadDirectory;

@property (nonatomic, strong, readonly) NSString *remoteEnsembleDirectory;
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
        [self createTransitCacheDirectories];
    }
    return self;
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


#pragma mark Downloading Remote Files

- (void)transferNewFilesToTransitCacheFromRemoteDirectory:(NSString *)remoteDirectory availableFilenames:(NSArray *)filenames forEventTypes:(NSArray *)eventTypes completion:(CDECompletionBlock)completion
{
        NSArray *filenamesToRetrieve = [self eventFilesRequiringRetrievalFromAvailableRemoteFiles:filenames allowedEventTypes:eventTypes];
        [self transferRemoteEventFiles:filenamesToRetrieve fromRemoteDirectory:remoteDirectory toTransitCacheWithCompletion:completion];
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

- (void)transferRemoteEventFiles:(NSArray *)filenames fromRemoteDirectory:(NSString *)remoteDirectory toTransitCacheWithCompletion:(CDECompletionBlock)completion
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
        NSString *remotePath = [remoteDirectory stringByAppendingPathComponent:filename];
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
    
    CDEAsynchronousTaskQueue *taskQueue = [[CDEAsynchronousTaskQueue alloc] initWithTasks:taskBlocks terminationPolicy:CDETaskQueueTerminationPolicyStopOnError completion:completion];
    [operationQueue addOperation:taskQueue];
}

- (NSArray *)eventFilesRequiringRetrievalFromAvailableRemoteFiles:(NSArray *)remoteFiles allowedEventTypes:(NSArray *)eventTypes
{
    NSMutableSet *toRetrieve = [NSMutableSet setWithArray:remoteFiles];
    NSSet *storeFilenames = [self filenamesForEventsWithAllowedTypes:eventTypes createdInStore:nil];
    [toRetrieve minusSet:storeFilenames];
    return [self sortFilenamesByGlobalCount:toRetrieve.allObjects];
}


#pragma mark Migrating Data In

- (void)migrateNewEventsWithAllowedTypes:(NSArray *)types fromTransitCacheWithCompletion:(CDECompletionBlock)completion
{
    NSError *error = nil;
    NSArray *files = [fileManager contentsOfDirectoryAtPath:self.localEventsDownloadDirectory error:&error];
    
    NSManagedObjectContext *moc = self.eventStore.managedObjectContext;
    CDEEventMigrator *migrator = [[CDEEventMigrator alloc] initWithEventStore:self.eventStore];
    
    NSMutableArray *tasks = [[NSMutableArray alloc] initWithCapacity:files.count];
    for (NSString *file in files) {
        NSString *path = [self.localEventsDownloadDirectory stringByAppendingPathComponent:file];
        
        CDEAsynchronousTaskBlock block = ^(CDEAsynchronousTaskCallbackBlock next) {
            BOOL isBaseline = NO;
            BOOL valid = [self filename:file isValidForAllowedEventTypes:types isBaseline:&isBaseline];
            
            if (!valid) {
                next(nil, NO);
                return;
            }
            
            // Check for a pre-existing event first. Skip if we find one.
            __block BOOL eventExists = NO;
            CDEGlobalCount globalCount;
            if (isBaseline) {
                NSString *uniqueId;
                [self count:&globalCount andUniqueIdentifier:&uniqueId fromBaselineFilename:file];
                [moc performBlockAndWait:^{
                    CDEStoreModificationEvent *existingEvent = [CDEStoreModificationEvent fetchStoreModificationEventWithUniqueIdentifier:uniqueId globalCount:globalCount inManagedObjectContext:moc];
                    eventExists = existingEvent != nil;
                }];
            }
            else {
                CDERevision *revision;
                [self count:&globalCount andRevision:&revision fromEventFilename:file];
                [moc performBlockAndWait:^{
                    CDEStoreModificationEvent *existingEvent = [CDEStoreModificationEvent fetchStoreModificationEventWithAllowedTypes:types persistentStoreIdentifier:revision.persistentStoreIdentifier revisionNumber:revision.revisionNumber inManagedObjectContext:moc]; 
                    eventExists = existingEvent != nil;
                }];
            }
            
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
    
    CDEAsynchronousTaskQueue *taskQueue = [[CDEAsynchronousTaskQueue alloc] initWithTasks:tasks terminationPolicy:CDETaskQueueTerminationPolicyCompleteAll completion:completion];
    [operationQueue addOperation:taskQueue];
}


#pragma mark Uploading Local Events

- (void)exportNewLocalNonBaselineEventsWithCompletion:(CDECompletionBlock)completion
{
    NSAssert(snapshotEventFilenames, @"No snapshot");
    
    CDELog(CDELoggingLevelVerbose, @"Transferring events from event store to cloud");

    NSArray *types = @[@(CDEStoreModificationEventTypeMerge), @(CDEStoreModificationEventTypeSave)];
    [self migrateNewLocalEventsToTransitCacheWithRemoteDirectory:self.remoteEventsDirectory existingRemoteFilenames:snapshotEventFilenames.allObjects allowedTypes:types completion:^(NSError *error) {
        if (error) CDELog(CDELoggingLevelWarning, @"Error migrating out events: %@", error);
        [self transferEventFilesInTransitCacheToRemoteDirectory:self.remoteEventsDirectory completion:completion];
    }];
}

- (void)exportNewLocalBaselineWithCompletion:(CDECompletionBlock)completion
{
    NSAssert(snapshotBaselineFilenames, @"No snapshot");

    CDELog(CDELoggingLevelVerbose, @"Transferring baseline from event store to cloud");
    
    NSArray *types = @[@(CDEStoreModificationEventTypeBaseline)];
    [self migrateNewLocalEventsToTransitCacheWithRemoteDirectory:self.remoteBaselinesDirectory existingRemoteFilenames:snapshotBaselineFilenames.allObjects allowedTypes:types completion:^(NSError *error) {
        if (error) CDELog(CDELoggingLevelWarning, @"Error migrating out baseline: %@", error);
        [self transferEventFilesInTransitCacheToRemoteDirectory:self.remoteBaselinesDirectory completion:completion];
    }];
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
            BOOL isBaseline = NO;
            __unused BOOL valid = [self filename:file isValidForAllowedEventTypes:types isBaseline:&isBaseline];
            NSAssert(valid, @"Invalid filename");
            
            CDEGlobalCount globalCount = -1;
            CDERevision *revision = nil;
            NSString *uniqueId = nil;
            if (isBaseline) {
                __unused BOOL isBaselineFile = [self count:&globalCount andUniqueIdentifier:&uniqueId fromBaselineFilename:file];
                NSAssert(isBaselineFile, @"Should be baseline");
            }
            else {
                __unused BOOL isEventFile = [self count:&globalCount andRevision:&revision fromEventFilename:file];
                NSAssert(isEventFile, @"Should be event file");
            }
            
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
                
                if (isBaseline) {
                    [migrator migrateLocalBaselineWithUniqueIdentifier:uniqueId globalCount:globalCount toFile:path completion:^(NSError *error) {
                        next(error, NO);
                    }];
                }
                else {
                    [migrator migrateLocalEventWithRevision:revision.revisionNumber toFile:path allowedTypes:types completion:^(NSError *error) {
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

- (void)transferEventFilesInTransitCacheToRemoteDirectory:(NSString *)remoteDirectory completion:(CDECompletionBlock)completion
{
    NSError *error = nil;
    NSArray *files = [fileManager contentsOfDirectoryAtPath:self.localEventsUploadDirectory error:&error];
    files = [self sortFilenamesByGlobalCount:files];
    
    NSMutableArray *taskBlocks = [NSMutableArray array];
    for (NSString *filename in files) {
        NSString *remotePath = [remoteDirectory stringByAppendingPathComponent:filename];
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
    
    CDEAsynchronousTaskQueue *taskQueue = [[CDEAsynchronousTaskQueue alloc] initWithTasks:taskBlocks terminationPolicy:CDETaskQueueTerminationPolicyStopOnError completion:completion];
    [operationQueue addOperation:taskQueue];
}

- (NSArray *)localEventFilesMissingFromRemoteCloudFiles:(NSArray *)remoteFiles allowedTypes:(NSArray *)types
{
    NSString *persistentStoreId = self.eventStore.persistentStoreIdentifier;
    NSMutableSet *filenames = [[self filenamesForEventsWithAllowedTypes:types createdInStore:persistentStoreId] mutableCopy];
    
    // Remove remote files to get the missing ones
    NSSet *remoteSet = [NSSet setWithArray:remoteFiles];
    [filenames minusSet:remoteSet];
    
    return [self sortFilenamesByGlobalCount:filenames.allObjects];
}


#pragma mark File Naming

- (NSString *)filenameForEvent:(CDEStoreModificationEvent *)event
{
    NSString *result = nil;
    if (event.type == CDEStoreModificationEventTypeBaseline)
        result = [NSString stringWithFormat:@"%lli_%@.cdeevent", event.globalCount, event.uniqueIdentifier];
    else {
        CDERevision *revision = event.eventRevision.revision;
        result = [NSString stringWithFormat:@"%lli_%@_%lli.cdeevent", event.globalCount, revision.persistentStoreIdentifier, revision.revisionNumber];
    }
    return result;
}

- (BOOL)count:(CDEGlobalCount *)count andRevision:(CDERevision * __autoreleasing *)revision fromEventFilename:(NSString *)filename
{
    NSArray *components = [[filename stringByDeletingPathExtension] componentsSeparatedByString:@"_"];
    if (components.count != 3) {
        *count = -1;
        *revision = nil;
        return NO;
    }
    
    *count = [components[0] longLongValue];
    
    CDERevisionNumber revNumber = [components[2] longLongValue];
    *revision = [[CDERevision alloc] initWithPersistentStoreIdentifier:components[1] revisionNumber:revNumber];
    
    return YES;
}

- (BOOL)count:(CDEGlobalCount *)count andUniqueIdentifier:(NSString * __autoreleasing *)uniqueId fromBaselineFilename:(NSString *)filename
{
    NSArray *components = [[filename stringByDeletingPathExtension] componentsSeparatedByString:@"_"];
    if (components.count != 2) {
        *count = -1;
        *uniqueId = nil;
        return NO;
    }
    
    *count = [components[0] longLongValue];
    *uniqueId = components[1];
    
    return YES;
}

- (BOOL)filename:(NSString *)file isValidForAllowedEventTypes:(NSArray *)types isBaseline:(BOOL *)isBaselineFile
{
    CDEGlobalCount globalCount = -1;
    CDERevision *revision = nil;
    NSString *uniqueId = nil;
    BOOL isEventFile = [self count:&globalCount andRevision:&revision fromEventFilename:file];
    *isBaselineFile = NO;
    if (isEventFile &&
        ([types containsObject:@(CDEStoreModificationEventTypeSave)] ||
         [types containsObject:@(CDEStoreModificationEventTypeMerge)]) ) return YES;
    
    *isBaselineFile = [self count:&globalCount andUniqueIdentifier:&uniqueId fromBaselineFilename:file];
    if (*isBaselineFile && [types containsObject:@(CDEStoreModificationEventTypeBaseline)]) return YES;
    
    return NO;
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

// Use type of nil for all types
// Use nil for store if any store is allowed
- (NSSet *)filenamesForEventsWithAllowedTypes:(NSArray *)types createdInStore:(NSString *)persistentStoreIdentifier
{
    NSMutableSet *filenames = [[NSMutableSet alloc] init];
    NSManagedObjectContext *moc = self.eventStore.managedObjectContext;
    [moc performBlockAndWait:^{
        NSArray *events = [CDEStoreModificationEvent fetchStoreModificationEventsWithTypes:types persistentStoreIdentifier:persistentStoreIdentifier inManagedObjectContext:moc];
        if (!events) {
            CDELog(CDELoggingLevelError, @"Could not retrieve local events");
        }
        
        for (CDEStoreModificationEvent *event in events) {
            NSString *filename = [self filenameForEvent:event];
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

- (NSString *)localDataDownloadDirectory
{
    return [self.localDownloadRoot stringByAppendingPathComponent:@"data"];
}

- (NSString *)localDataUploadDirectory
{
    return [self.localUploadRoot stringByAppendingPathComponent:@"data"];
}


#pragma mark Local Directory Structure

- (void)createTransitCacheDirectories
{
    NSArray *dirs = @[localFileRoot, self.localEventsDownloadDirectory, self.localEventsUploadDirectory,
        self.localStoresDownloadDirectory, self.localStoresUploadDirectory, self.localDataDownloadDirectory,
        self.localDataUploadDirectory];
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
        BOOL success = [fileManager removeItemAtPath:path error:error];
        if (!success) return NO;
    }
    
    return YES;
}


#pragma mark Removing Outdated Files

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
    NSSet *nonBaselineFilesForEventStore = [self filenamesForEventsWithAllowedTypes:nonBaselineTypes createdInStore:nil];
    NSSet *baselineFilesForEventStore = [self filenamesForEventsWithAllowedTypes:@[@(CDEStoreModificationEventTypeBaseline)] createdInStore:nil];
    
    // Determine baselines to remove
    NSMutableSet *baselinesToRemove = [snapshotBaselineFilenames mutableCopy];
    [baselinesToRemove minusSet:baselineFilesForEventStore];
    
    // Determine non-baselines to remove
    NSMutableSet *nonBaselinesToRemove = [snapshotEventFilenames mutableCopy];
    [nonBaselinesToRemove minusSet:nonBaselineFilesForEventStore];
    
    // Queue up removals
    NSArray *baselinePaths = [baselinesToRemove.allObjects cde_arrayByTransformingObjectsWithBlock:^id(NSString *file) {
        NSString *path = [self.remoteBaselinesDirectory stringByAppendingPathComponent:file];
        return path;
    }];
    NSArray *nonBaselinePaths = [nonBaselinesToRemove.allObjects cde_arrayByTransformingObjectsWithBlock:^id(NSString *file) {
        NSString *path = [self.remoteEventsDirectory stringByAppendingPathComponent:file];
        return path;
    }];
    NSArray *pathsToRemove = [baselinePaths arrayByAddingObjectsFromArray:nonBaselinePaths];
    
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
