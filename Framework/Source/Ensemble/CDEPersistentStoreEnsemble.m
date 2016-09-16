//
//  CDEPersistentStoreEnsemble.m
//  Ensembles
//
//  Created by Drew McCormack on 4/11/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import "CDEPersistentStoreEnsemble.h"
#import "CDECloudManager.h"
#import "CDEPersistentStoreImporter.h"
#import "CDEEventStore.h"
#import "CDEDefines.h"
#import "CDEAsynchronousTaskQueue.h"
#import "CDECloudFile.h"
#import "CDECloudDirectory.h"
#import "CDECloudFileSystem.h"
#import "CDESaveMonitor.h"
#import "CDEEventIntegrator.h"
#import "CDEEventBuilder.h"
#import "CDEBaselineConsolidator.h"
#import "CDERebaser.h"
#import "CDERevisionManager.h"


static NSString * const kCDEIdentityTokenContext = @"kCDEIdentityTokenContext";

static NSString * const kCDEStoreIdentifierKey = @"storeIdentifier";
static NSString * const kCDELeechDate = @"leechDate";

static NSString * const kCDEMergeTaskInfo = @"Merge";

NSString * const CDEMonitoredManagedObjectContextWillSaveNotification = @"CDEMonitoredManagedObjectContextWillSaveNotification";
NSString * const CDEMonitoredManagedObjectContextDidSaveNotification = @"CDEMonitoredManagedObjectContextDidSaveNotification";
NSString * const CDEPersistentStoreEnsembleDidSaveMergeChangesNotification = @"CDEPersistentStoreEnsembleDidSaveMergeChangesNotification";

NSString * const CDEManagedObjectContextSaveNotificationKey = @"managedObjectContextSaveNotification";


@interface CDEPersistentStoreEnsemble ()

@property (nonatomic, strong, readwrite) CDECloudManager *cloudManager;
@property (nonatomic, strong, readwrite) id <CDECloudFileSystem> cloudFileSystem;
@property (nonatomic, strong, readwrite) NSString *ensembleIdentifier;
@property (nonatomic, strong, readwrite) NSURL *storeURL;
@property (nonatomic, strong, readwrite) NSManagedObjectModel *managedObjectModel;
@property (nonatomic, strong, readwrite) NSURL *managedObjectModelURL;
@property (atomic, assign, readwrite, getter = isLeeched) BOOL leeched;
@property (atomic, assign, readwrite, getter = isMerging) BOOL merging;
@property (nonatomic, strong, readwrite) CDEEventStore *eventStore;
@property (nonatomic, strong, readwrite) CDESaveMonitor *saveMonitor;
@property (nonatomic, strong, readwrite) CDEEventIntegrator *eventIntegrator;
@property (nonatomic, strong, readwrite) CDEBaselineConsolidator *baselineConsolidator;
@property (nonatomic, strong, readwrite) CDERebaser *rebaser;

@end


@implementation CDEPersistentStoreEnsemble {
    BOOL saveOccurredDuringImport;
    NSOperationQueue *operationQueue;
    BOOL observingIdentityToken;
}

@synthesize cloudFileSystem = cloudFileSystem;
@synthesize ensembleIdentifier = ensembleIdentifier;
@synthesize storeURL = storeURL;
@synthesize persistentStoreOptions = persistentStoreOptions;
@synthesize cloudManager = cloudManager;
@synthesize eventStore = eventStore;
@synthesize saveMonitor = saveMonitor;
@synthesize eventIntegrator = eventIntegrator;
@synthesize managedObjectModel = managedObjectModel;
@synthesize managedObjectModelURL = managedObjectModelURL;
@synthesize baselineConsolidator = baselineConsolidator;
@synthesize rebaser = rebaser;

#pragma mark - Initialization and Deallocation

- (instancetype)initWithEnsembleIdentifier:(NSString *)identifier persistentStoreURL:(NSURL *)newStoreURL persistentStoreOptions:(NSDictionary *)storeOptions managedObjectModelURL:(NSURL *)modelURL cloudFileSystem:(id <CDECloudFileSystem>)newCloudFileSystem localDataRootDirectoryURL:(NSURL *)eventDataRootURL
{
    NSParameterAssert(identifier != nil);
    NSParameterAssert(newStoreURL != nil);
    NSParameterAssert(modelURL != nil);
    NSParameterAssert(newCloudFileSystem != nil);
    self = [super init];
    if (self) {
        persistentStoreOptions = storeOptions;
        
        operationQueue = [[NSOperationQueue alloc] init];
        operationQueue.maxConcurrentOperationCount = 1;
        if ([operationQueue respondsToSelector:@selector(setQualityOfService:)]) {
            [operationQueue setQualityOfService:NSQualityOfServiceUtility];
        }
        
        observingIdentityToken = NO;
        
        self.ensembleIdentifier = identifier;
        self.storeURL = newStoreURL;
        self.managedObjectModelURL = modelURL;
        self.managedObjectModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
        self.cloudFileSystem = newCloudFileSystem;
    
        BOOL success = [self setupEventStoreWithDataRootDirectoryURL:eventDataRootURL];
        if (!success) return nil;
        
        self.leeched = eventStore.containsEventData;
        if (self.leeched) [self.eventStore removeUnusedDataWithCompletion:NULL];
        
        [self initializeEventIntegrator];
        
        self.saveMonitor = [[CDESaveMonitor alloc] initWithStorePath:newStoreURL.path];
        self.saveMonitor.ensemble = self;
        self.saveMonitor.eventStore = eventStore;
        self.saveMonitor.eventIntegrator = self.eventIntegrator;
        
        self.cloudManager = [[CDECloudManager alloc] initWithEventStore:self.eventStore cloudFileSystem:self.cloudFileSystem];
        
        self.baselineConsolidator = [[CDEBaselineConsolidator alloc] initWithEventStore:self.eventStore];
        self.rebaser = [[CDERebaser alloc] initWithEventStore:self.eventStore];
        
        [self performInitialChecks];
    }
    return self;
}

- (instancetype)initWithEnsembleIdentifier:(NSString *)identifier persistentStoreURL:(NSURL *)url managedObjectModelURL:(NSURL *)modelURL cloudFileSystem:(id <CDECloudFileSystem>)newCloudFileSystem
{
    return [self initWithEnsembleIdentifier:identifier persistentStoreURL:url persistentStoreOptions:nil managedObjectModelURL:modelURL cloudFileSystem:newCloudFileSystem localDataRootDirectoryURL:nil];
}

- (void)initializeEventIntegrator
{
    NSURL *url = self.storeURL;
    self.eventIntegrator = [[CDEEventIntegrator alloc] initWithStoreURL:url managedObjectModel:self.managedObjectModel eventStore:self.eventStore];
    self.eventIntegrator.ensemble = self;
    self.eventIntegrator.persistentStoreOptions = persistentStoreOptions;
    
    __weak typeof(self) weakSelf = self;
    self.eventIntegrator.shouldSaveBlock = ^(NSManagedObjectContext *savingContext, NSManagedObjectContext *reparationContext) {
        BOOL result = YES;
        __strong typeof(self) strongSelf = weakSelf;
        if ([strongSelf.delegate respondsToSelector:@selector(persistentStoreEnsemble:shouldSaveMergedChangesInManagedObjectContext:reparationManagedObjectContext:)]) {
            result = [strongSelf.delegate persistentStoreEnsemble:strongSelf shouldSaveMergedChangesInManagedObjectContext:savingContext reparationManagedObjectContext:reparationContext];
        }
        return result;
    };
    
    self.eventIntegrator.failedSaveBlock = ^(NSManagedObjectContext *savingContext, NSError *error, NSManagedObjectContext *reparationContext) {
        __strong typeof(self) strongSelf = weakSelf;
        if ([strongSelf.delegate respondsToSelector:@selector(persistentStoreEnsemble:didFailToSaveMergedChangesInManagedObjectContext:error:reparationManagedObjectContext:)]) {
            return [strongSelf.delegate persistentStoreEnsemble:strongSelf didFailToSaveMergedChangesInManagedObjectContext:savingContext error:error reparationManagedObjectContext:reparationContext];
        }
        return NO;
    };
    
    self.eventIntegrator.didSaveBlock = ^(NSManagedObjectContext *context, NSDictionary *info) {
        __strong typeof(self) strongSelf = weakSelf;
        NSNotification *notification = [NSNotification notificationWithName:NSManagedObjectContextDidSaveNotification object:context userInfo:info];
        if ([strongSelf.delegate respondsToSelector:@selector(persistentStoreEnsemble:didSaveMergeChangesWithNotification:)]) {
            [strongSelf.delegate persistentStoreEnsemble:strongSelf didSaveMergeChangesWithNotification:notification];
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:CDEPersistentStoreEnsembleDidSaveMergeChangesNotification object:strongSelf userInfo:@{CDEManagedObjectContextSaveNotificationKey : notification}];
    };
}

- (BOOL)setupEventStoreWithDataRootDirectoryURL:(NSURL *)eventDataRootURL
{
    self.eventStore = [[CDEEventStore alloc] initWithEnsembleIdentifier:self.ensembleIdentifier pathToEventDataRootDirectory:eventDataRootURL.path];
    if (!self.eventStore) {
        // Attempt to recover by removing local data
        CDELog(CDELoggingLevelError, @"Failed to create event store. Serious error, so removing local data.");
        NSString *ensembleRoot = [CDEEventStore pathToEventDataRootDirectoryForRootDirectory:eventDataRootURL.path ensembleIdentifier:self.ensembleIdentifier];
        NSError *error = nil;
        if (![[NSFileManager defaultManager] removeItemAtPath:ensembleRoot error:&error]) {
            CDELog(CDELoggingLevelError, @"Attempt to remove corrupt ensemble data failed. Giving up: %@", error);
            return NO;
        }
        else {
            self.eventStore = [[CDEEventStore alloc] initWithEnsembleIdentifier:self.ensembleIdentifier pathToEventDataRootDirectory:eventDataRootURL.path];
            if (!self.eventStore) {
                CDELog(CDELoggingLevelError, @"Attempt to remove create event store failed again. Giving up.");
                return NO;
            }
        }
    }
    return YES;
}

- (void)dealloc
{
    [self dismantle];
}

- (void)dismantle
{
    if (observingIdentityToken) [(id)self.cloudFileSystem removeObserver:self forKeyPath:@"identityToken"];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [saveMonitor stopMonitoring];
    [eventStore dismantle];
}

#pragma mark - Discovering and Managing Ensembles

+ (void)retrieveEnsembleIdentifiersFromCloudFileSystem:(id <CDECloudFileSystem>)cloudFileSystem completion:(void(^)(NSError *error, NSArray *identifiers))completion
{
    [cloudFileSystem contentsOfDirectoryAtPath:@"/" completion:^(NSArray *contents, NSError *error) {
        NSArray *names = [contents valueForKeyPath:@"name"];
        if (completion) completion(error, names);
    }];
}

+ (void)removeEnsembleWithIdentifier:(NSString *)identifier inCloudFileSystem:(id <CDECloudFileSystem>)cloudFileSystem completion:(void(^)(NSError *error))completion
{
    NSString *path = [NSString stringWithFormat:@"/%@", identifier];
    [cloudFileSystem removeItemAtPath:path completion:completion];
}

#pragma mark - Initial Checks

- (void)performInitialChecks
{
    if (![self checkIncompleteEvents]) return;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self checkCloudFileSystemIdentityWithCompletion:^(NSError *error) {
            if (!error) {
                observingIdentityToken = YES;
                [(id)self.cloudFileSystem addObserver:self forKeyPath:@"identityToken" options:0 context:(__bridge void *)kCDEIdentityTokenContext];
            }
        }];
    });
}

- (BOOL)checkIncompleteEvents
{
    BOOL succeeded = YES;
    if (eventStore.incompleteMandatoryEventIdentifiers.count > 0) {
        // Delay until after init... returns, because we want to inform the delegate
        dispatch_async(dispatch_get_main_queue(), ^{
            [self deleechPersistentStoreWithCompletion:^(NSError *error) {
                if (!error) {
                    if ([self.delegate respondsToSelector:@selector(persistentStoreEnsemble:didDeleechWithError:)]) {
                        NSError *deleechError = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeDataCorruptionDetected userInfo:nil];
                        [self.delegate persistentStoreEnsemble:self didDeleechWithError:deleechError];
                    }
                }
                else {
                    CDELog(CDELoggingLevelError, @"Could not deleech after failing incomplete event check: %@", error);
                }
            }];
        });
        
        succeeded = NO;
    }
    else {
        NSManagedObjectContext *context = eventStore.managedObjectContext;
        for (NSString *eventId in eventStore.incompleteEventIdentifiers) {
            [context performBlock:^{
                CDEStoreModificationEvent *event = [CDEStoreModificationEvent fetchStoreModificationEventWithUniqueIdentifier:eventId inManagedObjectContext:context];
                if (!event) return;
                
                [context deleteObject:event];
                
                NSError *error;
                if ([context save:&error]) {
                    [eventStore deregisterIncompleteEventIdentifier:eventId];
                }
                else {
                    CDELog(CDELoggingLevelError, @"Could not save after deleting incomplete event: %@", error);
                }
            }];
        }
        
        [context performBlock:^{
            NSArray *incompleteEvents = [CDEStoreModificationEvent fetchStoreModificationEventsWithTypes:@[@(CDEStoreModificationEventTypeIncomplete)] persistentStoreIdentifier:nil inManagedObjectContext:context];
            for (CDEStoreModificationEvent *event in incompleteEvents) [context deleteObject:event];
            NSError *error;
            if (![context save:&error]) {
                CDELog(CDELoggingLevelError, @"Failed to delete incomplete events: %@", error);
            }
        }];
    }
    
    return succeeded;
}

#pragma mark - Completing Operations

- (void)dispatchCompletion:(CDECompletionBlock)completion withError:(NSError *)error
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (completion) completion(error);
    });
}

#pragma mark - Key Value Observing

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context == (__bridge void *)kCDEIdentityTokenContext) {
        [self checkCloudFileSystemIdentityWithCompletion:NULL];
    }
}

#pragma mark - Leeching and Deleeching Stores

- (void)leechPersistentStoreWithCompletion:(CDECompletionBlock)completion;
{
    NSAssert(self.cloudFileSystem, @"No cloud file system set");
    NSAssert([NSThread isMainThread], @"leech method called off main thread");
    
    NSMutableArray *tasks = [NSMutableArray array];

    CDEAsynchronousTaskBlock setupTask = ^(CDEAsynchronousTaskCallbackBlock next) {
        if (self.isLeeched) {
            NSError *error = [[NSError alloc] initWithDomain:CDEErrorDomain code:CDEErrorCodeDisallowedStateChange userInfo:nil];
            next(error, NO);
            return;
        }
        next(nil, NO);
    };
    [tasks addObject:setupTask];

    CDEAsynchronousTaskBlock connectTask = ^(CDEAsynchronousTaskCallbackBlock next) {
        [self.cloudFileSystem connect:^(NSError *error) {
            next(error, NO);
        }];
    };
    [tasks addObject:connectTask];
    
    if ([self.cloudFileSystem respondsToSelector:@selector(performInitialPreparation:)]) {
        CDEAsynchronousTaskBlock initialPrepTask = ^(CDEAsynchronousTaskCallbackBlock next) {
            [self.cloudFileSystem performInitialPreparation:^(NSError *error) {
                next(error, NO);
            }];
        };
        [tasks addObject:initialPrepTask];
    }

    CDEAsynchronousTaskBlock remoteStructureTask = ^(CDEAsynchronousTaskCallbackBlock next) {
        [self.cloudManager setup];
        [self.cloudManager createRemoteDirectoryStructureWithCompletion:^(NSError *error) {
            next(error, NO);
        }];
    };
    [tasks addObject:remoteStructureTask];
    
    CDEAsynchronousTaskBlock eventStoreTask = ^(CDEAsynchronousTaskCallbackBlock next) {
        [self setupEventStoreWithCompletion:^(NSError *error) {
            next(error, NO);
        }];
    };
    [tasks addObject:eventStoreTask];
    
    CDEAsynchronousTaskBlock importTask = ^(CDEAsynchronousTaskCallbackBlock next) {
        // Listen for save notifications, and fail if a save to the store happens during the import
        saveOccurredDuringImport = NO;
        [self beginObservingSaveNotifications];
        
        // Inform delegate of import
        if ([self.delegate respondsToSelector:@selector(persistentStoreEnsembleWillImportStore:)]) {
            [self.delegate persistentStoreEnsembleWillImportStore:self];
        }
        
        CDEPersistentStoreImporter *importer = [[CDEPersistentStoreImporter alloc] initWithPersistentStoreAtPath:self.storeURL.path managedObjectModel:self.managedObjectModel eventStore:self.eventStore];
        importer.persistentStoreOptions = self.persistentStoreOptions;
        importer.ensemble = self;
        [importer importWithCompletion:^(NSError *error) {
            [self endObservingSaveNotifications];
            
            if (nil == error) {
                // Store baseline
                self.eventStore.identifierOfBaselineUsedToConstructStore = [self.eventStore currentBaselineIdentifier];
                
                // Inform delegate
                if ([self.delegate respondsToSelector:@selector(persistentStoreEnsembleDidImportStore:)]) {
                    [self.delegate persistentStoreEnsembleDidImportStore:self];
                }
            }
            
            // Reset the event store
            [eventStore.managedObjectContext performBlockAndWait:^{
                [eventStore.managedObjectContext reset];
            }];
            
            next(error, NO);
        }];
    };
    [tasks addObject:importTask];
    
    CDEAsynchronousTaskBlock snapshotRemoteFilesTask = ^(CDEAsynchronousTaskCallbackBlock next) {
        [self.cloudManager snapshotRemoteFilesWithCompletion:^(NSError *error) {
            next(error, NO);
        }];
    };
    [tasks addObject:snapshotRemoteFilesTask];
    
    CDEAsynchronousTaskBlock exportDataFilesTask = ^(CDEAsynchronousTaskCallbackBlock next) {
        [self.cloudManager exportDataFilesWithCompletion:^(NSError *error) {
            next(error, NO);
        }];
    };
    [tasks addObject:exportDataFilesTask];
    
    CDEAsynchronousTaskBlock exportBaselinesTask = ^(CDEAsynchronousTaskCallbackBlock next) {
        [self.cloudManager exportNewLocalBaselineWithCompletion:^(NSError *error) {
            if (error) CDELog(CDELoggingLevelError, @"Failed to export baseline file during leech. Continuing regardless.");
            next(nil, NO); // If the export fails, continue regardless. Not essential.
        }];
    };
    [tasks addObject:exportBaselinesTask];
    
    CDEAsynchronousTaskBlock completeLeechTask = ^(CDEAsynchronousTaskCallbackBlock next) {
        // Reset the event store
        [self.eventStore.managedObjectContext performBlockAndWait:^{
            [eventStore.managedObjectContext reset];
        }];
        
        // Deleech if a save occurred during import
        if (saveOccurredDuringImport) {
            NSError *error = nil;
            error = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeSaveOccurredDuringLeeching userInfo:nil];
            [self forceDeleechDueToError:error];
            next(error, NO);
            return;
        }
        
        // Register in cloud
        NSDictionary *info = @{kCDEStoreIdentifierKey: self.eventStore.persistentStoreIdentifier, kCDELeechDate: [NSDate date]};
        [self.cloudManager setRegistrationInfo:info forStoreWithIdentifier:self.eventStore.persistentStoreIdentifier completion:^(NSError *error) {
            next(error, NO);
        }];
    };
    [tasks addObject:completeLeechTask];
    
    CDEAsynchronousTaskQueue *taskQueue = [[CDEAsynchronousTaskQueue alloc] initWithTasks:tasks terminationPolicy:CDETaskQueueTerminationPolicyStopOnError completion:^(NSError *error) {
        [self dispatchCompletion:completion withError:error];
    }];
    
    [operationQueue addOperation:taskQueue];
}

- (void)setupEventStoreWithCompletion:(CDECompletionBlock)completion
{    
    NSError *error = nil;
    eventStore.cloudFileSystemIdentityToken = self.cloudFileSystem.identityToken;
    BOOL success = [eventStore prepareNewEventStore:&error];
    dispatch_async(dispatch_get_main_queue(), ^{
        self.leeched = success;
        if (completion) completion(error);
    });
}

- (void)deleechPersistentStoreWithCompletion:(CDECompletionBlock)completion
{
    NSAssert([NSThread isMainThread], @"Deleech method called off main thread");
    
    CDEAsynchronousTaskBlock deleechTask = ^(CDEAsynchronousTaskCallbackBlock next) {
        if (!self.isLeeched) {
            [eventStore removeEventStore];
            NSError *error = [[NSError alloc] initWithDomain:CDEErrorDomain code:CDEErrorCodeDisallowedStateChange userInfo:nil];
            next(error, NO);
            return;
        }
        
        BOOL removedStore = [eventStore removeEventStore];
        self.leeched = eventStore.containsEventData;
        
        NSError *error = nil;
        if (!removedStore) error = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeUnknown userInfo:nil];
        next(error, NO);
    };
    
    CDEAsynchronousTaskQueue *deleechQueue = [[CDEAsynchronousTaskQueue alloc] initWithTask:deleechTask completion:^(NSError *error) {
        [self dispatchCompletion:completion withError:error];
    }];
    
    [operationQueue cancelAllOperations];
    [operationQueue addOperation:deleechQueue];
}

#pragma mark Observing saves during import

- (void)beginObservingSaveNotifications
{
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(managedObjectContextWillSave:) name:NSManagedObjectContextWillSaveNotification object:nil];
}

- (void)endObservingSaveNotifications
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSManagedObjectContextWillSaveNotification object:nil];
}

- (void)managedObjectContextWillSave:(NSNotification *)notif
{
    NSManagedObjectContext *context = notif.object;
    NSArray *stores = context.persistentStoreCoordinator.persistentStores;
    for (NSPersistentStore *store in stores) {
        NSURL *url1 = [self.storeURL URLByStandardizingPath];
        NSURL *url2 = [store.URL URLByStandardizingPath];
        if ([url1 isEqual:url2]) {
            saveOccurredDuringImport = YES;
            break;
        }
    }
}

#pragma mark Checks

- (void)forceDeleechDueToError:(NSError *)deleechError
{
    [self deleechPersistentStoreWithCompletion:^(NSError *error) {
        if (!error) {
            if ([self.delegate respondsToSelector:@selector(persistentStoreEnsemble:didDeleechWithError:)]) {
                [self.delegate persistentStoreEnsemble:self didDeleechWithError:deleechError];
            }
        }
        else {
            CDELog(CDELoggingLevelError, @"Could not force deleech");
        }
    }];
}

- (void)checkCloudFileSystemIdentityWithCompletion:(CDECompletionBlock)completion
{
    BOOL identityValid = [self.cloudFileSystem.identityToken isEqual:self.eventStore.cloudFileSystemIdentityToken];
    if (self.leeched && !identityValid) {
        NSError *deleechError = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeCloudIdentityChanged userInfo:nil];
        [self forceDeleechDueToError:deleechError];
        if (completion) completion(deleechError);
    }
    else {
        [self dispatchCompletion:completion withError:nil];
    }
}

- (void)checkStoreRegistrationInCloudWithCompletion:(CDECompletionBlock)completion
{
    if (!self.eventStore.verifiesStoreRegistrationInCloud) {
        [self dispatchCompletion:completion withError:nil];
        return;
    }
    
    NSString *storeId = self.eventStore.persistentStoreIdentifier;
    [self.cloudManager retrieveRegistrationInfoForStoreWithIdentifier:storeId completion:^(NSDictionary *info, NSError *error) {
        if (!error && !info) {
            NSError *unregisteredError = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeStoreUnregistered userInfo:nil];
            [self forceDeleechDueToError:unregisteredError];
            if (completion) completion(unregisteredError);
        }
        else {
            // If there was an error, can't conclude anything about registration state. Assume registered.
            // Don't want to deleech for no good reason.
            [self dispatchCompletion:completion withError:nil];
        }
    }];
}

#pragma mark Accessors

- (NSURL *)localDataRootDirectoryURL
{
    return [NSURL fileURLWithPath:self.eventStore.pathToEventDataRootDirectory];
}

#pragma mark Merging Changes

- (void)mergeWithCompletion:(CDECompletionBlock)completion
{
    NSAssert([NSThread isMainThread], @"Merge method called off main thread");
    
    NSMutableArray *tasks = [NSMutableArray array];
    
    CDEAsynchronousTaskBlock setupTask = ^(CDEAsynchronousTaskCallbackBlock next) {
        if (!self.leeched) {
            NSError *error = [[NSError alloc] initWithDomain:CDEErrorDomain code:CDEErrorCodeDisallowedStateChange userInfo:@{NSLocalizedDescriptionKey : @"Attempt to merge a store that is not leeched."}];
            next(error, NO);
            return;
        }
        
        NSFileManager *fileManager = [[NSFileManager alloc] init];
        if (![fileManager fileExistsAtPath:storeURL.path]) {
            NSError *error = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeMissingStore userInfo:nil];
            next(error, NO);
            return;
        }
        
        self.merging = YES;
        
        [self.eventIntegrator startMonitoringSaves]; // Will cancel merge if save occurs
        
        next(nil, NO);
    };
    [tasks addObject:setupTask];
    
    CDEAsynchronousTaskBlock repairTask = ^(CDEAsynchronousTaskCallbackBlock next) {
        if ([cloudFileSystem respondsToSelector:@selector(repairEnsembleDirectory:completion:)]) {
            [cloudFileSystem repairEnsembleDirectory:self.cloudManager.remoteEnsembleDirectory completion:^(NSError *error) {
                next(error, NO);
            }];
        }
        else {
            next(nil, NO);
        }
    };
    [tasks addObject:repairTask];
    
    CDEAsynchronousTaskBlock checkIdentityTask = ^(CDEAsynchronousTaskCallbackBlock next) {
        [self checkCloudFileSystemIdentityWithCompletion:^(NSError *error) {
            next(error, NO);
        }];
    };
    [tasks addObject:checkIdentityTask];
    
    CDEAsynchronousTaskBlock checkRegistrationTask = ^(CDEAsynchronousTaskCallbackBlock next) {
        [self checkStoreRegistrationInCloudWithCompletion:^(NSError *error) {
            next(error, NO);
        }];
    };
    [tasks addObject:checkRegistrationTask];
    
    CDEAsynchronousTaskBlock processChangesTask = ^(CDEAsynchronousTaskCallbackBlock next) {
        [eventStore flushWithCompletion:^(NSError *error) {
            next(error, NO);
        }];
    };
    [tasks addObject:processChangesTask];
    
    CDEAsynchronousTaskBlock remoteStructureTask = ^(CDEAsynchronousTaskCallbackBlock next) {
        [self.cloudManager createRemoteDirectoryStructureWithCompletion:^(NSError *error) {
            next(error, NO);
        }];
    };
    [tasks addObject:remoteStructureTask];
    
    CDEAsynchronousTaskBlock snapshotRemoteFilesTask = ^(CDEAsynchronousTaskCallbackBlock next) {
        [self.cloudManager snapshotRemoteFilesWithCompletion:^(NSError *error) {
            next(error, NO);
        }];
    };
    [tasks addObject:snapshotRemoteFilesTask];
    
    CDEAsynchronousTaskBlock removeOutOfDateNewlyImportedFiles = ^(CDEAsynchronousTaskCallbackBlock next) {
        NSError *error = nil;
        BOOL success = [self.cloudManager removeOutOfDateNewlyImportedFiles:&error];
        next((success ? nil : error), NO);
    };
    [tasks addObject:removeOutOfDateNewlyImportedFiles];
    
    CDEAsynchronousTaskBlock importDataFilesTask = ^(CDEAsynchronousTaskCallbackBlock next) {
        [self.cloudManager importNewDataFilesWithCompletion:^(NSError *error) {
            next(error, NO);
        }];
    };
    [tasks addObject:importDataFilesTask];

    CDEAsynchronousTaskBlock importBaselinesTask = ^(CDEAsynchronousTaskCallbackBlock next) {
        [self.cloudManager importNewBaselineEventsWithCompletion:^(NSError *error) {
            next(error, NO);
        }];
    };
    [tasks addObject:importBaselinesTask];
    
    CDEAsynchronousTaskBlock mergeBaselinesTask = ^(CDEAsynchronousTaskCallbackBlock next) {
        [self.baselineConsolidator consolidateBaselineWithCompletion:^(NSError *error) {
            next(error, NO);
        }];
    };
    [tasks addObject:mergeBaselinesTask];
    
    CDEAsynchronousTaskBlock importRemoteEventsTask = ^(CDEAsynchronousTaskCallbackBlock next) {
        [self.cloudManager importNewRemoteNonBaselineEventsWithCompletion:^(NSError *error) {
            next(error, NO);
        }];
    };
    [tasks addObject:importRemoteEventsTask];
    
    CDEAsynchronousTaskBlock removeOutdatedEventsTask = ^(CDEAsynchronousTaskCallbackBlock next) {
        [self.rebaser deleteEventsPreceedingBaselineWithCompletion:^(NSError *error) {
            next(error, NO);
        }];
    };
    [tasks addObject:removeOutdatedEventsTask];
    
    CDEAsynchronousTaskBlock rebaseTask = ^(CDEAsynchronousTaskCallbackBlock next) {
        [self.rebaser shouldRebaseWithCompletion:^(BOOL result) {
            if (result) {
                [self.rebaser rebaseWithCompletion:^(NSError *error) {
                    next(error, NO);
                }];
            }
            else {
                next(nil, NO);
            }
        }];
    };
    [tasks addObject:rebaseTask];
    
    CDEAsynchronousTaskBlock mergeEventsTask = ^(CDEAsynchronousTaskCallbackBlock next) {
        [self.eventIntegrator mergeEventsWithCompletion:^(NSError *error) {
            // Store baseline id if everything went well
            if (nil == error) self.eventStore.identifierOfBaselineUsedToConstructStore = [self.eventStore currentBaselineIdentifier];
            next(error, NO);
        }];
    };
    [tasks addObject:mergeEventsTask];
    
    CDEAsynchronousTaskBlock exportDataFilesTask = ^(CDEAsynchronousTaskCallbackBlock next) {
        [self.eventStore removeUnreferencedDataFiles];
        [self.cloudManager exportDataFilesWithCompletion:^(NSError *error) {
            next(error, NO);
        }];
    };
    [tasks addObject:exportDataFilesTask];
    
    CDEAsynchronousTaskBlock exportBaselinesTask = ^(CDEAsynchronousTaskCallbackBlock next) {
        [self.cloudManager exportNewLocalBaselineWithCompletion:^(NSError *error) {
            next(error, NO);
        }];
    };
    [tasks addObject:exportBaselinesTask];
    
    CDEAsynchronousTaskBlock exportEventsTask = ^(CDEAsynchronousTaskCallbackBlock next) {
        [self.cloudManager exportNewLocalNonBaselineEventsWithCompletion:^(NSError *error) {
            next(error, NO);
        }];
    };
    [tasks addObject:exportEventsTask];
    
    CDEAsynchronousTaskBlock removeRemoteFiles = ^(CDEAsynchronousTaskCallbackBlock next) {
        [self.cloudManager removeOutdatedRemoteFilesWithCompletion:^(NSError *error) {
            next(error, NO);
        }];
    };
    [tasks addObject:removeRemoteFiles];
    
    CDEAsynchronousTaskQueue *taskQueue = [[CDEAsynchronousTaskQueue alloc] initWithTasks:tasks terminationPolicy:CDETaskQueueTerminationPolicyStopOnError completion:^(NSError *error) {
        [self dispatchCompletion:completion withError:error];
        [self.eventIntegrator stopMonitoringSaves];
        self.merging = NO;
    }];
    
    taskQueue.info = kCDEMergeTaskInfo;
    [operationQueue addOperation:taskQueue];
}

- (void)cancelMergeWithCompletion:(CDECompletionBlock)completion
{
    NSAssert([NSThread isMainThread], @"cancel merge method called off main thread");
    for (NSOperation *operation in operationQueue.operations) {
        if ([operation respondsToSelector:@selector(info)] && [[(id)operation info] isEqual:kCDEMergeTaskInfo]) {
            [operation cancel];
        }
    }
    [operationQueue addOperationWithBlock:^{
        [self dispatchCompletion:completion withError:nil];
    }];
}

#pragma mark Prepare for app termination

- (void)processPendingChangesWithCompletion:(CDECompletionBlock)completion
{
    NSAssert([NSThread isMainThread], @"Process pending changes invoked off main thread");
    
    if (!self.leeched) {
        [self dispatchCompletion:completion withError:nil];
        return;
    }
    
    [operationQueue addOperationWithBlock:^{
        [eventStore flushWithCompletion:^(NSError *error) {
            [self dispatchCompletion:completion withError:error];
        }];
    }];
}

- (void)stopMonitoringSaves
{
    NSAssert([NSThread isMainThread], @"stop monitor method called off main thread");
    [saveMonitor stopMonitoring];
}

#pragma mark Event Builder Delegate

- (NSArray *)globalIdentifiersForManagedObjects:(NSArray *)objects
{
    NSArray *result = nil;
    if ([self.delegate respondsToSelector:@selector(persistentStoreEnsemble:globalIdentifiersForManagedObjects:)]) {
        result = [self.delegate persistentStoreEnsemble:self globalIdentifiersForManagedObjects:objects];
    }
    return result;
}

@end
