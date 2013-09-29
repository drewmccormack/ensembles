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

typedef void (^CDEEventIntegratorWillSaveBlock)(NSManagedObjectContext *context, NSDictionary *info);
typedef BOOL (^CDEEventIntegratorFailedSaveBlock)(NSManagedObjectContext *context, NSError *error);
typedef void (^CDEEventIntegratorDidSaveBlock)(NSManagedObjectContext *context, NSDictionary *info);

@interface CDEEventIntegrator : NSObject

@property (nonatomic, readonly) NSURL *storeURL;
@property (nonatomic, readonly) NSManagedObjectModel *managedObjectModel;
@property (nonatomic, readonly) CDEEventStore *eventStore;
@property (nonatomic, readwrite, weak) CDEPersistentStoreEnsemble *ensemble;
@property (nonatomic, copy) CDEEventIntegratorWillSaveBlock willSaveBlock;
@property (nonatomic, copy) CDEEventIntegratorFailedSaveBlock failedSaveBlock;
@property (nonatomic, copy) CDEEventIntegratorDidSaveBlock didSaveBlock;

@property (readonly) NSManagedObjectContext *managedObjectContext;

- (instancetype)initWithStoreURL:(NSURL *)newStoreURL managedObjectModel:(NSManagedObjectModel *)model eventStore:(CDEEventStore *)newEventStore;

- (void)mergeEventsImportedSinceRevision:(CDERevisionNumber)revisionNumber completion:(CDECompletionBlock)completion;

@end

