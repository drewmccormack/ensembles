//
//  CDESyncEngine.m
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

static NSString * const kCDEIdentityTokenContext = @"kCDEIdentityTokenContext";

static NSString * const kCDEStoreIdentifierKey = @"storeIdentifier";
static NSString * const kCDELeechDate = @"leechDate";

NSString * const CDEMonitoredManagedObjectContextWillSaveNotification = @"CDEMonitoredManagedObjectContextWillSaveNotification";
NSString * const CDEMonitoredManagedObjectContextDidSaveNotification = @"CDEMonitoredManagedObjectContextDidSaveNotification";


@interface CDEPersistentStoreEnsemble ()

@property (nonatomic, strong, readwrite) CDECloudManager *cloudManager;
@property (nonatomic, strong, readwrite) id <CDECloudFileSystem> cloudFileSystem;
@property (nonatomic, strong, readwrite) NSString *ensembleIdentifier;
@property (nonatomic, strong, readwrite) NSString *storePath;
@property (nonatomic, strong, readwrite) NSManagedObjectModel *managedObjectModel;
@property (nonatomic, strong, readwrite) NSURL *managedObjectModelURL;
@property (nonatomic, assign, readwrite, getter = isLeeched) BOOL leeched;
@property (nonatomic, assign, readwrite, getter = isMerging) BOOL merging;
@property (nonatomic, strong, readwrite) CDEEventStore *eventStore;
@property (nonatomic, strong, readwrite) CDESaveMonitor *saveMonitor;
@property (nonatomic, strong, readwrite) CDEEventIntegrator *eventIntegrator;

@end


@implementation CDEPersistentStoreEnsemble {
    BOOL saveOccurredDuringImport;
    NSOperationQueue *operationQueue;
}

@synthesize cloudFileSystem = cloudFileSystem;
@synthesize ensembleIdentifier = ensembleIdentifier;
@synthesize storePath = storePath;
@synthesize leeched = leeched;
@synthesize merging = merging;
@synthesize cloudManager = cloudManager;
@synthesize eventStore = eventStore;
@synthesize saveMonitor = saveMonitor;
@synthesize eventIntegrator = eventIntegrator;
@synthesize managedObjectModel = managedObjectModel;
@synthesize managedObjectModelURL = managedObjectModelURL;

#pragma mark - Initialization and Deallocation

- (instancetype)initWithEnsembleIdentifier:(NSString *)identifier persistentStorePath:(NSString *)path managedObjectModelURL:(NSURL *)modelURL cloudFileSystem:(id <CDECloudFileSystem>)newCloudFileSystem localDataRootDirectory:(NSString *)eventDataRoot
{
    self = [super init];
    if (self) {
        operationQueue = [[NSOperationQueue alloc] init];
        operationQueue.maxConcurrentOperationCount = 1;
        
        self.ensembleIdentifier = identifier;
        self.storePath = path;
        self.managedObjectModelURL = modelURL;
        self.managedObjectModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
        self.cloudFileSystem = newCloudFileSystem;
    
        self.eventStore = [[CDEEventStore alloc] initWithEnsembleIdentifier:self.ensembleIdentifier pathToEventDataRootDirectory:eventDataRoot];
        self.leeched = eventStore.containsEventData;
        
        [self initializeEventIntegrator];
        
        self.saveMonitor = [[CDESaveMonitor alloc] initWithStorePath:path];
        self.saveMonitor.ensemble = self;
        self.saveMonitor.eventStore = eventStore;
        self.saveMonitor.eventIntegrator = self.eventIntegrator;
        
        self.cloudManager = [[CDECloudManager alloc] initWithEventStore:self.eventStore cloudFileSystem:self.cloudFileSystem];
        
        [self performInitialChecks];
    }
    return self;
}

- (instancetype)initWithEnsembleIdentifier:(NSString *)identifier persistentStorePath:(NSString *)path managedObjectModelURL:(NSURL *)modelURL cloudFileSystem:(id <CDECloudFileSystem>)newCloudFileSystem
{
    return [self initWithEnsembleIdentifier:identifier persistentStorePath:path managedObjectModelURL:modelURL cloudFileSystem:newCloudFileSystem localDataRootDirectory:nil];
}

- (void)initializeEventIntegrator
{
    NSURL *url = [NSURL fileURLWithPath:self.storePath];
    self.eventIntegrator = [[CDEEventIntegrator alloc] initWithStoreURL:url managedObjectModel:self.managedObjectModel eventStore:self.eventStore];
    self.eventIntegrator.ensemble = self;
    
    __weak CDEPersistentStoreEnsemble *weakSelf = self;
    self.eventIntegrator.willSaveBlock = ^(NSManagedObjectContext *savingContext, NSManagedObjectContext *reparationContext) {
        CDEPersistentStoreEnsemble *strongSelf = weakSelf;
        if ([strongSelf.delegate respondsToSelector:@selector(persistentStoreEnsemble:willSaveMergedChangesInManagedObjectContext:reparationManagedObjectContext:)]) {
            [strongSelf.delegate persistentStoreEnsemble:strongSelf willSaveMergedChangesInManagedObjectContext:savingContext reparationManagedObjectContext:reparationContext];
        }
    };
    
    self.eventIntegrator.failedSaveBlock = ^(NSManagedObjectContext *savingContext, NSError *error, NSManagedObjectContext *reparationContext) {
        CDEPersistentStoreEnsemble *strongSelf = weakSelf;
        if ([strongSelf.delegate respondsToSelector:@selector(persistentStoreEnsemble:didFailToSaveMergedChangesInManagedObjectContext:error:reparationManagedObjectContext:)]) {
            return [strongSelf.delegate persistentStoreEnsemble:strongSelf didFailToSaveMergedChangesInManagedObjectContext:savingContext error:error reparationManagedObjectContext:reparationContext];
        }
        return NO;
    };
    
    self.eventIntegrator.didSaveBlock = ^(NSManagedObjectContext *context, NSDictionary *info) {
        CDEPersistentStoreEnsemble *strongSelf = weakSelf;
        if ([strongSelf.delegate respondsToSelector:@selector(persistentStoreEnsemble:didSaveMergeChangesWithNotification:)]) {
            NSNotification *notification = [NSNotification notificationWithName:NSManagedObjectContextDidSaveNotification object:context userInfo:info];
            [strongSelf.delegate persistentStoreEnsemble:strongSelf didSaveMergeChangesWithNotification:notification];
        }
    };
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [saveMonitor stopMonitoring];
}

#pragma mark - Initial Checks

- (void)performInitialChecks
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (![self checkIncompleteEvents]) return;
        [self checkCloudFileSystemIdentityWithCompletion:^(NSError *error) {
            if (!error) {
                [(id)self.cloudFileSystem addObserver:self forKeyPath:@"identityToken" options:0 context:(__bridge void *)kCDEIdentityTokenContext];
            }
        }];
    });
}

- (BOOL)checkIncompleteEvents
{
    BOOL succeeded = YES;
    if (eventStore.incompleteMandatoryEventIdentifiers.count > 0) {
        succeeded = NO;
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
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [eventStore deregisterIncompleteEventIdentifier:eventId];
                    });
                }
                else {
                    CDELog(CDELoggingLevelError, @"Could not save after deleting incomplete event: %@", error);
                }
            }];
        }
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
    
    if (self.isLeeched) {
        NSError *error = [[NSError alloc] initWithDomain:CDEErrorDomain code:CDEErrorCodeDisallowedStateChange userInfo:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(error);
        });
        return;
    }
    
    CDEAsynchronousTaskBlock connectTask = ^(CDEAsynchronousTaskCallbackBlock next) {
        [self.cloudFileSystem connect:^(NSError *error) {
            next(error, NO);
        }];
    };
    
    CDEAsynchronousTaskBlock initialPrepTask = ^(CDEAsynchronousTaskCallbackBlock next) {
        [self.cloudFileSystem performInitialPreparation:^(NSError *error) {
            next(error, NO);
        }];
    };
    
    CDEAsynchronousTaskBlock remoteStructureTask = ^(CDEAsynchronousTaskCallbackBlock next) {
        [self.cloudManager createRemoteDirectoryStructureWithCompletion:^(NSError *error) {
            next(error, NO);
        }];
    };
    
    CDEAsynchronousTaskBlock eventStoreTask = ^(CDEAsynchronousTaskCallbackBlock next) {
        [self setupEventStoreWithCompletion:^(NSError *error) {
            next(error, NO);
        }];
    };
    
    CDEAsynchronousTaskBlock importTask = ^(CDEAsynchronousTaskCallbackBlock next) {
        // Listen for save notifications, and fail if a save to the store happens during the import
        saveOccurredDuringImport = NO;
        [self beginObservingSaveNotifications];
        
        // Inform delegate of import
        if ([self.delegate respondsToSelector:@selector(persistentStoreEnsembleWillImportStore:)]) {
            [self.delegate persistentStoreEnsembleWillImportStore:self];
        }
        
        CDEPersistentStoreImporter *importer = [[CDEPersistentStoreImporter alloc] initWithPersistentStoreAtPath:self.storePath managedObjectModel:self.managedObjectModel eventStore:self.eventStore];
        importer.ensemble = self;
        [importer importWithCompletion:^(NSError *error) {
            [self endObservingSaveNotifications];
            
            if (!error && [self.delegate respondsToSelector:@selector(persistentStoreEnsembleDidImportStore:)]) {
                [self.delegate persistentStoreEnsembleDidImportStore:self];
            }
            
            next(error, NO);
        }];
    };
    
    CDEAsynchronousTaskBlock completeLeechTask = ^(CDEAsynchronousTaskCallbackBlock next) {
        // Deleech if a save occurred during import
        if (saveOccurredDuringImport) {
            NSError *error = nil;
            error = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorSaveOccurredDuringLeeching userInfo:nil];
            [self performSelector:@selector(forceDeleechDueToError:) withObject:error afterDelay:0.0];
            next(error, NO);
            return;
        }
        
        // Register in cloud
        NSDictionary *info = @{kCDEStoreIdentifierKey: self.eventStore.persistentStoreIdentifier, kCDELeechDate: [NSDate date]};
        [self.cloudManager setRegistrationInfo:info forStoreWithIdentifier:self.eventStore.persistentStoreIdentifier completion:^(NSError *error) {
            next(error, NO);
        }];
    };
    
    NSMutableArray *tasks = [NSMutableArray arrayWithObjects:connectTask, remoteStructureTask, eventStoreTask, importTask, completeLeechTask, nil];
    
    if ([self.cloudFileSystem respondsToSelector:@selector(performInitialPreparation:)]) {
        [tasks insertObject:initialPrepTask atIndex:1];
    }
    
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
        if ([self.storePath isEqualToString:store.URL.path]) {
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
        [self performSelector:@selector(forceDeleechDueToError:) withObject:deleechError afterDelay:0.0];
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
            [self performSelector:@selector(forceDeleechDueToError:) withObject:unregisteredError afterDelay:0.0];
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

- (NSString *)localDataRootDirectory
{
    return self.eventStore.pathToEventDataRootDirectory;
}

#pragma mark Merging Changes

- (void)mergeWithCompletion:(CDECompletionBlock)completion
{
    NSAssert([NSThread isMainThread], @"Merge method called off main thread");
    
    if (!self.leeched) {
        NSError *error = [[NSError alloc] initWithDomain:CDEErrorDomain code:CDEErrorCodeDisallowedStateChange userInfo:@{NSLocalizedDescriptionKey : @"Attempt to merge a store that is not leeched."}];
        [self dispatchCompletion:completion withError:error];
        return;
    }
    
    if (self.merging) {
        NSError *error = [[NSError alloc] initWithDomain:CDEErrorDomain code:CDEErrorCodeDisallowedStateChange userInfo:@{NSLocalizedDescriptionKey : @"Attempt to merge when merge is already underway."}];
        [self dispatchCompletion:completion withError:error];
        return;
    }
    
    self.merging = YES;
    
    CDEAsynchronousTaskBlock checkIdentityTask = ^(CDEAsynchronousTaskCallbackBlock next) {
        [self checkCloudFileSystemIdentityWithCompletion:^(NSError *error) {
            next(error, NO);
        }];
    };
    
    CDEAsynchronousTaskBlock checkRegistrationTask = ^(CDEAsynchronousTaskCallbackBlock next) {
        [self checkStoreRegistrationInCloudWithCompletion:^(NSError *error) {
            next(error, NO);
        }];
    };
    
    CDEAsynchronousTaskBlock processChangesTask = ^(CDEAsynchronousTaskCallbackBlock next) {
        [self processPendingChangesWithCompletion:^(NSError *error) {
            next(error, NO);
        }];
    };
    
    CDEAsynchronousTaskBlock importRemoteEventsTask = ^(CDEAsynchronousTaskCallbackBlock next) {
        [self.cloudManager importNewRemoteEventsWithCompletion:^(NSError *error) {
            next(error, NO);
        }];
    };
    
    CDEAsynchronousTaskBlock mergeEventsTask = ^(CDEAsynchronousTaskCallbackBlock next) {
        CDERevisionNumber lastMerge = [self.eventStore lastMergeRevision];
        [self.eventIntegrator mergeEventsImportedSinceRevision:lastMerge completion:^(NSError *error) {
            next(error, NO);
        }];
    };
    
    CDEAsynchronousTaskBlock exportEventsTask = ^(CDEAsynchronousTaskCallbackBlock next) {
        [self.cloudManager exportNewLocalEventsWithCompletion:^(NSError *error) {
            next(error, NO);
        }];
    };
    
    NSArray *tasks = @[checkIdentityTask, checkRegistrationTask, processChangesTask, importRemoteEventsTask, mergeEventsTask, exportEventsTask];
    CDEAsynchronousTaskQueue *taskQueue = [[CDEAsynchronousTaskQueue alloc] initWithTasks:tasks terminationPolicy:CDETaskQueueTerminationPolicyStopOnError completion:^(NSError *error) {
        [self dispatchCompletion:completion withError:error];
        self.merging = NO;
    }];
    
    [operationQueue addOperation:taskQueue];
}

- (void)cancelMergeWithCompletion:(CDECompletionBlock)completion
{
    NSAssert([NSThread isMainThread], @"cancel merge method called off main thread");
    if (!self.isMerging) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(nil);
        });
    }
    else {
        // TODO: Write this. Will require cancel methods in other classes
    }
}

#pragma mark Prepare for app termination

- (void)processPendingChangesWithCompletion:(CDECompletionBlock)completion
{
    NSAssert([NSThread isMainThread], @"Process pending changes invoked off main thread");
    
    if (!self.leeched) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(nil);
        });
        return;
    }
    
    [operationQueue addOperationWithBlock:^{
        NSError *error = nil;
        [eventStore flush:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(error);
        });
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
