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
    if (revisionsByIdentifier[newId] != nil) {
        CDELog(CDELoggingLevelError, @"Found duplicate store in revision set. Existing Set: %@\rNew Rev: %@", self, newRevision);
    }
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


#pragma mark Determining Maxima/Minima

- (CDERevisionSet *)revisionSetByReducingRevisionSet:(CDERevisionSet *)otherSet withBlock:(CDERevisionNumber(^)(CDERevisionNumber firstRev, CDERevisionNumber secondRev))block
{
    NSMutableSet *allStoreIds = [[NSMutableSet alloc] initWithSet:self.persistentStoreIdentifiers];
    [allStoreIds unionSet:otherSet.persistentStoreIdentifiers];
    [allStoreIds removeObject:[NSNull null]];
    
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
        
        CDEGlobalCount reducedGlobalCount;
        if (!rev1)
            reducedGlobalCount = rev2.globalCount;
        else if (!rev2)
            reducedGlobalCount = rev1.globalCount;
        else
            reducedGlobalCount = block(rev1.globalCount, rev2.globalCount);
        
        CDERevision *newRevision = [[CDERevision alloc] initWithPersistentStoreIdentifier:persistentStoreId revisionNumber:reducedRev globalCount:reducedGlobalCount];
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

+ (CDERevisionSet *)revisionSetByTakingStoreWiseMaximumOfRevisionSets:(NSArray *)sets
{
    CDERevisionSet *newSet = [[CDERevisionSet alloc] init];
    for (CDERevisionSet *set in sets) {
        newSet = [newSet revisionSetByTakingStoreWiseMaximumWithRevisionSet:set];
    }
    return newSet;
}


#pragma mark Ordering

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

- (BOOL)isEqualToRevisionSet:(CDERevisionSet *)otherSet
{
    NSMutableSet *allStoreIds = [[NSMutableSet alloc] initWithSet:self.persistentStoreIdentifiers];
    [allStoreIds unionSet:otherSet.persistentStoreIdentifiers];
    
    BOOL rev1AlwaysEqualToRev2 = YES;
    for ( NSString *persistentStoreId in allStoreIds ) {
        CDERevision *rev1 = [self revisionForPersistentStoreIdentifier:persistentStoreId];
        CDERevision *rev2 = [otherSet revisionForPersistentStoreIdentifier:persistentStoreId];
        
        if (!rev1 || !rev2 || (rev1.revisionNumber != rev2.revisionNumber)) {
            rev1AlwaysEqualToRev2 = NO;
            break;
        }
    }
    
    return rev1AlwaysEqualToRev2;
}


#pragma mark Description

- (NSString *)description
{
    NSMutableString *result = [[NSMutableString alloc] initWithString:[super description]];
    [result appendString:@"\n"];
    for (CDERevision *revision in self.revisions) {
        [result appendFormat:@"Store: %@, Global Count: %lli, Revision: %lli\n", revision.persistentStoreIdentifier, revision.globalCount, revision.revisionNumber];
    }
    return result;
}

@end
