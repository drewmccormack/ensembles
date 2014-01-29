//
//  CDEEventIntegrator.h
//  Test App iOS
//
//  Created by Drew McCormack on 4/23/13.
//  Copyright (c) 2013 The Mental Faculty B.V. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#import "CDEDefines.h"

@class CDEEventStore;
@class CDEPersistentStoreEnsemble;

typedef void (^CDEEventIntegratorWillSaveBlock)(NSManagedObjectContext *savingContext, NSManagedObjectContext *reparationContext);
typedef BOOL (^CDEEventIntegratorFailedSaveBlock)(NSManagedObjectContext *savingContext, NSError *error, NSManagedObjectContext *reparationContext);
typedef void (^CDEEventIntegratorDidSaveBlock)(NSManagedObjectContext *savingContext, NSDictionary *info);

@interface CDEEventIntegrator : NSObject

@property (nonatomic, strong, readonly) NSURL *storeURL;
@property (nonatomic, strong, readonly) NSManagedObjectModel *managedObjectModel;
@property (nonatomic, strong, readonly) CDEEventStore *eventStore;
@property (nonatomic, weak, readwrite) CDEPersistentStoreEnsemble *ensemble;
@property (nonatomic, copy, readwrite) CDEEventIntegratorWillSaveBlock willSaveBlock;
@property (nonatomic, copy, readwrite) CDEEventIntegratorFailedSaveBlock failedSaveBlock;
@property (nonatomic, copy, readwrite) CDEEventIntegratorDidSaveBlock didSaveBlock;

@property (readonly) NSManagedObjectContext *managedObjectContext;

- (instancetype)initWithStoreURL:(NSURL *)newStoreURL managedObjectModel:(NSManagedObjectModel *)model eventStore:(CDEEventStore *)newEventStore;

- (void)startMonitoringSaves;
- (void)stopMonitoringSaves;

- (void)mergeEventsImportedSinceRevision:(CDERevisionNumber)revisionNumber completion:(CDECompletionBlock)completion;

@end

