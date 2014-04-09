//
//  CDEEventMigrator.h
//  Test App iOS
//
//  Migrates events in and out of the event store.
//
//  Created by Drew McCormack on 5/10/13.
//  Copyright (c) 2013 The Mental Faculty B.V. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CDEDefines.h"

@class CDEEventStore;
@class CDEPersistentStoreEnsemble;

@interface CDEEventMigrator : NSObject

@property (nonatomic, strong, readonly) CDEEventStore *eventStore;
@property (nonatomic, strong, readwrite) NSString *storeTypeForNewFiles;
@property (nonatomic, weak, readwrite) CDEPersistentStoreEnsemble *ensemble;

- (instancetype)initWithEventStore:(CDEEventStore *)newStore;

- (void)migrateLocalEventWithRevision:(CDERevisionNumber)revision toFile:(NSString *)path allowedTypes:(NSArray *)types completion:(CDECompletionBlock)completion;
- (void)migrateLocalBaselineWithUniqueIdentifier:(NSString *)uniqueId globalCount:(CDEGlobalCount)count persistentStorePrefix:(NSString *)storePrefix toFile:(NSString *)path completion:(CDECompletionBlock)completion;
- (void)migrateNonBaselineEventsSinceRevision:(CDERevisionNumber)revision toFile:(NSString *)path completion:(CDECompletionBlock)completion;
- (void)migrateEventsInFromFiles:(NSArray *)paths completion:(CDECompletionBlock)completion;

@end
