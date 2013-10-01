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
#import "CDECloudFile.h"
#import "CDECloudDirectory.h"
#import "CDECloudFileSystem.h"
#import "CDESaveMonitor.h"
#import "CDEEventIntegrator.h"
#import "CDEEventBuilder.h"

static NSString * const kCDEIdentityTokenContext = @"kCDEIdentityTokenContext";

@interface CDEPersistentStoreEnsemble ()

@property (nonatomic, readwrite) CDECloudManager *cloudManager;
@property (nonatomic, readwrite) id <CDECloudFileSystem> cloudFileSystem;
@property (nonatomic, readwrite) NSString *ensembleIdentifier;
@property (nonatomic, readwrite) NSString *storePath;
@property (nonatomic, readwrite) NSManagedObjectModel *managedObjectModel;
@property (nonatomic, readwrite, getter = isLeeched) BOOL leeched;
@property (nonatomic, readwrite, getter = isMerging) BOOL merging;
@property (nonatomic, readwrite) CDEEventStore *eventStore;
@property (nonatomic, readwrite) CDESaveMonitor *saveMonitor;
@property (nonatomic, readwrite) CDEEventIntegrator *eventIntegrator;

@end


@implementation CDEPersistentStoreEnsemble

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

+ (instancetype)persistentStoreEnsembleForPersistentStoreCoordinator:(NSPersistentStoreCoordinator *)coordinator ensembleIdentifier:(NSString *)identifier cloudFileSystem:(id <CDECloudFileSystem>)cloudFileSystem
{
    NSAssert(coordinator.persistentStores.count == 1, @"Cannot use +persistentStoreEnsembleWithEnsembleIdentifier... if there are more than one stores");
    NSPersistentStore *store = coordinator.persistentStores.lastObject;
    id ensemble = [[CDEPersistentStoreEnsemble alloc] initWithEnsembleIdentifier:identifier persistentStorePath:store.URL.path managedObjectModel:coordinator.managedObjectModel cloudFileSystem:cloudFileSystem];
    return ensemble;
}

- (instancetype)initWithEnsembleIdentifier:(NSString *)identifier persistentStorePath:(NSString *)path managedObjectModel:(NSManagedObjectModel *)model cloudFileSystem:(id <CDECloudFileSystem>)newCloudFileSystem localDataRootDirectory:(NSString *)eventDataRoot
{
    self = [super init];
    if (self) {
        self.ensembleIdentifier = identifier;
        self.storePath = path;
        self.managedObjectModel = model;
        self.cloudFileSystem = newCloudFileSystem;
    
        self.eventStore = [[CDEEventStore alloc] initWithEnsembleIdentifier:self.ensembleIdentifier pathToEventDataRootDirectory:eventDataRoot];
        self.leeched = eventStore.containsEventData;
        
        [self initializeEventIntegrator];
        
        self.saveMonitor = [[CDESaveMonitor alloc] initWithStorePath:path];
        self.saveMonitor.ensemble = self;
        self.saveMonitor.eventStore = eventStore;
        self.saveMonitor.eventIntegrator = self.eventIntegrator;
        
        self.cloudManager = [[CDECloudManager alloc] initWithEventStore:self.eventStore cloudFileSystem:self.cloudFileSystem];
        
        [self checkCloudFileSystemIdentityWithCompletion:^(NSError *error) {
            if (!error) {
                [(id)self.cloudFileSystem addObserver:self forKeyPath:@"identityToken" options:0 context:(__bridge void *)kCDEIdentityTokenContext];
            }
        }];
    }
    return self;
}

- (instancetype)initWithEnsembleIdentifier:(NSString *)identifier persistentStorePath:(NSString *)path managedObjectModel:(NSManagedObjectModel *)model cloudFileSystem:(id <CDECloudFileSystem>)newCloudFileSystem
{
    return [self initWithEnsembleIdentifier:identifier persistentStorePath:path managedObjectModel:model cloudFileSystem:newCloudFileSystem localDataRootDirectory:nil];
}

- (void)initializeEventIntegrator
{
    NSURL *url = [NSURL fileURLWithPath:self.storePath];
    self.eventIntegrator = [[CDEEventIntegrator alloc] initWithStoreURL:url managedObjectModel:self.managedObjectModel eventStore:self.eventStore];
    self.eventIntegrator.ensemble = self;
    
    __weak CDEPersistentStoreEnsemble *weakSelf = self;
    self.eventIntegrator.willSaveBlock = ^(NSManagedObjectContext *context, NSDictionary *info) {
        CDEPersistentStoreEnsemble *strongSelf = weakSelf;
        if ([strongSelf.delegate respondsToSelector:@selector(persistentStoreEnsemble:willSaveMergedChangesInManagedObjectContext:info:)]) {
            [strongSelf.delegate persistentStoreEnsemble:strongSelf willSaveMergedChangesInManagedObjectContext:context info:info];
        }
    };
    
    self.eventIntegrator.failedSaveBlock = ^(NSManagedObjectContext *context, NSError *error) {
        CDEPersistentStoreEnsemble *strongSelf = weakSelf;
        if ([strongSelf.delegate respondsToSelector:@selector(persistentStoreEnsemble:didFailToSaveMergedChangesInManagedObjectContext:error:)]) {
            return [strongSelf.delegate persistentStoreEnsemble:strongSelf didFailToSaveMergedChangesInManagedObjectContext:context error:error];
        }
        return NO;
    };
    
    self.eventIntegrator.didSaveBlock = ^(NSManagedObjectContext *context, NSDictionary *info) {
        CDEPersistentStoreEnsemble *strongSelf = weakSelf;
        if ([strongSelf.delegate respondsToSelector:@selector(persistentStoreEnsemble:didSaveMergeChangesWithNotification:)]) {
            NSNotification *notification = [[NSNotification alloc] initWithName:NSManagedObjectContextDidSaveNotification object:context userInfo:info];
            [strongSelf.delegate persistentStoreEnsemble:strongSelf didSaveMergeChangesWithNotification:notification];
        }
    };
}

- (void)dealloc
{
    [saveMonitor stopMonitoring];
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
    
    [self.cloudFileSystem connect:^(NSError *error) {
        if (error) {
            if (completion) completion(error);
            return;
        }

        CDECodeBlock createRemoteStructure = ^{
            [self.cloudManager createRemoteDirectoryStructureWithCompletion:^(NSError *error) {
                if (error) {
                    if (completion) completion(error);
                    return;
                }
                
                [self setupEventStoreWithCompletion:^(NSError *error) {
                    if (error) {
                        if (completion) completion(error);
                        return;
                    }
                    
                    CDEPersistentStoreImporter *importer = [[CDEPersistentStoreImporter alloc] initWithPersistentStoreAtPath:self.storePath managedObjectModel:self.managedObjectModel eventStore:self.eventStore];
                    importer.ensemble = self;
                    [importer importWithCompletion:completion];
                }];
            }];
        };
        
        // Give cloud file system a chance to perform initial preparation
        if ([self.cloudFileSystem respondsToSelector:@selector(performInitialPreparation:)]) {
            [self.cloudFileSystem performInitialPreparation:^(NSError *error) {
                if (error) {
                    if (completion) completion(error);
                    return;
                }
                createRemoteStructure();
            }];
        }
        else {
            createRemoteStructure();
        }
    }];
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
    NSAssert([NSThread isMainThread], @"Remove store method called off main thread");
    
    if (!self.isLeeched) {
        NSError *error = [[NSError alloc] initWithDomain:CDEErrorDomain code:CDEErrorCodeDisallowedStateChange userInfo:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(error);
        });
        return;
    }

    BOOL success = [eventStore removeEventStore];
    self.leeched = eventStore.containsEventData;
    
    NSError *error = nil;
    if (!success) error = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeUnknown userInfo:nil];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (completion) completion(error);
    });
}

- (void)checkCloudFileSystemIdentityWithCompletion:(CDECompletionBlock)completion
{
    BOOL identityValid = [self.cloudFileSystem.identityToken isEqual:self.eventStore.cloudFileSystemIdentityToken];
    if (self.leeched && !identityValid) {
        [self deleechPersistentStoreWithCompletion:^(NSError *error) {
            if (!error) {
                NSError *deleechError = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeCloudIdentityChanged userInfo:nil];
                if (completion) completion(deleechError);
                
                if ([self.delegate respondsToSelector:@selector(persistentStoreEnsembleDidDeleechDueToCloudIdentityTokenChange:)]) {
                    [self.delegate persistentStoreEnsembleDidDeleechDueToCloudIdentityTokenChange:self];
                }
            }
            else {
                CDELog(CDELoggingLevelError, @"Could not deleech in identity check");
                if (completion) completion(nil);
            }
        }];
    }
    else {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(nil);
        });
    }
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
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(error);
        });
        return;
    }
    
    if (self.merging) {
        NSError *error = [[NSError alloc] initWithDomain:CDEErrorDomain code:CDEErrorCodeDisallowedStateChange userInfo:@{NSLocalizedDescriptionKey : @"Attempt to merge when merge is already underway."}];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(error);
        });
        return;
    }
    
    self.merging = YES;
    [self checkCloudFileSystemIdentityWithCompletion:^(NSError *error) {
        if (error) {
            if (completion) completion(error);
            self.merging = NO;
            return;
        }
        
        [self processPendingChangesWithCompletion:^(NSError *error) {
            [self.cloudManager importNewRemoteEventsWithCompletion:^(NSError *error) {
                if (error) {
                    if (completion) completion(error);
                    self.merging = NO;
                    return;
                }
                
                CDERevisionNumber lastMerge = [self.eventStore lastMergeRevision];
                [self.eventIntegrator mergeEventsImportedSinceRevision:lastMerge completion:^(NSError *error) {
                    if (error) {
                        if (completion) completion(error);
                        self.merging = NO;
                        return;
                    }

                    [self.cloudManager exportNewLocalEventsWithCompletion:^(NSError *error) {
                        if (completion) completion(error);
                        self.merging = NO;
                    }];
                }];
            }];
        }];
    }];
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
    
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSError *error = nil;
        [eventStore flush:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(error);
        });
    });
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
