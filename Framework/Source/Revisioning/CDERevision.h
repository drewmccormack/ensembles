//
//  CDERevision.h
//  Ensembles
//
//  Created by Drew McCormack on 10/08/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CDEDefines.h"

@interface CDERevision : NSObject

@property (nonatomic, assign, readwrite) CDERevisionNumber revisionNumber;
@property (nonatomic, assign, readwrite) CDEGlobalCount globalCount;
@property (nonatomic, copy, readwrite) NSString *persistentStoreIdentifier;
@property (nonatomic, copy, readonly) id <NSObject, NSCopying> uniqueIdentifier;

- (instancetype)initWithPersistentStoreIdentifier:(NSString *)identifier revisionNumber:(CDERevisionNumber)number globalCount:(CDEGlobalCount)globalCount;
- (instancetype)initWithPersistentStoreIdentifier:(NSString *)identifier revisionNumber:(CDERevisionNumber)number;

- (NSComparisonResult)compare:(CDERevision *)other;

@end
