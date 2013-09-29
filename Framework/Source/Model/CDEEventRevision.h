//
//  CDERevision.h
//  Ensembles
//
//  Created by Drew McCormack on 09/07/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#import "CDEDefines.h"

@class CDEStoreModificationEvent;
@class CDERevision;
@class CDERevisionSet;

@interface CDEEventRevision : NSManagedObject

@property (nonatomic) CDERevisionNumber revisionNumber;
@property (nonatomic, retain) NSString *persistentStoreIdentifier;
@property (nonatomic, retain) CDEStoreModificationEvent *storeModificationEvent;
@property (nonatomic, retain) CDEStoreModificationEvent *storeModificationEventForOtherStores;
@property (nonatomic, readonly) CDERevision *revision;

+ (instancetype)makeEventRevisionForPersistentStoreIdentifier:(NSString *)identifier revisionNumber:(CDERevisionNumber)revision inManagedObjectContext:(NSManagedObjectContext *)context;
+ (NSSet *)fetchPersistentStoreIdentifiersInManagedObjectContext:(NSManagedObjectContext *)context;

+ (NSSet *)makeEventRevisionsForRevisionSet:(CDERevisionSet *)set inManagedObjectContext:(NSManagedObjectContext *)context;

@end
