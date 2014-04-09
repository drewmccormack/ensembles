//
//  CDEEventFile.h
//  Ensembles Mac
//
//  Created by Drew McCormack on 08/04/14.
//  Copyright (c) 2014 Drew McCormack. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#import "CDEEventRevision.h"

@class CDEStoreModificationEvent;

@interface CDEEventFile : NSObject

@property (nonatomic, readonly) NSString *preferredFilename;
@property (nonatomic, readonly) NSSet *aliases;
@property (nonatomic, readonly) NSPredicate *eventFetchPredicate;
@property (nonatomic, readonly, getter = isBaseline) BOOL baseline;
@property (nonatomic, readonly) NSString *uniqueIdentifier;
@property (nonatomic, readonly) NSString *persistentStoreIdentifier;
@property (nonatomic, readonly) NSString *persistentStorePrefix;
@property (nonatomic, readonly) BOOL eventShouldBeUnique;
@property (nonatomic, readonly) CDERevisionNumber revisionNumber;
@property (nonatomic, readonly) CDEGlobalCount globalCount;

- (id)initWithStoreModificationEvent:(CDEStoreModificationEvent *)event;
- (id)initWithFilename:(NSString *)filename;

@end
