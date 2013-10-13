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

@property (nonatomic) NSString *uniqueIdentifier;
@property (nonatomic) CDEStoreModificationEventType type;
@property (nonatomic, retain) CDEEventRevision *eventRevision;
@property (nonatomic, retain) NSSet *eventRevisionsOfOtherStores;
@property (nonatomic) CDEGlobalCount globalCount;
@property (nonatomic) NSTimeInterval timestamp;
@property (nonatomic, retain) NSString *modelVersion;
@property (nonatomic, retain) NSSet *objectChanges;

@property (nonatomic, copy) CDERevisionSet *revisionSetOfOtherStoresAtCreation;
@property (nonatomic, readonly) CDERevisionSet *revisionSet;

+ (instancetype)fetchStoreModificationEventForPersistentStoreIdentifier:(NSString *)persistentStoreId revisionNumber:(CDERevisionNumber)revision inManagedObjectContext:(NSManagedObjectContext *)context;
+ (NSArray *)fetchStoreModificationEventsForPersistentStoreIdentifier:(NSString *)persistentStoreId sinceRevisionNumber:(CDERevisionNumber)revision inManagedObjectContext:(NSManagedObjectContext *)context;

+ (void)prefetchRelatedObjectsForStoreModificationEvents:(NSArray *)storeModEvents;

@end
