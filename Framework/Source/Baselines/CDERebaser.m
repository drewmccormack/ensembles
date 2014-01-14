//
//  CDEBaselinePropagator.m
//  Ensembles
//
//  Created by Drew McCormack on 05/01/14.
//  Copyright (c) 2014 Drew McCormack. All rights reserved.
//

#import "CDERebaser.h"
#import "CDEDefines.h"
#import "CDEEventStore.h"
#import "CDEStoreModificationEvent.h"
#import "CDEObjectChange.h"

@implementation CDERebaser

@synthesize eventStore = eventStore;
@synthesize ensemble = ensemble;

- (instancetype)initWithEventStore:(CDEEventStore *)newStore
{
    self = [super init];
    if (self) {
        eventStore = newStore;
    }
    return self;
}


#pragma mark Determining When to Rebase

- (CGFloat)estimatedEventStoreCompactionFollowingRebase
{
    // Determine size of baseline
    NSInteger currentBaselineCount = [self countOfBaseline];
    
    // Determine inserted, deleted, and updated changes outside baseline
    NSInteger deletedCount = [self countOfNonBaselineObjectChangesOfType:CDEObjectChangeTypeDelete];
    NSInteger insertedCount = [self countOfNonBaselineObjectChangesOfType:CDEObjectChangeTypeInsert];
    NSInteger updatedCount = [self countOfNonBaselineObjectChangesOfType:CDEObjectChangeTypeUpdate];
    
    // Estimate size of baseline after rebasing
    NSInteger rebasedBaselineCount = currentBaselineCount - 2*deletedCount - updatedCount + insertedCount;

    // Estimate compaction
    NSInteger currentCount = currentBaselineCount + deletedCount + insertedCount + updatedCount;
    CGFloat compaction = 1.0f - ( rebasedBaselineCount / (CGFloat)MAX(1,currentCount) );
    compaction = MIN( MAX(compaction, 0.0f), 1.0f);
    
    return compaction;
}

- (BOOL)shouldRebase
{
    // Rebase if we can reduce object changes by more than 50%
    return self.estimatedEventStoreCompactionFollowingRebase > 0.5;
}


#pragma mark Rebasing

- (void)rebaseWithCompletion:(CDECompletionBlock)completion
{
    
}


#pragma mark Fetching Object Change Counts

- (NSUInteger)countOfNonBaselineObjectChangesOfType:(CDEObjectChangeType)type
{
    __block NSUInteger count = 0;
    NSManagedObjectContext *context = eventStore.managedObjectContext;
    [context performBlockAndWait:^{
        NSError *error = nil;
        NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"CDEObjectChange"];
        NSPredicate *eventTypePredicate = [NSPredicate predicateWithFormat:@"storeModificationEvent.type != %d", CDEStoreModificationEventTypeBaseline];
        NSPredicate *changeTypePredicate = [NSPredicate predicateWithFormat:@"type = %d", type];
        fetch.predicate = [NSCompoundPredicate andPredicateWithSubpredicates:@[eventTypePredicate, changeTypePredicate]];
        count = [context countForFetchRequest:fetch error:&error];
        if (error) CDELog(CDELoggingLevelError, @"Couldn't fetch count of non-baseline objects: %@", error);
    }];
    return count;
}

- (NSUInteger)countOfBaseline
{
    __block NSUInteger count = 0;
    NSManagedObjectContext *context = eventStore.managedObjectContext;
    [context performBlockAndWait:^{
        NSError *error = nil;
        NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"CDEObjectChange"];
        fetch.predicate = [NSPredicate predicateWithFormat:@"storeModificationEvent.type = %d", CDEStoreModificationEventTypeBaseline];
        count = [context countForFetchRequest:fetch error:&error];
        if (error) CDELog(CDELoggingLevelError, @"Couldn't fetch count of baseline: %@", error);
    }];
    return count;
}

@end
