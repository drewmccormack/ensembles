//
//  CDERevisionSet.h
//  Ensembles
//
//  Created by Drew McCormack on 24/07/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@class CDERevision;

@interface CDERevisionSet : NSObject 

@property (nonatomic, assign, readonly) NSUInteger numberOfRevisions;
@property (nonatomic, strong, readonly) NSSet *revisions;
@property (nonatomic, strong, readonly) NSSet *persistentStoreIdentifiers;

- (CDERevision *)revisionForPersistentStoreIdentifier:(NSString *)identifier;

- (BOOL)hasRevisionForPersistentStoreIdentifier:(NSString *)identifier;

- (void)addRevision:(CDERevision *)newRevision;
- (void)removeRevision:(CDERevision *)revision;
- (void)removeRevisionForPersistentStoreIdentifier:(NSString *)identifier;

- (void)incrementRevisionForStoreWithIdentifier:(NSString *)persistentStoreIdentifier;

- (CDERevisionSet *)revisionSetByTakingStoreWiseMinimumWithRevisionSet:(CDERevisionSet *)otherSet;
- (CDERevisionSet *)revisionSetByTakingStoreWiseMaximumWithRevisionSet:(CDERevisionSet *)otherSet;
+ (CDERevisionSet *)revisionSetByTakingStoreWiseMaximumOfRevisionSets:(NSArray *)sets;

- (NSComparisonResult)compare:(CDERevisionSet *)otherSet;
- (BOOL)isEqualToRevisionSet:(CDERevisionSet *)otherSet;

@end
