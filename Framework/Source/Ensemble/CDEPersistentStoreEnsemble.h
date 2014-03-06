//
//  CDEPersistentStoreEnsemble.h
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

///--------------------
/// @name Notifications
///--------------------

/**
 Posted when ensembles observes that a `NSManagedObjectContext` will save to the monitored persistent store. You can monitor this notification rather than the standard `NSManagedObjectContextWillSaveNotification` if you want to be sure that the ensemble has already prepared for the save when the notification is observed. If you observe `NSManagedObjectContextWillSaveNotification` directly, you can't be sure that the ensemble has observed the notification, because order of receivers is not defined.
 
 The object for the notification is not the ensemble, but the context that is saving. The ensemble observing the save is accessible in the `userInfo` dictionary via the key `persistentStoreEnsemble`.
 */
extern NSString * const CDEMonitoredManagedObjectContextWillSaveNotification;

/**
 Posted when the ensemble observes that a `NSManagedObjectContext` has saved to the monitored persistent store. You can monitor this notification rather than the standard `NSManagedObjectContexDidSaveNotification` if you want to be sure that the ensemble has already processed the save when the notification is observed. If you observe `NSManagedObjectContextDidSaveNotification` directly, you can't be sure that the ensemble has observed the notification, because order of receivers is not defined.
 
  The object for the notification is not the ensemble, but the context that is saving. The ensemble observing the save is accessible in the `userInfo` dictionary via the key `persistentStoreEnsemble`.
 */
extern NSString * const CDEMonitoredManagedObjectContextDidSaveNotification;

/**
 This notification is fired after the ensemble has merged changes and performed a background save into the persistent store. You can use this notification to invoke the `mergeChangesFromContextDidSaveNotification:` method on any of the contexts that depend on the content of the store. Alternatively, you can implement the `persistentStoreEnsemble:didSaveMergeChangesWithNotification:` method for this purpose.
 
 The object for the notification is the ensemble. The save notification, which is what is passed to the `mergeChangesFromContextDidSaveNotification:` method, is provided in the `userInfo` dictionary with the key `CDEManagedObjectContextSaveNotificationKey`.
 
 @warning This notification is posted on the background thread where the merge save occurred. It is important to invoke the `mergeChangesFromContextDidSaveNotification:` method on the thread/queue corresponding to the `NSManagedObjectContext` merging the changes.
 */
extern NSString * const CDEPersistentStoreEnsembleDidSaveMergeChangesNotification;

/**
 Used as a key in the `userInfo` dictionary of the `CDEPersistentStoreEnsembleDidSaveMergeChangesNotification` notification. It's value is the original notification resulting from the save, and can be passed to the `mergeChangesFromContextDidSaveNotification:` method to update other contexts that access the persistent store.
 */
extern NSString * const CDEManagedObjectContextSaveNotificationKey;

/**
 A protocol that includes methods invoked by the `CDEPeristentStoreEnsemble`. The ensemble uses this to inform of sync-related changes.
 */
@protocol CDEPersistentStoreEnsembleDelegate <NSObject>

@optional

/**
 Invoked during leeching when the contents of the persistent store are about to be migrated to the cloud.
 
 @param ensemble The `CDEPersistentStoreEnsemble`
 */
- (void)persistentStoreEnsembleWillImportStore:(CDEPersistentStoreEnsemble *)ensemble;

/**
 Invoked during leeching when the contents of the persistent store have been migrated to the cloud.
 
 @param ensemble The `CDEPersistentStoreEnsemble`
 */
- (void)persistentStoreEnsembleDidImportStore:(CDEPersistentStoreEnsemble *)ensemble;

// The following are invoked from a background thread
// Contexts are private queue type, and should be accessed using performBlock... methods
- (BOOL)persistentStoreEnsemble:(CDEPersistentStoreEnsemble *)ensemble shouldSaveMergedChangesInManagedObjectContext:(NSManagedObjectContext *)savingContext reparationManagedObjectContext:(NSManagedObjectContext *)reparationContext;
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
