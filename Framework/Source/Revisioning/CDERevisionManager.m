//
//  CDERevisionManager.m
//  Ensembles
//
//  Created by Drew McCormack on 25/08/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import "CDERevisionManager.h"
#import "CDEEventStore.h"
#import "CDERevision.h"
#import "CDERevisionSet.h"
#import "CDEEventRevision.h"
#import "CDEStoreModificationEvent.h"

@implementation CDERevisionManager

@synthesize eventStore = eventStore;
@synthesize eventManagedObjectContext = eventManagedObjectContext;

#pragma mark Initialization

- (instancetype)initWithEventStore:(CDEEventStore *)newStore eventManagedObjectContext:(NSManagedObjectContext *)newContext
{
    self = [super init];
    if (self) {
        eventStore = newStore;
        eventManagedObjectContext = newContext;
    }
    return self;
}

- (instancetype)initWithEventStore:(CDEEventStore *)newStore
{
    return [self initWithEventStore:newStore eventManagedObjectContext:newStore.managedObjectContext];
}

#pragma mark Fetching from Event Store

- (NSArray *)sortStoreModificationEvents:(NSArray *)events
{
    // Sort in save order. Use store id to disambiguate in unlikely event of identical timestamps.
    NSArray *sortDescriptors = @[
        [NSSortDescriptor sortDescriptorWithKey:@"globalCount" ascending:YES],
        [NSSortDescriptor sortDescriptorWithKey:@"timestamp" ascending:YES],
        [NSSortDescriptor sortDescriptorWithKey:@"eventRevision.persistentStoreIdentifier" ascending:YES]
    ];
    return [events sortedArrayUsingDescriptors:sortDescriptors];
}

- (NSArray *)fetchUncommittedStoreModificationEvents:(NSError * __autoreleasing *)error
{
    __block NSArray *result = nil;
    [eventManagedObjectContext performBlockAndWait:^{
        CDEStoreModificationEvent *lastMergeEvent = [CDEStoreModificationEvent fetchStoreModificationEventForPersistentStoreIdentifier:eventStore.persistentStoreIdentifier revisionNumber:eventStore.lastMergeRevision inManagedObjectContext:eventManagedObjectContext];
        CDERevisionSet *lastMergeRevisionSet = lastMergeEvent.revisionSet;
        if (!lastMergeRevisionSet) lastMergeRevisionSet = [CDERevisionSet new]; // No previous merge
        
        // Determine which stores have appeared since last merge
        NSSet *allStoreIds = [CDEEventRevision fetchPersistentStoreIdentifiersInManagedObjectContext:eventManagedObjectContext];
        NSSet *lastMergeStoreIds = lastMergeRevisionSet.persistentStoreIdentifiers;
        NSMutableSet *missingStoreIds = [NSMutableSet setWithSet:allStoreIds];
        [missingStoreIds minusSet:lastMergeStoreIds];
        
        NSMutableArray *events = [[NSMutableArray alloc] init];
        for (CDEEventRevision *revision in lastMergeRevisionSet.revisions) {
            NSArray *recentEvents = [CDEStoreModificationEvent fetchStoreModificationEventsForPersistentStoreIdentifier:revision.persistentStoreIdentifier sinceRevisionNumber:revision.revisionNumber inManagedObjectContext:eventManagedObjectContext];
            [events addObjectsFromArray:recentEvents];
        }
        
        for (NSString *persistentStoreId in missingStoreIds) {
            NSArray *recentEvents = [CDEStoreModificationEvent fetchStoreModificationEventsForPersistentStoreIdentifier:persistentStoreId sinceRevisionNumber:-1 inManagedObjectContext:eventManagedObjectContext];
            [events addObjectsFromArray:recentEvents];
        }
        
        result = [self sortStoreModificationEvents:events];
    }];
    return result;
}

- (NSArray *)fetchStoreModificationEventsConcurrentWithEvents:(NSArray *)events error:(NSError *__autoreleasing *)error
{
    if (events.count == 0) return @[];
    
    __block NSArray *result = nil;
    [eventManagedObjectContext performBlockAndWait:^{
        CDERevisionSet *minSet = [[CDERevisionSet alloc] init];
        for (CDEStoreModificationEvent *event in events) {
            CDERevisionSet *revSet = event.revisionSet;
            minSet = [minSet revisionSetByTakingStoreWiseMinimumWithRevisionSet:revSet];
        }
        
        // Add concurrent events from the stores present in the events passed in
        NSManagedObjectContext *context = [events.lastObject managedObjectContext];
        NSMutableSet *concurrentEvents = [[NSMutableSet alloc] initWithArray:events]; // Events are concurrent with themselves
        for (CDERevision *minRevision in minSet.revisions) {
            NSArray *recentEvents = [CDEStoreModificationEvent fetchStoreModificationEventsForPersistentStoreIdentifier:minRevision.persistentStoreIdentifier sinceRevisionNumber:minRevision.revisionNumber inManagedObjectContext:context];
            [concurrentEvents addObjectsFromArray:recentEvents];
        }
        
        // Determine which stores are missing from the events
        NSSet *allStoreIds = [CDEEventRevision fetchPersistentStoreIdentifiersInManagedObjectContext:context];
        NSMutableSet *missingStoreIds = [NSMutableSet setWithSet:allStoreIds];
        [missingStoreIds minusSet:minSet.persistentStoreIdentifiers];
        
        // Add events from the missing stores
        for (NSString *persistentStoreId in missingStoreIds) {
            NSArray *recentEvents = [CDEStoreModificationEvent fetchStoreModificationEventsForPersistentStoreIdentifier:persistentStoreId sinceRevisionNumber:-1 inManagedObjectContext:context];
            [concurrentEvents addObjectsFromArray:recentEvents];
        }
        
        result = [self sortStoreModificationEvents:concurrentEvents.allObjects];
    }];
    
    return result;
}

#pragma mark Checks

- (BOOL)checkIntegrationPrequisites:(NSError * __autoreleasing *)error
{
    __block BOOL result = YES;
    [eventManagedObjectContext performBlockAndWait:^{
        NSArray *uncommittedEvents = [self fetchUncommittedStoreModificationEvents:error];
        if (!uncommittedEvents) {
            result = NO;
            return;
        }
        
        if (![self checkAllDependenciesExistForStoreModificationEvents:uncommittedEvents]) {
            if (error) *error = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeMissingDependencies userInfo:nil];
            result = NO;
            return;
        }
        
        NSArray *concurrentEvents = [self fetchStoreModificationEventsConcurrentWithEvents:uncommittedEvents error:error];
        if (!concurrentEvents) {
            result = NO;
            return;
        }
        
        if (![self checkContinuityOfStoreModificationEvents:concurrentEvents]) {
            if (error) *error = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeDiscontinuousRevisions userInfo:nil];
            result = NO;
            return;
        }
    }];
    
    return result;
}

- (BOOL)checkModelVersionsOfStoreModificationEvents:(NSArray *)events
{
    // TODO: Need to implement model version checking
    return YES;
}

- (BOOL)checkAllDependenciesExistForStoreModificationEvents:(NSArray *)events
{
    __block BOOL result = YES;
    [eventManagedObjectContext performBlockAndWait:^{
        for (CDEStoreModificationEvent *event in events) {
            NSSet *otherStoreRevs = event.eventRevisionsOfOtherStores;
            for (CDEEventRevision *otherStoreRev in otherStoreRevs) {
                CDEStoreModificationEvent *dependency = [CDEStoreModificationEvent fetchStoreModificationEventForPersistentStoreIdentifier:otherStoreRev.persistentStoreIdentifier revisionNumber:otherStoreRev.revisionNumber inManagedObjectContext:event.managedObjectContext];
                if (!dependency) {
                    result = NO;
                    return;
                }
            }
        }
    }];
    return result;
}

- (BOOL)checkContinuityOfStoreModificationEvents:(NSArray *)events
{
    __block BOOL result = YES;
    [eventManagedObjectContext performBlockAndWait:^{
        NSSet *stores = [NSSet setWithArray:[events valueForKeyPath:@"eventRevision.persistentStoreIdentifier"]];
        NSArray *sortDescs = @[[NSSortDescriptor sortDescriptorWithKey:@"eventRevision.revisionNumber" ascending:YES]];
        for (NSString *persistentStoreId in stores) {
            NSPredicate *predicate = [NSPredicate predicateWithFormat:@"eventRevision.persistentStoreIdentifier = %@", persistentStoreId];
            NSArray *storeEvents = [events filteredArrayUsingPredicate:predicate];
            storeEvents = [storeEvents sortedArrayUsingDescriptors:sortDescs];
            
            CDEStoreModificationEvent *firstEvent = storeEvents[0];
            CDERevisionNumber revision = firstEvent.eventRevision.revisionNumber;
            for (CDEStoreModificationEvent *event in storeEvents) {
                CDERevisionNumber nextRevision = event.eventRevision.revisionNumber;
                if (nextRevision - revision > 1) {
                    result = NO;
                    return;
                }
                revision = nextRevision;
            }
        }
    }];
    return result;
}

#pragma mark Global Count

- (CDEGlobalCount)maximumGlobalCount
{
    __block long long maxCount = -1;
    [eventManagedObjectContext performBlockAndWait:^{
        NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"CDEStoreModificationEvent"];
        fetch.propertiesToFetch = @[@"globalCount"];
        
        NSArray *result = [eventManagedObjectContext executeFetchRequest:fetch error:NULL];
        if (!result) @throw [NSException exceptionWithName:CDEException reason:@"Failed to get global count" userInfo:nil];
        if (result.count == 0) return;
        
        NSNumber *max = [result valueForKeyPath:@"@max.globalCount"];
        maxCount = max.longLongValue;
    }];
    return maxCount;
}

#pragma mark Maximum (Latest) Revisions

- (CDERevisionSet *)revisionSetOfMostRecentEvents
{
    __block CDERevisionSet *set = nil;
    [eventManagedObjectContext performBlockAndWait:^{
        NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"CDEEventRevision"];
        request.predicate = [NSPredicate predicateWithFormat:@"storeModificationEvent != NIL"];
        
        NSError *error;
        NSArray *allRevisions = [eventManagedObjectContext executeFetchRequest:request error:&error];
        if (!allRevisions) @throw [NSException exceptionWithName:CDEException reason:@"Fetch of revisions failed" userInfo:nil];
        
        set = [[CDERevisionSet alloc] init];
        for (CDEEventRevision *eventRevision in allRevisions) {
            NSString *identifier = eventRevision.persistentStoreIdentifier;
            CDERevision *currentRecentRevision = [set revisionForPersistentStoreIdentifier:identifier];
            if (!currentRecentRevision || currentRecentRevision.revisionNumber < eventRevision.revisionNumber) {
                if (currentRecentRevision) [set removeRevision:currentRecentRevision];
                [set addRevision:eventRevision.revision];
            }
        }
    }];
    return set;
}

@end
