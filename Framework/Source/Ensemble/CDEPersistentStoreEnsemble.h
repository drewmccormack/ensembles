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


///
/// @name Notifications
///

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
 This notification is fired after the ensemble has merged changes and performed a background save into the persistent store. You can use this notification to invoke the `mergeChangesFromContextDidSaveNotification`: method on any of the contexts that depend on the content of the store. Alternatively, you can implement the `persistentStoreEnsemble:didSaveMergeChangesWithNotification:` method for this purpose.
 
 The object for the notification is the ensemble. The save notification, which is what is passed to the `mergeChangesFromContextDidSaveNotification`: method, is provided in the `userInfo` dictionary with the key `CDEManagedObjectContextSaveNotificationKey`.
 
 @warning This notification is posted on the saving context background thread. It is important to invoke the `mergeChangesFromContextDidSaveNotification`: method on the thread/queue corresponding to the `NSManagedObjectContext` merging the changes.
 */
extern NSString * const CDEPersistentStoreEnsembleDidSaveMergeChangesNotification;

/**
 Used as a key in the `userInfo` dictionary of the `CDEPersistentStoreEnsembleDidSaveMergeChangesNotification` notification. It's value is the original notification resulting from the save, and can be passed to the `mergeChangesFromContextDidSaveNotification`: method to update other contexts that access the persistent store.
 */
extern NSString * const CDEManagedObjectContextSaveNotificationKey;


/**
 A protocol that includes methods invoked by the `CDEPeristentStoreEnsemble`. The ensemble uses this to inform of sync-related changes.
 */
@protocol CDEPersistentStoreEnsembleDelegate <NSObject>

@optional


///
/// @name Leeching
///

/**
 Invoked during leeching when the contents of the persistent store are about to be migrated to the cloud.
 
 @param ensemble The `CDEPersistentStoreEnsemble` that is about to import
 */
- (void)persistentStoreEnsembleWillImportStore:(CDEPersistentStoreEnsemble *)ensemble;

/**
 Invoked during leeching when the contents of the persistent store have been migrated to the cloud.
 
 @param ensemble The `CDEPersistentStoreEnsemble` that is importing the store
 */
- (void)persistentStoreEnsembleDidImportStore:(CDEPersistentStoreEnsemble *)ensemble;


///
/// @name Merging
///

/**
 Invoked when the ensemble is about to attempt to save merged changes into the persistent store.
 
 This method is invoked on a background thread. Both of the contexts passed have private queue concurrency type, and so they should only be accessed via calls to `performBlock...` methods.
 
 You can use the saving context to check what changes have been made in the merge via `NSManagedObjectContext` methods like `insertedObjects`, `updatedObjects`, and `deletedObjects`.
 
 You should not make any changes directly in the saving context. If you need to make changes before the save is attempted, you can make them in the reparation context.
 
 You can force the merge to terminate altogether by returning `NO` from this method.
 
 @param ensemble The `CDEPersistentStoreEnsemble` that will attempt to save
 @param savingContext A private-queue context which includes the unsaved changes that will be committed to the store
 @param reparationContext A private-queue context that can be used to make any changes necessary to allow the save to succeed
 @return YES if the save should be attempted, and NO to abort the merge entirely
 @warning Be careful not to nest calls to the `performBlock...` methods for the two contexts. This will very likely lead to a deadlock, because the contexts in question have a parent-child relationship.
 */
- (BOOL)persistentStoreEnsemble:(CDEPersistentStoreEnsemble *)ensemble shouldSaveMergedChangesInManagedObjectContext:(NSManagedObjectContext *)savingContext reparationManagedObjectContext:(NSManagedObjectContext *)reparationContext;

/**
 Invoked when the ensemble attempted to save merged changes into the persistent store, but the save failed.
 
 This method is invoked on a background thread. Both of the contexts passed have private queue concurrency type, and so they should only be accessed via calls to `performBlock...` methods.
 
 You can use the saving context to check what changes failed to save via `NSManagedObjectContext` methods like `insertedObjects`, `updatedObjects`, and `deletedObjects`. The error that occurred during saving is passed and can be used to determine which objects are responsible for the failure.
 
 You should not make any changes directly in the saving context. If you wish to reattempt the save, make any necessary changes in the reparation context, and then return `YES`.
 
 You can force the merge to terminate altogether by returning `NO` from this method.
 
 @param ensemble The `CDEPersistentStoreEnsemble` that attempted the save
 @param savingContext A private-queue context which includes the unsaved changes that will be committed to the store
 @param error The error returned by the `save`: method
 @param reparationContext A private-queue context that can be used to make any changes necessary to allow the save to be reattempted
 @return YES if the save should be reattempted, and NO to abort the merge entirely
 @warning Be careful not to nest calls to the `performBlock...` methods for the two contexts. This will very likely lead to a deadlock, because the contexts in question have a parent-child relationship.
 */
- (BOOL)persistentStoreEnsemble:(CDEPersistentStoreEnsemble *)ensemble didFailToSaveMergedChangesInManagedObjectContext:(NSManagedObjectContext *)savingContext error:(NSError *)error reparationManagedObjectContext:(NSManagedObjectContext *)reparationContext;

/**
 Invoked after the ensemble successfully saves merged changes into the persistent store.
 
 This method is invoked on the saving context background thread. The notification passed includes a `userInfo` dictionary based on the notification that was posted when the context saved. It contains the `NSManagedObject` instances for all insertions, updates, and deletions that were included in the save.
 
 You will usually want to pass this notification to the `mergeChangesFromContextDidSaveNotification`: method of any context that accesses the persistent store, be it directly or indirectly. This will allow the context to account for the changes.
 
 @warning Be sure to invoke the `mergeChangesFromContextDidSaveNotification`: method on the thread/queue corresponding to the messaged context.
 
 @param ensemble The `CDEPersistentStoreEnsemble` that saved the changes
 @param notification A notification object containing the `userInfo` from the saving context in the `NSManagedObjectContextDidSaveNotification` notification
 
 @see `CDEPersistentStoreEnsembleDidSaveMergeChangesNotification`
 */
- (void)persistentStoreEnsemble:(CDEPersistentStoreEnsemble *)ensemble didSaveMergeChangesWithNotification:(NSNotification *)notification;


///
/// @name Deleeching
///

/**
 Invoked when the ensemble is forced to deleech due to an unexpected issue.
 
 In normal operation, an ensemble will not deleech unless requested to do so. However, circumstances can arise that can compromise the integrity of the sync data, in which case, the ensemble can elect to spontaneously deleech. 
 
 By way of example, if the user logs out of the cloud service used for sync, the ensemble will deleech, as it no longer has access to the cloud data.
 
 You can use this method to update the interface to reflect the deleeched state, and perhaps notify the user of the issue. You can attempt to leech again to continue syncing.
 
 @param ensemble The ensemble that is deleeching
 @param error An error describing the cause of the deleech
 */
- (void)persistentStoreEnsemble:(CDEPersistentStoreEnsemble *)ensemble didDeleechWithError:(NSError *)error;


///
/// @name Object Identity
///

/**
 Supply global identifiers for objects.
 
 By default, the ensemble will generate random global identifiers for all objects. If logically-equivalent objects are inserted on multiple devices, after merging, there will be duplicates.
 
 You can either deduplicate these objects in code, by fetching, and deleting a duplicate, or you can instead provide global identifiers which Ensembles can use to identify corresponding objects and merge them automatically.
 
 Whenever the ensemble needs to know the global identifier of one or more objects, it will invoke this method. You can determine the identifiers as you please, but they must be immutable: an object should not have its global identifier change at any point. If you find you are tempted to change the global identifier of an object, it is better to delete the object instead, and create a new object with the new identifier.
 
 The global identifiers do not have to be stored in the persistent store, but it often works out to be the best solution. You can either determine the global identifier from existing properties (eg email, tag), or store a random identifier like a uuid.
 
 If you have certain objects in the array for which you do not wish to assign your own global identifier, you can return `NSNull` in that position.
 
 @param ensemble The ensemble requesting global identifiers
 @param objects The objects for which global identifiers are requested
 @return An array of global identifiers for the objects passed, in the same order. `NSNull` can be inserted in this array where no global identifier is needed.
 */
- (NSArray *)persistentStoreEnsemble:(CDEPersistentStoreEnsemble *)ensemble globalIdentifiersForManagedObjects:(NSArray *)objects;

@end


/**
 The central class of Ensembles, it represents a set of synchronizing persistent stores.
 
 An ensemble can be seen as a set of persistent stores that exchange data in order to reach eventual consistency. The `CDEPersistentStoreEnsemble` class is responsible for monitoring saves to a persistent store, exchanging this data with ensemble objects on other peers, and merging changes from other peers into its persistent store.
 
 You typically create one `CDEPersistentStoreEnsemble` object for each persistent store that you need to sync in your app. An ensemble has an identifier, which is used to match it with other ensemble objects on peer devices. Ensemble objects with the same identifier are considered to represent corresponding persistent stores, and the data in the persistent stores will be merged.
 
 The process of initially setting up an ensemble object for communication with its peers is known as 'leeching'. An ensemble begins in a deleeched state. Leeching prepares local storage needed by the framework, registers the device in the cloud, and migrates the data in the local persistent store into the cloud. Leeching is persistent, and typically only need be performed once, though it is possible to request that the ensemble deleech.
 
 Once an ensemble is leeched, it can merge changes from other devices. Merging involves replaying changes from other devices, together with locally recorded changes, in order to update the persistent store. If changes are made concurrently on different devices, there is no guarantee that the data will be valid after replaying the changes. The ensemble provides delegate methods that can be used to make repairs to the data before committing. The changes made in reparation are also captured by the ensemble and transferred to other peers.
 */
@interface CDEPersistentStoreEnsemble : NSObject


///
/// @name Delegate
///

/**
 The ensemble's delegate.
 */
@property (nonatomic, weak, readwrite) id <CDEPersistentStoreEnsembleDelegate> delegate;


///
/// @name Cloud File System
///

/**
 The cloud file system, which is used to transfer files to other devices.
 */
@property (nonatomic, strong, readonly) id <CDECloudFileSystem> cloudFileSystem;


///
/// @name Storage for Ensemble
///

/**
 File URL for the root of a directory used by the ensemble to store transaction logs and other data needed to sync.
 
 The directory is setup when the ensemble leeches, and removed when it deleeches. The data stored includes the transaction logs, binary files, and various metadata files.
 
 The default location is set by the framework to be a folder inside the user's Application Support directory. You can override this by passing a path upon initialization.
 */
@property (nonatomic, strong, readonly) NSURL *localDataRootDirectoryURL;


///
/// @name Ensemble Identity
///

/**
 A global identifier for the ensemble.
 
 The identifier is passed in during initialization. Ensemble objects on different devices with corresponding identifiers will sync their persistent stores.
 */
@property (nonatomic, strong, readonly) NSString *ensembleIdentifier;


///
/// @name Persistent Store and Model
///

/**
 The file URL to the SQLite persistent store that is to be synced.
 */
@property (nonatomic, strong, readonly) NSURL *storeURL;

/**
 The options used whenever the framework adds an `NSPersistentStore` instance referencing the main SQLite store.
 */
@property (nonatomic, strong, readonly) NSDictionary *persistentStoreOptions;

/**
 The file URL of the managed object model file used for the persistent store.
 
 The URL is passed into upon initialization. It gives the location of the compiled model file, which has the extension `momd` or `mom`.
 */
@property (nonatomic, strong, readonly) NSURL *managedObjectModelURL;

/**
 The `NSManagedObjectModel` used for the monitored persistent store.
 */
@property (nonatomic, strong, readonly) NSManagedObjectModel *managedObjectModel;


///
/// @name Active State
///

/**
 Whether the ensemble is leeched, and thus ready to merge.
 
 You should not attempt to merge unless the ensemble is leeched, or attempt to leech an ensemble that is already
 leeched. Either will lead to an error.
 */
@property (atomic, assign, readonly, getter = isLeeched) BOOL leeched;

/**
 Whether the ensemble is currently in the process of merging changes from other devices.
 
 Attempting to merge while another merge is in progress will cause the second merge to be queued
 and executed when the first merge completes.
 */
@property (atomic, assign, readonly, getter = isMerging) BOOL merging;


///
/// @name Initialization
///

/**
 Initializes an ensemble with the default location for local data storage.
 
 Unless you have good reason to set the local data root elsewhere, this is the initializer you should use.
 
 @param identifier The global identifier for the ensemble. This must be the same for all syncing ensemble objects across devices.
 @param storeURL The file URL for the persistent store that is to be synced.
 @param modelURL A file URL for the location of the compiled (momd, mom) model file used in the persistent store.
 @param cloudFileSystem The cloud file system object used to transfer files between devices.
 */
- (instancetype)initWithEnsembleIdentifier:(NSString *)identifier persistentStoreURL:(NSURL *)storeURL managedObjectModelURL:(NSURL *)modelURL cloudFileSystem:(id <CDECloudFileSystem>)cloudFileSystem;

/**
 Initializes an ensemble.
 
 This is the designated initializer.
 
 @param identifier The global identifier for the ensemble. This must be the same for all syncing ensemble objects across devices.
 @param storeURL The file URL to the persistent store that is to be synced.
 @param options Options to use when the framework is adding an `NSPersistentStore` instance for your main persistent store. This could be useful if you need to include SQLite pragmas.
 @param modelURL A file URL for the location of the compiled (momd, mom) model file used in the persistent store.
 @param cloudFileSystem The cloud file system object used to transfer files between devices.
 @param dataRootURL The file URL to the root directory used by the ensemble to store transaction logs and other metadata. Passing nil will cause the default directory to be used.
 */
- (instancetype)initWithEnsembleIdentifier:(NSString *)identifier persistentStoreURL:(NSURL *)storeURL persistentStoreOptions:(NSDictionary *)options managedObjectModelURL:(NSURL *)modelURL cloudFileSystem:(id <CDECloudFileSystem>)cloudFileSystem localDataRootDirectoryURL:(NSURL *)dataRootURL;


///
/// @name Leeching and Deleeching
///

/**
 Attaches the ensemble to corresponding ensemble objects on other devices.
 
 This method sets up local storage and metadata, and registers the persistent store with the cloud, so that ensemble objects on other devices know of its existence.
 
 It also converts the contents of the persistent store into transaction logs, and adds them to the cloud for merging on other devices.
 
 Because this can be a lengthy process, and can involve networking, the method is asynchronous.
 
 If an error occurs during leeching, the ensemble will be left in a deleeched state. You will have to reattempt to leech at a later time.
 
 You should avoid saving to the persistent store during leeching. If a save is detected, the leech will terminate with an error.
 
 @param completion A completion block that is executed when leeching completes, whether successful or not. The block is passed `nil` upon a successful leech, and an `NSError` otherwise.
 */
- (void)leechPersistentStoreWithCompletion:(CDECompletionBlock)completion;

/**
 Detaches the ensemble from peers, effectively terminating syncing.
 
 The local data of the ensemble is deleted.
 
 Because this can be a lengthy process, the method is asynchronous.
 
 @param completion A completion block that is executed when deleeching completes. The block is passed nil upon success, and an `NSError` otherwise.
 */
- (void)deleechPersistentStoreWithCompletion:(CDECompletionBlock)completion;


///
/// @name Merging
///

/**
 Begins merging data from other peers into the persistent store.
 
 Merging involves retrieving new files from the cloud, importing them into the local data set, and applying the changes to the persistent store. This can take some time, so the method is asynchronous.
 
 A merge can fail for a variety of reasons, from file downloads being incomplete, to the merge being interrupted by a save to the persistent store. Errors during merging are not typically very serious, and you should just retry the merge a bit later. Error codes can be found in CDEDefines.
 
 @param completion A block that is executed upon completion of merging, whether successful or not. The block is passed nil upon a successful merge, and an `NSError` otherwise.
 */
- (void)mergeWithCompletion:(CDECompletionBlock)completion;

/**
 Cancels a merge, if one is active.
 
 @param completion A block that is executed upon completion. The block is passed nil if the cancellation is successful, and an `NSError` otherwise.
 */
- (void)cancelMergeWithCompletion:(CDECompletionBlock)completion;


///
/// @name Ensemble Discovery and Management
///

/**
 Queries a cloud file system for the identifiers of the ensembles it contains.
 
 Use this method to discover dynamically generated ensembles, such as in document-based apps. 
 
 Note that this is quite a primitive register for documents. You may be better to maintain a custom registry of document metadata (eg plists) in a cloud directory. You can still use the cloud file system instance to upload and download the metadata files.
 
 @param cloudFileSystem The cloud file system object used to transfer files between devices.
 @param completion The completion block called with the results. The error parameter is nil on success.
 */
+ (void)retrieveEnsembleIdentifiersFromCloudFileSystem:(id <CDECloudFileSystem>)cloudFileSystem completion:(void(^)(NSError *error, NSArray *identifiers))completion;

/**
 Completely removes the cloud data of an ensemble,
 
 You should use this method sparingly, only if you are sure that your devices are no longer using the ensemble. 
 
 The removal can also take some time to propagate depending on the cloud file system used. With iCloud, for example, it can be many minutes before other devices remove the data. For this reason, it is not a good idea to delete the data, and then immediately recreate the ensemble. In cases like that, it is reasonably likely that a device will see a mix of new and old data, and enter an invalid state.
 
 @param identifier The identifier of the ensemble for removal.
 @param cloudFileSystem The cloud file system storing the data.
 @param completion The completion block called when the data has been removed. Success is indicated by the error being nil.
 */
+ (void)removeEnsembleWithIdentifier:(NSString *)identifier inCloudFileSystem:(id <CDECloudFileSystem>)cloudFileSystem completion:(void(^)(NSError *error))completion;


///
/// @name Waiting for Task Completion
///

/**
 Flushes any queued operations, and ensures all data is saved to disk.
 
 You can use this method if you want to be sure ensembles has completed any backed-up tasks.
 
 @param block A block that is executed upon completion. The block is passed nil upon success, and an `NSError` otherwise.
 */
- (void)processPendingChangesWithCompletion:(CDECompletionBlock)block;


///
/// @name Dismantling an Ensemble
///

/**
 Force the ensemble to dismantle. Normally this happens when it deallocs, but sometimes you may want to force it to happen early,
 such as when you want to create a new ensemble that replaces an existing ensemble. In order to prevent the two ensembles accessing the same
 data at the same time, you can tell one to dismantle, after which it will no longer use or access the disk, or monitor saves.
 */
- (void)dismantle;

@end

@interface CDEPersistentStoreEnsemble (Internal)

- (NSArray *)globalIdentifiersForManagedObjects:(NSArray *)objects;

@end
