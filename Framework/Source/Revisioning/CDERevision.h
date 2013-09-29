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

@property (nonatomic) CDERevisionNumber revisionNumber;
@property (nonatomic) CDEGlobalCount globalCount;
@property (nonatomic, copy) NSString *persistentStoreIdentifier;
@property (nonatomic, readonly) id <NSObject, NSCopying> uniqueIdentifier;

- (instancetype)initWithPersistentStoreIdentifier:(NSString *)identifier revisionNumber:(CDERevisionNumber)number globalCount:(CDEGlobalCount)globalCount;
- (instancetype)initWithPersistentStoreIdentifier:(NSString *)identifier revisionNumber:(CDERevisionNumber)number;

- (NSComparisonResult)compare:(CDERevision *)other;

@end
