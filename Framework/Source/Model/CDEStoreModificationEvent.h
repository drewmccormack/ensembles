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
    CDEStoreModificationEventTypeIncomplete = 0,
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

// Working with revisions
- (void)setRevisionSet:(CDERevisionSet *)newSet forPersistentStoreIdentifier:(NSString *)persistentStoreId;
- (void)deleteEventRevisions;

// Fetching types of events. Pass nil for either argument to allow all.
+ (NSArray *)fetchStoreModificationEventsWithTypes:(NSArray *)types persistentStoreIdentifier:(NSString *)persistentStoreIdentifier inManagedObjectContext:(NSManagedObjectContext *)context;

// Fetching particular events
+ (instancetype)fetchStoreModificationEventWithUniqueIdentifier:(NSString *)uniqueId globalCount:(CDEGlobalCount)count persistentStorePrefix:(NSString *)storePrefix inManagedObjectContext:(NSManagedObjectContext *)context;
+ (instancetype)fetchStoreModificationEventWithUniqueIdentifier:(NSString *)uniqueId inManagedObjectContext:(NSManagedObjectContext *)context;
+ (instancetype)fetchStoreModificationEventWithAllowedTypes:(NSArray *)types persistentStoreIdentifier:(NSString *)storeId revisionNumber:(CDERevisionNumber)revision inManagedObjectContext:(NSManagedObjectContext *)context;
+ (instancetype)fetchNonBaselineEventForPersistentStoreIdentifier:(NSString *)persistentStoreId revisionNumber:(CDERevisionNumber)revision inManagedObjectContext:(NSManagedObjectContext *)context; // Non-baseline events

// Fetching non-baseline events
+ (NSArray *)fetchNonBaselineEventsForPersistentStoreIdentifier:(NSString *)persistentStoreId sinceRevisionNumber:(CDERevisionNumber)revision inManagedObjectContext:(NSManagedObjectContext *)context;
+ (NSArray *)fetchNonBaselineEventsUpToGlobalCount:(CDEGlobalCount)globalCount inManagedObjectContext:(NSManagedObjectContext *)context;
+ (NSArray *)fetchNonBaselineEventsInManagedObjectContext:(NSManagedObjectContext *)context;

// Fetching baseline events
+ (instancetype)fetchMostRecentBaselineStoreModificationEventInManagedObjectContext:(NSManagedObjectContext *)context;

// Predicates
+ (NSPredicate *)predicateForAllowedTypes:(NSArray *)types persistentStoreIdentifier:(NSString *)persistentStoreIdentifier;

// Prefetching
+ (void)prefetchRelatedObjectsForStoreModificationEvents:(NSArray *)storeModEvents;

@end
