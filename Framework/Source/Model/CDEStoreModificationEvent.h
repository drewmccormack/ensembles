//
//  CDEStoreModificationEvent.h
//  Test App iOS
//
//  Created by Drew McCormack on 4/14/13.
//  Copyright (c) 2013 The Mental Faculty B.V. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#import "CDEDefines.h"

@class CDEEventRevision;
@class CDERevisionSet;

typedef NS_ENUM(int16_t, CDEStoreModificationEventType) {
    CDEStoreModificationEventTypeBaseline   = 100,
    CDEStoreModificationEventTypeSave       = 200,
    CDEStoreModificationEventTypeMerge      = 300
};


@interface CDEStoreModificationEvent : NSManagedObject

@property (nonatomic, strong, readwrite) NSString *uniqueIdentifier;
@property (nonatomic, assign, readwrite) CDEStoreModificationEventType type;
@property (nonatomic, strong, readwrite) CDEEventRevision *eventRevision;
@property (nonatomic, strong, readwrite) NSSet *eventRevisionsOfOtherStores;
@property (nonatomic, assign, readwrite) CDEGlobalCount globalCount;
@property (nonatomic, assign, readwrite) NSTimeInterval timestamp;
@property (nonatomic, strong, readwrite) NSString *modelVersion;
@property (nonatomic, strong, readwrite) NSSet *objectChanges;

@property (nonatomic, copy, readwrite) CDERevisionSet *revisionSetOfOtherStoresAtCreation;
@property (nonatomic, strong, readonly) CDERevisionSet *revisionSet;

// Fetching particular events
+ (instancetype)fetchStoreModificationEventWithUniqueIdentifier:(NSString *)uniqueId inManagedObjectContext:(NSManagedObjectContext *)context;
+ (instancetype)fetchStoreModificationEventForPersistentStoreIdentifier:(NSString *)persistentStoreId revisionNumber:(CDERevisionNumber)revision inManagedObjectContext:(NSManagedObjectContext *)context;

// Fetching non-baseline events
+ (NSArray *)fetchStoreModificationEventsForPersistentStoreIdentifier:(NSString *)persistentStoreId sinceRevisionNumber:(CDERevisionNumber)revision inManagedObjectContext:(NSManagedObjectContext *)context;
+ (NSArray *)fetchStoreModificationEventsUpToGlobalCount:(CDEGlobalCount)globalCount inManagedObjectContext:(NSManagedObjectContext *)context;

// Fetching baseline events
+ (instancetype)fetchBaselineStoreModificationEventInManagedObjectContext:(NSManagedObjectContext *)context;

// Prefetching
+ (void)prefetchRelatedObjectsForStoreModificationEvents:(NSArray *)storeModEvents;

@end
