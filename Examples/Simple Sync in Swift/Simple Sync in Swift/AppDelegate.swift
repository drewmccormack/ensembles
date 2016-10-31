//
//  AppDelegate.swift
//  Simple Sync in Swift
//
//  Created by Drew McCormack on 31/01/16.
//  Copyright © 2016 Drew McCormack. All rights reserved.
//

import UIKit
import CoreData
import Ensembles

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, CDEPersistentStoreEnsembleDelegate {

    var window: UIWindow?
    
    
    // MARK: App Delegate Methods
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
        // Use verbose logging for sync
        CDESetCurrentLoggingLevel(CDELoggingLevel.verbose.rawValue)
        
        // Setup Core Data Stack
        self.setupCoreData()
        
        // Create holder object if necessary. Ensure it is fully saved before we leech.
        _ = NumberHolder.numberHolderInContext(managedObjectContext)
        try! managedObjectContext.save()
        
        // Setup Ensemble
        let modelURL = Bundle.main.url(forResource: "Model", withExtension: "momd")
        cloudFileSystem = CDEICloudFileSystem(ubiquityContainerIdentifier: nil)
        ensemble = CDEPersistentStoreEnsemble(ensembleIdentifier: "NumberStore", persistentStore: storeURL, managedObjectModelURL: modelURL!, cloudFileSystem: cloudFileSystem)
        ensemble.delegate = self
        
        // Listen for local saves, and trigger merges
        NotificationCenter.default.addObserver(self, selector:#selector(AppDelegate.localSaveOccurred(_:)), name:NSNotification.Name.CDEMonitoredManagedObjectContextDidSave, object:nil)
        NotificationCenter.default.addObserver(self, selector:#selector(AppDelegate.cloudDataDidDownload(_:)), name:NSNotification.Name.CDEICloudFileSystemDidDownloadFiles, object:nil)
        
        // Pass context to controller
        let controller = self.window?.rootViewController as! ViewController
        controller.managedObjectContext = managedObjectContext
        
        // Sync
        self.sync(nil)
        
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        let taskIdentifier = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
        try! managedObjectContext.save()
        self.sync {
            UIApplication.shared.endBackgroundTask(taskIdentifier)
        }
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        self.sync(nil)
    }
    
    
    // MARK: Notification Handlers
    
    func localSaveOccurred(_ notif: Notification) {
        self.sync(nil)
    }
    
    func cloudDataDidDownload(_ notif: Notification) {
        self.sync(nil)
    }
    
    
    // MARK: Core Data Stack
    
    var managedObjectContext: NSManagedObjectContext!

    var storeDirectoryURL: URL {
        return try! FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    }
    
    var storeURL: URL {
        return self.storeDirectoryURL.appendingPathComponent("store.sqlite")
    }
    
    func setupCoreData() {
        let modelURL = Bundle.main.url(forResource: "Model", withExtension: "momd")
        let model = NSManagedObjectModel(contentsOf: modelURL!)
        
        try! FileManager.default.createDirectory(at: self.storeDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model!)
        let options = [NSMigratePersistentStoresAutomaticallyOption: true, NSInferMappingModelAutomaticallyOption: true]
        try! coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: self.storeURL, options: options)
        
        managedObjectContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        managedObjectContext.persistentStoreCoordinator = coordinator
        managedObjectContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    
    // MARK: Ensembles
    
    var cloudFileSystem: CDECloudFileSystem!
    var ensemble: CDEPersistentStoreEnsemble!
    
    func sync(_ completion: ((Void) -> Void)?) {
        let viewController = self.window?.rootViewController as! ViewController
        viewController.activityIndicator?.startAnimating()
        if !ensemble.isLeeched {
            ensemble.leechPersistentStore {
                error in
                viewController.activityIndicator?.stopAnimating()
                viewController.refresh()
                completion?()
            }
        }
        else {
            ensemble.merge {
                error in
                viewController.activityIndicator?.stopAnimating()
                viewController.refresh()
                completion?()
            }
        }
    }
    
    func persistentStoreEnsemble(_ ensemble: CDEPersistentStoreEnsemble, didSaveMergeChangesWith notification: Notification) {
        managedObjectContext.performAndWait {
            self.managedObjectContext.mergeChanges(fromContextDidSave: notification)
        }
    }
    
    func persistentStoreEnsemble(_ ensemble: CDEPersistentStoreEnsemble!, globalIdentifiersForManagedObjects objects: [Any]!) -> [Any]! {
        let numberHolders = objects as! [NumberHolder]
        return numberHolders.map { $0.uniqueIdentifier }
    }

}

