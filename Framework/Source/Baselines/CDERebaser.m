//
//  CDEBaselinePropagator.m
//  Ensembles
//
//  Created by Drew McCormack on 05/01/14.
//  Copyright (c) 2014 Drew McCormack. All rights reserved.
//

#import "CDERebaser.h"
#import "NSManagedObjectModel+CDEAdditions.h"
#import "CDEDefines.h"
#import "CDEEventStore.h"
#import "CDEPersistentStoreEnsemble.h"
#import "CDEStoreModificationEvent.h"
#import "CDEObjectChange.h"
#import "CDEEventRevision.h"
#import "CDERevisionManager.h"
#import "CDERevisionSet.h"
#import "CDERevision.h"


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
    // or if there is no baseline at all
    NSManagedObjectContext *context = eventStore.managedObjectContext;
    __block BOOL hasBaseline = NO;
    [context performBlockAndWait:^{
        CDEStoreModificationEvent *baseline = [CDEStoreModificationEvent fetchBaselineStoreModificationEventInManagedObjectContext:context];
        hasBaseline = baseline != nil;
    }];
    return !hasBaseline || self.estimatedEventStoreCompactionFollowingRebase > 0.5;
}


#pragma mark Rebasing

- (void)rebaseWithCompletion:(CDECompletionBlock)completion
{
    CDEGlobalCount newBaselineGlobalCount = [self globalCountForNewBaseline];
    
    NSManagedObjectContext *context = eventStore.managedObjectContext;
    [context performBlock:^{
        NSArray *eventsToMerge = [CDEStoreModificationEvent fetchStoreModificationEventsUpToGlobalCount:newBaselineGlobalCount inManagedObjectContext:context];
        if (eventsToMerge.count == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(nil);
            });
            return;
        }
        
        // Fetch baseline. If none exists, create one.
        CDEStoreModificationEvent *baseline = [CDEStoreModificationEvent fetchBaselineStoreModificationEventInManagedObjectContext:context];
        if (!baseline) {
            baseline = [NSEntityDescription insertNewObjectForEntityForName:@"CDEStoreModificationEvent" inManagedObjectContext:context];
            baseline.type = CDEStoreModificationEventTypeBaseline;
            baseline.globalCount = -1;
            baseline.modelVersion = [self.ensemble.managedObjectModel cde_entityHashesPropertyList];
        }
        
        // Prefetch
        [CDEStoreModificationEvent prefetchRelatedObjectsForStoreModificationEvents:eventsToMerge];
        
        // Merge events
        CDERevisionSet *baselineRevisionSet = baseline.revisionSet;
        CDERevisionSet *newRevisionSet = baselineRevisionSet;
        for (CDEStoreModificationEvent *event in eventsToMerge) {
            CDERevisionSet *eventRevisionSet = event.revisionSet;
            
            // Check that event comes after baseline
            if ([eventRevisionSet compare:baselineRevisionSet] == NSOrderedAscending) continue;
            
            // Merge event
            
            
            
            
            
            // Get lastest revisions
            newRevisionSet = [newRevisionSet revisionSetByTakingStoreWiseMaximumWithRevisionSet:event.revisionSet];
        }
        
        // Set new count and timestamp
        baseline.globalCount = newBaselineGlobalCount;
        baseline.timestamp = [NSDate timeIntervalSinceReferenceDate];
        
        // Update revisions
        NSString *persistentStoreId = self.eventStore.persistentStoreIdentifier;
        CDERevision *revision = [newRevisionSet revisionForPersistentStoreIdentifier:persistentStoreId];
        CDERevisionNumber revisionNumber = revision ? revision.revisionNumber : -1;
        CDEEventRevision *eventRevision = [CDEEventRevision makeEventRevisionForPersistentStoreIdentifier:persistentStoreId revisionNumber:revisionNumber inManagedObjectContext:context];
        baseline.eventRevision = eventRevision;
        
        [newRevisionSet removeRevisionForPersistentStoreIdentifier:persistentStoreId];
        baseline.eventRevisionsOfOtherStores = [CDEEventRevision makeEventRevisionsForRevisionSet:newRevisionSet inManagedObjectContext:context];
        
        // Delete merged events
        for (CDEStoreModificationEvent *event in eventsToMerge) [context deleteObject:event];

        // Save
        NSError *error;
        if (![context save:&error]) CDELog(CDELoggingLevelError, @"Failed to save rebase: %@", error);
    }];
}

- (CDEGlobalCount)globalCountForNewBaseline
{
    CDERevisionManager *revisionManager = [[CDERevisionManager alloc] initWithEventStore:self.eventStore];
    CDERevisionSet *latestRevisionSet = [revisionManager revisionSetOfMostRecentEvents];
    
    // We will remove any store that hasn't updated since the existing baseline
    NSManagedObjectContext *context = eventStore.managedObjectContext;
    __block CDERevisionSet *baselineRevisionSet;
    [context performBlockAndWait:^{
        CDEStoreModificationEvent *baselineEvent = [CDEStoreModificationEvent fetchBaselineStoreModificationEventInManagedObjectContext:context];
        baselineRevisionSet = baselineEvent.revisionSet;
    }];
    
    // Baseline count is minimum of global count from all devices
    CDEGlobalCount baselineCount = NSNotFound;
    for (CDERevision *revision in latestRevisionSet.revisions) {
        // Ignore stores that haven't updated since the baseline
        // They will have to re-leech
        NSString *storeId = revision.persistentStoreIdentifier;
        CDERevision *baselineRevision = [baselineRevisionSet revisionForPersistentStoreIdentifier:storeId];
        if (!baselineRevision || baselineRevision.revisionNumber >= revision.revisionNumber) continue;
        
        // Find the minimum global count
        baselineCount = MIN(baselineCount, revision.revisionNumber);
    }
    if (baselineCount == NSNotFound) baselineCount = -1;
    
    return baselineCount;
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
