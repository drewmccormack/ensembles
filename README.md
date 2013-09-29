Core Data Ensembles
===

_Author:_ Drew McCormack
_Date:_ 29th September, 2013

Ensembles extends Apple's Core Data framework to add peer-to-peer synchronization for Mac OS and iOS. Multiple SQLite persistent stores can be coupled together via a file synchronization platform like iCloud or Dropbox. The framework can be readily extended to support any service capable of moving files between devices, including custom servers.

#### Idiomatic  App

Idiomatic is a relatively simple example app that incorporates Ensembles and works with iCloud to sync across devices. The app allows you to record your ideas, and add tags to group them. The Core Data model of the app includes two entities, with a many-to-many relationship.

The Idiomatic project is a good way to get acquainted with Ensembles, and how it is integrated in a Core Data app. Idiomatic can be run in the iPhone Simulator, or on a device, but in order to test it, you need to follow a few preparatory steps.

1. Register an App ID for Idiomatic (_eg_ com.yourcompany.idiomatic) in the Certificates, Identifiers & Profiles section of the iOS Developer Center, and make sure the iCloud service is enabled.
2. Select the Idiomatic Project in the source list of the Xcode project, and then select the Idiomatic target.
3. In the General section, set the bundle identifier (_eg_ com.yourcompany.idiomatic).
4. Select the _Capabilities_ section, turn on the iCloud switch, and replace the existing Ubiquity Container with your own.
5. In the IDMAppDelegate class, locate this code in application:didFinishLaunchingWithOptions:

	// Setup Ensemble
	cloudFileSystem = [[CDEICloudFileSystem alloc] initWithUbiquityContainerIdentifier:@"P7BXV6PHLD.com.mentalfaculty.idiomatic"];

6. Fill in the Ubiquity Container Identifier appropriate for your bundle identifier and team identifier. You can find this on the iOS Developer Center under the App ID you registered. Just combine the _Prefix_ entry with the _ID_.
7. Build and install on devices and simulators that are logged into the same iCloud account.
8. Add notes, and tag them as desired. The app will sync when it becomes active, but you can force a sync by tapping the button under the Groups table.

#### Getting to Know Ensembles

The most important class in the Ensembles framework is `CDEPersistentStoreEnsemble`. You create one instance of this class for each `NSPersistentStore` that you want to sync. This class monitors saves to your SQLite store, and merges in changes from other devices as they arrive.

You typically initialize a `CDEPersistentStoreEnsemble` around the same point in your code that your Core Data stack is initialized. It is important that the ensemble is initialized before data is saved.

There is one other family of classes that you need to be familiar with. These are classes that conform to the `CDECloudFileSystem` protocol. Any class conforming to this protocol can serve as the file syncing backend of an ensemble, allowing data to be transferred between devices. You can use one of the existing classes (_eg_ `CDEICloudFileSystem`), or develop your own.

The initialization of an ensemble is typically only a few lines long.

	// Setup Ensemble
	cloudFileSystem = [[CDEICloudFileSystem alloc] 
		initWithUbiquityContainerIdentifier:@"P7BXV6PHLD.com.mentalfaculty.idiomatic"];
	ensemble = [[CDEPersistentStoreEnsemble alloc] initWithEnsembleIdentifier:@"MainStore" 
		persistentStorePath:storeURL.path 
		managedObjectModel:model 
		cloudFileSystem:cloudFileSystem];
	ensemble.delegate = self;

After the cloud file system is initialized, it is passed to the `CDEPersistentStoreEnsemble` initializer, together with the `NSManagedObjectModel` and path to the `NSPersistentStore`. An ensemble identifier is used to match stores across devices. It is important that this be the same for each store in the ensemble.

Once a `CDEPersistentStoreEnsemble` has been initialized, it can be _leeched_. This step typically only needs to take place once, to setup the ensemble and perform an initial import of data in the local persistent store. Once an ensemble has been leeched, it remains leeched even after a relaunch. The ensemble only gets _deleeched_ if you explicitly request it, or if a serious problem arises in the cloud file system, such as an account switch.

You can query an ensemble for whether it is already leeched using the `isLeeched` property, and initiate the leeching process with `leechPersistentStoreWithCompletion:`. (Attempting to leech an ensemble that is already leeched will cause an error.)

	if (!ensemble.isLeeched) {
	    [ensemble leechPersistentStoreWithCompletion:^(NSError *error) {
	        if (error) NSLog(@"Could not leech to ensemble: %@", error);
	    }];
	}

Because many tasks in Ensembles can involve networking or long operations, most methods are asynchronous and include a block callback which is called on completion of the task with an error parameter. If the error is `nil`, the task completed successfully. Methods should only be initiated on the main thread, and completion callbacks are sent to the main queue.

With the ensemble leeched, sync operations can be initiated using the `mergeWithCompletion:` method.

	[ensemble mergeWithCompletion:^(NSError *error) {
	    if (error) NSLog(@"Error merging: %@", error);
	}];	

A merge involves retrieving new changes for other devices from the cloud file system, integrating them in a background `NSManagedObjectContext`, merging with new local changes, and saving the result to the `NSPersistentStore`.

When a merge occurs, it is important to merge the changes into your main `NSManagedObjectContext`. You can do this in the `persistentStoreEnsemble:didSaveMergeChangesWithNotification:` delegate method. 

	- (void)persistentStoreEnsemble:(CDEPersistentStoreEnsemble *)ensemble didSaveMergeChangesWithNotification:(NSNotification *)notification
	{
	    [managedObjectContext performBlock:^{
	        [managedObjectContext mergeChangesFromContextDidSaveNotification:notification];
	    }];
	}

Note that this is invoked on the thread of the background context used for merging the changes. You need to make sure the `mergeChangesFromContextDidSaveNotification:` method is invoked on the thread corresponding to the main context.

There is one other delegate method that you will probably want to implement, in order to provide global identifiers for managed objects. 

	- (NSArray *)persistentStoreEnsemble:(CDEPersistentStoreEnsemble *)ensemble 
		globalIdentifiersForManagedObjects:(NSArray *)objects
	{
	    return [objects valueForKeyPath:@"uniqueIdentifier"];
	} 

This method is also invoked on a background thread. Care should be taken to only access the objects passed on this thread.

It is not compulsory to provide global identifiers, but if you do, the framework will automatically ensure that no objects get duplicated due to multiple imports on different devices. If you don't provide global identifiers, the framework has no way to identify a new object, and will assign it a new unique identifier.

If you do decide to provide global identifiers, it is up to you how you generate them, and where you store them. A common choice is to add an extra attribute to entities in your data model, and set that to a uuid on insertion into the store.

#### Unit Tests

Unit tests are included for the Ensembles framework on the Mac. To run the tests, open the Xcode project for the Mac platform, choose the Ensembles Mac target in the toolbar at the top, and select the menu item `Product > Test`.

