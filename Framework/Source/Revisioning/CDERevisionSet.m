//
//  CDERevisionSet.m
//  Ensembles
//
//  Created by Drew McCormack on 24/07/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import "CDERevisionSet.h"
#import "CDERevision.h"

@implementation CDERevisionSet {
    NSMutableDictionary *revisionsByIdentifier;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        revisionsByIdentifier = [[NSMutableDictionary alloc] initWithCapacity:10];
    }
    return self;
}

- (NSSet *)revisions
{
    NSSet *result = [NSSet setWithArray:revisionsByIdentifier.allValues];
    return result;
}

- (NSSet *)persistentStoreIdentifiers
{
    return [self.revisions valueForKeyPath:@"persistentStoreIdentifier"];
}

- (CDERevision *)revisionForPersistentStoreIdentifier:(NSString *)identifier
{
    return revisionsByIdentifier[identifier];
}

- (BOOL)hasRevisionForPersistentStoreIdentifier:(NSString *)identifier
{
    return revisionsByIdentifier[identifier] != nil;
}

- (void)addRevision:(CDERevision *)newRevision
{
    NSString *newId = newRevision.persistentStoreIdentifier;
    NSAssert(revisionsByIdentifier[newId] == nil, @"Store is already present in set");
    revisionsByIdentifier[newId] = newRevision;
}

- (void)removeRevision:(CDERevision *)revision
{
    NSString *revisionId = revision.persistentStoreIdentifier;
    NSAssert(revisionsByIdentifier[revisionId] != nil, @"Store is not present in set");
    [revisionsByIdentifier removeObjectForKey:revisionId];
}

- (void)removeRevisionForPersistentStoreIdentifier:(NSString *)identifier
{
    CDERevision *revision = [self revisionForPersistentStoreIdentifier:identifier];
    if (!revision) return;
    [self removeRevision:revision];
}

- (NSUInteger)numberOfRevisions
{
    return revisionsByIdentifier.count;
}

- (void)incrementRevisionForStoreWithIdentifier:(NSString *)persistentStoreIdentifier
{
    NSAssert([self hasRevisionForPersistentStoreIdentifier:persistentStoreIdentifier], @"Store identifier not found");
    
    CDERevision *existingRevision = revisionsByIdentifier[persistentStoreIdentifier];
    CDERevision *newRevision = [[CDERevision alloc] initWithPersistentStoreIdentifier:persistentStoreIdentifier revisionNumber:existingRevision.revisionNumber+1];
    
    [self removeRevision:existingRevision];
    [self addRevision:newRevision];
}

- (CDERevisionSet *)revisionSetByReducingRevisionSet:(CDERevisionSet *)otherSet withBlock:(CDERevisionNumber(^)(CDERevisionNumber firstRev, CDERevisionNumber secondRev))block
{
    NSMutableSet *allStoreIds = [[NSMutableSet alloc] initWithSet:self.persistentStoreIdentifiers];
    [allStoreIds unionSet:otherSet.persistentStoreIdentifiers];
    
    CDERevisionSet *resultSet = [[CDERevisionSet alloc] init];
    for ( NSString *persistentStoreId in allStoreIds ) {
        CDERevision *rev1 = [self revisionForPersistentStoreIdentifier:persistentStoreId];
        CDERevision *rev2 = [otherSet revisionForPersistentStoreIdentifier:persistentStoreId];
        
        CDERevisionNumber reducedRev;
        if (!rev1)
            reducedRev = rev2.revisionNumber;
        else if (!rev2)
            reducedRev = rev1.revisionNumber;
        else
            reducedRev = block(rev1.revisionNumber, rev2.revisionNumber);
        
        CDERevision *newRevision = [[CDERevision alloc] initWithPersistentStoreIdentifier:persistentStoreId revisionNumber:reducedRev];
        [resultSet addRevision:newRevision];
    }
    
    return resultSet;
}

- (CDERevisionSet *)revisionSetByTakingStoreWiseMinimumWithRevisionSet:(CDERevisionSet *)otherSet
{
    return [self revisionSetByReducingRevisionSet:otherSet withBlock:^CDERevisionNumber(CDERevisionNumber firstRev, CDERevisionNumber secondRev) {
        return MIN(firstRev, secondRev);
    }];
}

- (CDERevisionSet *)revisionSetByTakingStoreWiseMaximumWithRevisionSet:(CDERevisionSet *)otherSet
{
    return [self revisionSetByReducingRevisionSet:otherSet withBlock:^CDERevisionNumber(CDERevisionNumber firstRev, CDERevisionNumber secondRev) {
        return MAX(firstRev, secondRev);
    }];
}

- (NSComparisonResult)compare:(CDERevisionSet *)otherSet
{
    NSMutableSet *allStoreIds = [[NSMutableSet alloc] initWithSet:self.persistentStoreIdentifiers];
    [allStoreIds unionSet:otherSet.persistentStoreIdentifiers];
    
    BOOL rev1AlwaysMax = YES, rev2AlwaysMax = YES;
    BOOL rev1AlwaysEqualToRev2 = YES;
    for ( NSString *persistentStoreId in allStoreIds ) {
        CDERevision *rev1 = [self revisionForPersistentStoreIdentifier:persistentStoreId];
        CDERevision *rev2 = [otherSet revisionForPersistentStoreIdentifier:persistentStoreId];
        
        if (!rev1) {
            rev1AlwaysMax = NO;
            rev1AlwaysEqualToRev2 = NO;
            continue;
        }
        
        if (!rev2) {
            rev2AlwaysMax = NO;
            rev1AlwaysEqualToRev2 = NO;
            continue;
        }
        
        if (rev1.revisionNumber != rev2.revisionNumber) rev1AlwaysEqualToRev2 = NO;
        if (rev1.revisionNumber > rev2.revisionNumber) {
            rev2AlwaysMax = NO;
        }
        if (rev1.revisionNumber < rev2.revisionNumber) {
            rev1AlwaysMax = NO;
        }
    }
    
    NSComparisonResult result;
    if (rev1AlwaysEqualToRev2)
        result = NSOrderedSame;
    else if (rev1AlwaysMax)
        result = NSOrderedDescending;
    else if (rev2AlwaysMax)
        result = NSOrderedAscending;
    else
        result = NSOrderedSame;
    
    return result;
}

@end
