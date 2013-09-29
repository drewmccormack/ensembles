//
//  CDEManagedObjectContextSaveMonitor.h
//  Test App iOS
//
//  Created by Drew McCormack on 4/16/13.
//  Copyright (c) 2013 The Mental Faculty B.V. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@class CDEEventStore;
@class CDEEventIntegrator;
@class CDEPersistentStoreEnsemble;

@interface CDESaveMonitor : NSObject

@property (strong) CDEEventStore *eventStore;
@property (strong) NSString *storePath;
@property (weak) CDEEventIntegrator *eventIntegrator;
@property (nonatomic, readwrite, weak) CDEPersistentStoreEnsemble *ensemble;

- (id)initWithStorePath:(NSString *)storePath;

- (NSPersistentStore *)monitoredPersistentStoreInManagedObjectContext:(NSManagedObjectContext *)context;
- (NSSet *)monitoredManagedObjectsInSet:(NSSet *)objectsSet;

- (void)stopMonitoring;

@end
