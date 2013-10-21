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


@protocol CDEPersistentStoreEnsembleDelegate <NSObject>

@optional

- (void)persistentStoreEnsemble:(CDEPersistentStoreEnsemble *)ensemble willSaveMergedChangesInManagedObjectContext:(NSManagedObjectContext *)context info:(NSDictionary *)infoDict;
- (BOOL)persistentStoreEnsemble:(CDEPersistentStoreEnsemble *)ensemble didFailToSaveMergedChangesInManagedObjectContext:(NSManagedObjectContext *)context error:(NSError *)error;
- (void)persistentStoreEnsemble:(CDEPersistentStoreEnsemble *)ensemble didSaveMergeChangesWithNotification:(NSNotification *)notification;

- (void)persistentStoreEnsemble:(CDEPersistentStoreEnsemble *)ensemble didDeleechWithError:(NSError *)error;

- (NSArray *)persistentStoreEnsemble:(CDEPersistentStoreEnsemble *)ensemble globalIdentifiersForManagedObjects:(NSArray *)objects;

@end


@interface CDEPersistentStoreEnsemble : NSObject

@property (nonatomic, readwrite, weak) id <CDEPersistentStoreEnsembleDelegate> delegate;
@property (nonatomic, readonly) id <CDECloudFileSystem> cloudFileSystem;
@property (nonatomic, readonly) NSString *localDataRootDirectory;
@property (nonatomic, readonly) NSString *ensembleIdentifier;
@property (nonatomic, readonly) NSString *storePath;
@property (nonatomic, readonly) NSManagedObjectModel *managedObjectModel;
@property (nonatomic, readonly, getter = isLeeched) BOOL leeched;
@property (nonatomic, readonly, getter = isMerging) BOOL merging;

+ (instancetype)persistentStoreEnsembleForPersistentStoreCoordinator:(NSPersistentStoreCoordinator *)coordinator ensembleIdentifier:(NSString *)identifier cloudFileSystem:(id <CDECloudFileSystem>)cloudFileSystem;

- (instancetype)initWithEnsembleIdentifier:(NSString *)identifier persistentStorePath:(NSString *)path managedObjectModel:(NSManagedObjectModel *)model cloudFileSystem:(id <CDECloudFileSystem>)newCloudFileSystem;
- (instancetype)initWithEnsembleIdentifier:(NSString *)identifier persistentStorePath:(NSString *)path managedObjectModel:(NSManagedObjectModel *)model cloudFileSystem:(id <CDECloudFileSystem>)newCloudFileSystem localDataRootDirectory:(NSString *)dataRoot;

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
