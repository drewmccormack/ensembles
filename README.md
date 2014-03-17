Core Data Ensembles
===

_Author:_ Drew McCormack<br>
_Created:_ 29th September, 2013<br>
_Last Updated:_ 10th March, 2014

*You can kickstart integration of Ensembles in your app &mdash; and support the open source project &mdash; by purchasing a support and documentation package at [ensembles.io](http://ensembles.io/).*

Ensembles extends Apple's Core Data framework to add peer-to-peer synchronization for Mac OS and iOS. Multiple SQLite persistent stores can be coupled together via a file synchronization platform like iCloud or Dropbox. The framework can be readily extended to support any service capable of moving files between devices, including custom servers.

#### Downloading Ensembles

To clone Ensembles to your local drive, use the command

	git clone https://github.com/drewmccormack/ensembles.git

Ensembles makes use of Git submodules. To retrieve these, change to the `ensembles` root directory
	
	cd ensembles
	
and issue this command

	git submodule update --init

#### Incorporating Ensembles in an iOS Project

To add Ensembles to your App's Xcode Project with CocoaPods...

1. Add the following to your Podfile 

		platform :ios, '7.0'
		pod "Ensembles", "~> 0.4.0"

To manually add Ensembles to your App's Xcode Project...

1. Drag the `Ensembles iOS.xcodeproj` project from the `Framework` directory into your Xcode project.
2. Select the App's project root, and the App target.
3. In the General tab, click the + button in the _Linked Frameworks and Libraries_ section.
4. Choose the `libensembles_ios.a` library and add it.
5. Select the Build Settings tab. Locate the Header Search Paths setting. 
6. Add a path to the Ensembles directory `Framework`, and make the search path _recursive_. (You may want to form the path relative to your Xcode project, eg, `$(SRCROOT)/../ensembles/Framework`).
7. Locate the Other Linker Flags setting, and add the flag `-ObjC`.
8. Drag the `Framework/Resources` directory from the Ensembles project into your App project. Make sure the _Create groups for any added Folders_ option is selected.

#### Including Optional Cloud Services

By default, Ensembles only includes support for iCloud. To use other cloud services, such as Dropbox, you may need to add a few steps to the procedure above. 

If you are using Cocoapods, you should not need to do anything. The optional cloud services are included in the default install. 

If you don't want to include the optional services in your project, you can replace the standard pod command in your Podfile with the following

		pod "Ensembles/Core", "~> 0.4.0"

If you are installing Ensembles manually, rather than with Cocoapods, you need to locate the source files and frameworks relevant to the service you want to support. You can find frameworks in the `Vendor` folder, and source files in `Framework/Extensions`.

By way of example, if you want to support Dropbox, you need to add the DropboxSDK Xcode project as a dependency, link to the appropriate product library, and include the files `CDEDropboxCloudFileSystem.h` and `CDEDropboxCloudFileSystem.m` in your project.

#### Idiomatic  App

Idiomatic is a relatively simple example app which incorporates Ensembles and works with iCloud or Dropbox to sync across devices. The app allows you to record your ideas, and add tags to group them. The Core Data model of the app includes two entities, with a many-to-many relationship.

The Idiomatic project is a good way to get acquainted with Ensembles, and how it is integrated in a Core Data app. Idiomatic can be run in the iPhone Simulator, or on a device, but in order to test it, you need to follow a few preparatory steps.

1. Register an App ID for Idiomatic (eg com.yourcompany.idiomatic) in the Certificates, Identifiers & Profiles section of the iOS Developer Center, and make sure the iCloud service is enabled.
2. Select the Idiomatic Project in the source list of the Xcode project, and then select the Idiomatic target.
3. In the General section, set the bundle identifier (eg com.yourcompany.idiomatic).
4. Select the _Capabilities_ section, turn on the iCloud switch, and replace the existing Ubiquity Container with your own.
5. At the top of the `IDMAppDelegate` class, locate this code

		NSString * const IDMICloudContainerIdentifier = @"P7BXV6PHLD.com.mentalfaculty.idiomatic";
		
6. Fill in the Ubiquity Container Identifier appropriate for your bundle identifier and team identifier. You can find this on the iOS Developer Center under the App ID you registered. Just combine the _Prefix_ entry with the _ID_.
7. Build and install on devices and simulators that are logged into the same iCloud account.
8. Add notes, and tag them as desired. The app will sync when it becomes active, but you can force a sync by tapping the button under the Groups table.

Dropbox sync should work via The Mental Faculty account, but if you want to use your own developer account, you need to do the following:

1. Sign up for a Dropbox developer account at developer.dropbox.com
2. In the App Console, click the Create app button.
3. Choose the Dropbox API app type.
4. Choose to store 'Files and Datastores'
5. Choose 'Yes &mdash; My app only needs access to files it creates'
6. Name the app (eg Idiomatic)
7. Click on Create app 
8. At the top of the `IDMAppDelegate` class, locate this code, and replace the values with the strings you just created on the Dropbox site.

		NSString * const IDMDropboxAppKey = @"xxxxxxxxxxxxxxx";
		NSString * const IDMDropboxAppSecret = @"xxxxxxxxxxxxxxx";
	
9. Select the Idiomatic project in Xcode, and then the Idiomatic iOS target.
10. Select the Info tab.
11. Open the URL Types section, and change the URL Schemes entry to 

		db-<Your Dropbox App Key>

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
		managedObjectModelURL:modelURL
		cloudFileSystem:cloudFileSystem];
	ensemble.delegate = self;

After the cloud file system is initialized, it is passed to the `CDEPersistentStoreEnsemble` initializer, together with the URL of a file containing the `NSManagedObjectModel`, and the path to the `NSPersistentStore`. An ensemble identifier is used to match stores across devices. It is important that this be the same for each store in the ensemble.

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

Unit tests are included for the Ensembles framework on each platform. To run the tests, open the Xcode workspace, choose the Ensembles Mac or Ensembles iOS target in the toolbar at the top, and select the menu item `Product > Test`.

