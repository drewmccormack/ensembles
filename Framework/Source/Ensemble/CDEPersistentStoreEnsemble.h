//
//  CDESyncensemble.h
//  Ensembles
//
//  Created by Drew McCormack on 4/11/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#import "CDEDefines.h"


@class CDEPersistentStoreEnsemble;
@protocol CDECloudFileSystem;

extern NSString * const CDEMonitoredManagedObjectContextWillSaveNotification;
extern NSString * const CDEMonitoredManagedObjectContextDidSaveNotification;
extern NSString * const CDEPersistentStoreEnsembleDidSaveMergeChangesNotification;

@protocol CDEPersistentStoreEnsembleDelegate <NSObject>

@optional

- (void)persistentStoreEnsembleWillImportStore:(CDEPersistentStoreEnsemble *)ensemble;
- (void)persistentStoreEnsembleDidImportStore:(CDEPersistentStoreEnsemble *)ensemble;

- (void)persistentStoreEnsemble:(CDEPersistentStoreEnsemble *)ensemble willSaveMergedChangesInManagedObjectContext:(NSManagedObjectContext *)savingContext reparationManagedObjectContext:(NSManagedObjectContext *)reparationContext;
- (BOOL)persistentStoreEnsemble:(CDEPersistentStoreEnsemble *)ensemble didFailToSaveMergedChangesInManagedObjectContext:(NSManagedObjectContext *)savingContext error:(NSError *)error reparationManagedObjectContext:(NSManagedObjectContext *)reparationContext;
- (void)persistentStoreEnsemble:(CDEPersistentStoreEnsemble *)ensemble didSaveMergeChangesWithNotification:(NSNotification *)notification;

- (void)persistentStoreEnsemble:(CDEPersistentStoreEnsemble *)ensemble didDeleechWithError:(NSError *)error;

- (NSArray *)persistentStoreEnsemble:(CDEPersistentStoreEnsemble *)ensemble globalIdentifiersForManagedObjects:(NSArray *)objects;

@end


@interface CDEPersistentStoreEnsemble : NSObject

@property (nonatomic, weak, readwrite) id <CDEPersistentStoreEnsembleDelegate> delegate;
@property (nonatomic, strong, readonly) id <CDECloudFileSystem> cloudFileSystem;
@property (nonatomic, strong, readonly) NSString *localDataRootDirectory;
@property (nonatomic, strong, readonly) NSString *ensembleIdentifier;
@property (nonatomic, strong, readonly) NSString *storePath;
@property (nonatomic, strong, readonly) NSURL *managedObjectModelURL;
@property (nonatomic, strong, readonly) NSManagedObjectModel *managedObjectModel;
@property (nonatomic, assign, readonly, getter = isLeeched) BOOL leeched;
@property (nonatomic, assign, readonly, getter = isMerging) BOOL merging;

- (instancetype)initWithEnsembleIdentifier:(NSString *)identifier persistentStorePath:(NSString *)path managedObjectModelURL:(NSURL *)modelURL cloudFileSystem:(id <CDECloudFileSystem>)newCloudFileSystem;
- (instancetype)initWithEnsembleIdentifier:(NSString *)identifier persistentStorePath:(NSString *)path managedObjectModelURL:(NSURL *)modelURL cloudFileSystem:(id <CDECloudFileSystem>)newCloudFileSystem localDataRootDirectory:(NSString *)dataRoot;

- (void)leechPersistentStoreWithCompletion:(CDECompletionBlock)completion;
- (void)deleechPersistentStoreWithCompletion:(CDECompletionBlock)completion;

- (void)mergeWithCompletion:(CDECompletionBlock)completion;
- (void)cancelMergeWithCompletion:(CDECompletionBlock)completion;

- (void)processPendingChangesWithCompletion:(CDECompletionBlock)block;

- (void)stopMonitoringSaves;

@end

@interface CDEPersistentStoreEnsemble (Internal)

- (NSArray *)globalIdentifiersForManagedObjects:(NSArray *)objects;

@end
