//
//  CDERebaser.m
//  Ensembles
//
//  Created by Drew McCormack on 05/01/14.
//  Copyright (c) 2014 Drew McCormack. All rights reserved.
//

#import "CDERebaser.h"
#import "NSManagedObjectModel+CDEAdditions.h"
#import "CDEFoundationAdditions.h"
#import "NSMapTable+CDEAdditions.h"
#import "CDEDefines.h"
#import "CDEEventStore.h"
#import "CDEPersistentStoreEnsemble.h"
#import "CDEStoreModificationEvent.h"
#import "CDEObjectChange.h"
#import "CDEGlobalIdentifier.h"
#import "CDEEventRevision.h"
#import "CDERevisionManager.h"
#import "CDERevisionSet.h"
#import "CDERevision.h"

@interface CDERebaser ()

@property (nonatomic, readwrite, assign) BOOL forceRebase; // Used only for testing

@end

@implementation CDERebaser

@synthesize eventStore = eventStore;
@synthesize ensemble = ensemble;
@synthesize forceRebase = forceRebase;

- (instancetype)initWithEventStore:(CDEEventStore *)newStore
{
    self = [super init];
    if (self) {
        eventStore = newStore;
        forceRebase = NO;
    }
    return self;
}


#pragma mark Removing Out-of-Date Events

- (void)deleteEventsPreceedingBaselineWithCompletion:(CDECompletionBlock)completion
{
    NSManagedObjectContext *context = eventStore.managedObjectContext;
    [context performBlock:^{
        CDEStoreModificationEvent *baseline = [CDEStoreModificationEvent fetchMostRecentBaselineStoreModificationEventInManagedObjectContext:context];
        CDERevisionSet *baselineRevisionSet = baseline.revisionSet;
        NSSet *storeIds = baselineRevisionSet.persistentStoreIdentifiers;
        NSArray *types = @[@(CDEStoreModificationEventTypeMerge), @(CDEStoreModificationEventTypeSave)];
        for (NSString *storeId in storeIds) {
            CDERevision *baseRevision = [baselineRevisionSet revisionForPersistentStoreIdentifier:storeId];
            
            NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"CDEStoreModificationEvent"];
            NSPredicate *storePredicate = [CDEStoreModificationEvent predicateForAllowedTypes:types persistentStoreIdentifier:storeId];
            NSPredicate *revisionPredicate = [NSPredicate predicateWithFormat:@"eventRevision.revisionNumber <= %lld", baseRevision.revisionNumber];
            fetch.predicate = [NSCompoundPredicate andPredicateWithSubpredicates:@[storePredicate, revisionPredicate]];
            
            NSError *error;
            NSArray *events = [context executeFetchRequest:fetch error:&error];
            if (!events) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completion) completion(error);
                });
                return;
            }
            
            [CDEStoreModificationEvent prefetchRelatedObjectsForStoreModificationEvents:events];
            for (CDEStoreModificationEvent *event in events) {
                [context deleteObject:event];
            }
        }
        
        NSError *error = nil;
        BOOL saved = [context save:&error];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(saved ? nil : error);
        });
    }];
}

#pragma mark Determining When to Rebase

- (void)estimateEventStoreCompactionFollowingRebaseWithCompletion:(void(^)(float compaction))completion
{
    NSParameterAssert(completion);
    [self.eventStore.managedObjectContext performBlock:^{
        // Determine size of baseline
        NSInteger currentBaselineCount = [self countOfBaseline];
        
        // Determine inserted, deleted, and updated changes outside baseline
        NSInteger deletedCount = [self countOfNonBaselineObjectChangesOfType:CDEObjectChangeTypeDelete];
        NSInteger insertedCount = [self countOfNonBaselineObjectChangesOfType:CDEObjectChangeTypeInsert];
        NSInteger updatedCount = [self countOfNonBaselineObjectChangesOfType:CDEObjectChangeTypeUpdate];
        
        // Estimate size of baseline after rebasing.
        // Assume that an insertion is 1 data unit.
        // A deletion removes at least one insertion, so it is worth 1 data unit.
        // An update is usually to some subset of properties. Assume it has weight 0.2 data units.
        float postRebaseSize = currentBaselineCount - deletedCount + insertedCount;
        
        // Estimate compaction
        float currentSize = currentBaselineCount + insertedCount + 0.2*updatedCount;
        float compaction = 1.0f - ( postRebaseSize / (float)MAX(1,currentSize) );
        compaction = MIN( MAX(compaction, 0.0f), 1.0f);
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(compaction);
        });
    }];
}

- (void)shouldRebaseWithCompletion:(void(^)(BOOL result))completion
{
    NSParameterAssert(completion);
    
    if (self.forceRebase) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(YES);
        });
        return;
    }

    // Rebase if there are more than 500 object changes, or we can reduce data by more than 50%,
    // or if there is no baseline at all
    NSManagedObjectContext *context = eventStore.managedObjectContext;
    [context performBlock:^{
        BOOL hasBaseline = NO;
        CDERevisionSet *baselineRevisionSet = nil;
        CDEStoreModificationEvent *baseline = [CDEStoreModificationEvent fetchMostRecentBaselineStoreModificationEventInManagedObjectContext:context];
        hasBaseline = baseline != nil;
        baselineRevisionSet = baseline.revisionSet;
        
        // Rebase if the baseline doesn't include all stores
        CDERevisionManager *revisionManager = [[CDERevisionManager alloc] initWithEventStore:self.eventStore];
        NSSet *allStores = revisionManager.allPersistentStoreIdentifiers;
        BOOL hasAllDevicesInBaseline = [baselineRevisionSet.persistentStoreIdentifiers isEqualToSet:allStores];
        
        BOOL hasManyEvents = [self countOfStoreModificationEvents] > 50;
        BOOL hasAdequateChanges = [self countOfAllObjectChanges] >= 500;
        
        [self estimateEventStoreCompactionFollowingRebaseWithCompletion:^(float compaction) {
            BOOL compactionIsAdequate = compaction > 0.5f;
            BOOL result = !hasBaseline || !hasAllDevicesInBaseline || hasManyEvents || (hasAdequateChanges && compactionIsAdequate);
            if (completion) completion(result);
        }];
    }];
}


#pragma mark Rebasing

- (void)rebaseWithCompletion:(CDECompletionBlock)completion
{
    CDELog(CDELoggingLevelVerbose, @"Starting rebase");
    
    CDEGlobalCount newBaselineGlobalCount = [self globalCountForNewBaseline];
    CDELog(CDELoggingLevelVerbose, @"New baseline global count: %lld", newBaselineGlobalCount);
    
    NSManagedObjectContext *context = eventStore.managedObjectContext;
    [context performBlock:^{
        // Fetch objects
        CDEStoreModificationEvent *existingBaseline = [CDEStoreModificationEvent fetchMostRecentBaselineStoreModificationEventInManagedObjectContext:context];
        NSArray *eventsToMerge = [CDEStoreModificationEvent fetchNonBaselineEventsUpToGlobalCount:newBaselineGlobalCount inManagedObjectContext:context];
        if (existingBaseline && eventsToMerge.count == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(nil);
            });
            return;
        }
        
        // Check that events can be integrated, ie, pass all checks.
        NSError *error = nil;
        CDERevisionManager *revisionManager = [[CDERevisionManager alloc] initWithEventStore:self.eventStore];
        revisionManager.managedObjectModelURL = self.ensemble.managedObjectModelURL;
        BOOL passedChecks = [revisionManager checkRebasingPrerequisitesForEvents:eventsToMerge error:&error];
        if (!passedChecks) {
            CDELog(CDELoggingLevelWarning, @"Failed rebasing prerequisite checks. Aborting rebase");
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(error);
            });
            return;
        }
        
        // If no baseline exists, create one.
        CDEStoreModificationEvent *newBaseline = existingBaseline;
        if (!existingBaseline) {
            newBaseline = [NSEntityDescription insertNewObjectForEntityForName:@"CDEStoreModificationEvent" inManagedObjectContext:context];
            newBaseline.type = CDEStoreModificationEventTypeBaseline;
        }
    
        // Merge events into baseline
        [self mergeOrderedEvents:eventsToMerge intoBaseline:newBaseline];
        
        // Set new count and other properties
        newBaseline.globalCount = newBaselineGlobalCount;
        newBaseline.timestamp = [NSDate timeIntervalSinceReferenceDate];
        newBaseline.modelVersion = [self.ensemble.managedObjectModel cde_entityHashesPropertyList];
        
        // Update store revisions by taking the maximum for each store, and the baseline
        NSArray *revisionedEvents = eventsToMerge;
        if (existingBaseline) revisionedEvents = [revisionedEvents arrayByAddingObject:existingBaseline];
        CDERevisionSet *newRevisionSet = [CDERevisionSet revisionSetByTakingStoreWiseMaximumOfRevisionSets:[revisionedEvents valueForKeyPath:@"revisionSet"]];
        NSString *persistentStoreId = self.eventStore.persistentStoreIdentifier;
        [newBaseline setRevisionSet:newRevisionSet forPersistentStoreIdentifier:persistentStoreId];
        if (newBaseline.eventRevision.revisionNumber == -1) newBaseline.eventRevision.revisionNumber = 0;
        
        // Delete merged events
        for (CDEStoreModificationEvent *event in eventsToMerge) [context deleteObject:event];

        // Save
        BOOL saved = [context save:&error];
        if (!saved) CDELog(CDELoggingLevelError, @"Failed to save rebase: %@", error);
        
        // Complete
        dispatch_async(dispatch_get_main_queue(), ^{
            CDELog(CDELoggingLevelVerbose, @"Finishing rebase");
            if (completion) completion(saved ? nil : error);
        });
    }];
}

- (void)mergeOrderedEvents:(NSArray *)eventsToMerge intoBaseline:(CDEStoreModificationEvent *)baseline
{
    // Create map of existing object changes
    [CDEStoreModificationEvent prefetchRelatedObjectsForStoreModificationEvents:@[baseline]];
    NSMapTable *objectChangesByGlobalId = [NSMapTable cde_strongToStrongObjectsMapTable];
    NSSet *objectChanges = baseline.objectChanges;
    for (CDEObjectChange *change in objectChanges) {
        [objectChangesByGlobalId setObject:change forKey:change.globalIdentifier];
    }
    
    // Loop through events, merging them in the baseline
    for (CDEStoreModificationEvent *event in eventsToMerge) {
        
        // Prefetch for performance
        [CDEStoreModificationEvent prefetchRelatedObjectsForStoreModificationEvents:@[event]];
        
        // Loop through object changes
        [event.objectChanges.allObjects cde_enumerateObjectsDrainingEveryIterations:100 usingBlock:^(CDEObjectChange *change, NSUInteger index, BOOL *stop) {
            CDEObjectChange *existingChange = [objectChangesByGlobalId objectForKey:change.globalIdentifier];
            [self mergeChange:change withSubordinateChange:existingChange addToBaseline:baseline withObjectChangesByGlobalId:objectChangesByGlobalId];
        }];
    }
}

- (void)mergeChange:(CDEObjectChange *)change withSubordinateChange:(CDEObjectChange *)subordinateChange addToBaseline:(CDEStoreModificationEvent *)baseline withObjectChangesByGlobalId:(NSMapTable *)objectChangesByGlobalId
{
    NSManagedObjectContext *context = change.managedObjectContext;
    switch (change.type) {
        case CDEObjectChangeTypeDelete:
            if (subordinateChange) {
                [objectChangesByGlobalId removeObjectForKey:change.globalIdentifier];
                [context deleteObject:subordinateChange];
            }
            break;
            
        case CDEObjectChangeTypeInsert:
            if (subordinateChange) {
                [change mergeValuesFromSubordinateObjectChange:subordinateChange];
                [context deleteObject:subordinateChange];
            }
            change.storeModificationEvent = baseline;
            [objectChangesByGlobalId setObject:change forKey:change.globalIdentifier];
            break;
            
        case CDEObjectChangeTypeUpdate:
            if (subordinateChange) {
                [change mergeValuesFromSubordinateObjectChange:subordinateChange];
                [context deleteObject:subordinateChange];
                change.type = CDEObjectChangeTypeInsert;
                change.storeModificationEvent = baseline;
                [objectChangesByGlobalId setObject:change forKey:change.globalIdentifier];
            }
            break;
            
        default:
            @throw [NSException exceptionWithName:CDEException reason:@"Invalid object change type" userInfo:nil];
            break;
    }
}

- (CDEGlobalCount)globalCountForNewBaseline
{
    CDERevisionManager *revisionManager = [[CDERevisionManager alloc] initWithEventStore:self.eventStore];
    CDERevisionSet *latestRevisionSet = [revisionManager revisionSetOfMostRecentEvents];
    
    // We will remove any store that hasn't updated since the existing baseline
    NSManagedObjectContext *context = eventStore.managedObjectContext;
    __block CDERevisionSet *baselineRevisionSet;
    [context performBlockAndWait:^{
        CDEStoreModificationEvent *baselineEvent = [CDEStoreModificationEvent fetchMostRecentBaselineStoreModificationEventInManagedObjectContext:context];
        baselineRevisionSet = baselineEvent.revisionSet;
    }];
    
    // Baseline count is minimum of global count from all devices
    CDEGlobalCount baselineCount = NSNotFound;
    for (CDERevision *revision in latestRevisionSet.revisions) {
        // Ignore stores that haven't updated since the baseline
        // They will have to do a full integration to catch up
        NSString *storeId = revision.persistentStoreIdentifier;
        CDERevision *baselineRevision = [baselineRevisionSet revisionForPersistentStoreIdentifier:storeId];
        if (baselineRevision && baselineRevision.revisionNumber >= revision.revisionNumber) continue;
        
        // Find the minimum global count
        baselineCount = MIN(baselineCount, revision.globalCount);
    }
    if (baselineCount == NSNotFound) baselineCount = 0;
    
    return baselineCount;
}


#pragma mark Fetching Counts

- (NSUInteger)countOfStoreModificationEvents
{
    __block NSUInteger count = 0;
    NSManagedObjectContext *context = eventStore.managedObjectContext;
    [context performBlockAndWait:^{
        NSError *error = nil;
        NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"CDEStoreModificationEvent"];
        count = [context countForFetchRequest:fetch error:&error];
        if (error) CDELog(CDELoggingLevelError, @"Couldn't fetch count of events: %@", error);
    }];
    return count;
}

- (NSUInteger)countOfAllObjectChanges
{
    __block NSUInteger count = 0;
    NSManagedObjectContext *context = eventStore.managedObjectContext;
    [context performBlockAndWait:^{
        NSError *error = nil;
        NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"CDEObjectChange"];
        count = [context countForFetchRequest:fetch error:&error];
        if (error) CDELog(CDELoggingLevelError, @"Couldn't fetch count of object changes: %@", error);
    }];
    return count;
}

- (NSUInteger)countOfNonBaselineObjectChangesOfType:(CDEObjectChangeType)type
{
    __block NSUInteger count = 0;
    NSManagedObjectContext *context = eventStore.managedObjectContext;
    [context performBlockAndWait:^{
        NSError *error = nil;
        NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"CDEObjectChange"];
        NSPredicate *eventTypePredicate = [NSPredicate predicateWithFormat:@"storeModificationEvent.type != %d && storeModificationEvent.type != %d", CDEStoreModificationEventTypeBaseline, CDEStoreModificationEventTypeIncomplete];
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
