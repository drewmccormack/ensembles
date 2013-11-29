//
//  CDEBaselineConsolidator.m
//  Ensembles Mac
//
//  Created by Drew McCormack on 27/11/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import "CDEBaselineConsolidator.h"
#import "CDEEventStore.h"
#import "CDEStoreModificationEvent.h"
#import "CDERevisionSet.h"

@implementation CDEBaselineConsolidator {
}

@synthesize eventStore = eventStore;

- (id)initWithEventStore:(CDEEventStore *)newEventStore
{
    self = [super init];
    if (self) {
        eventStore = newEventStore;
    }
    return self;
}

+ (NSFetchRequest *)baselineFetchRequest
{
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"CDEStoreModificationEvent"];
    fetch.predicate = [NSPredicate predicateWithFormat:@"type = %d", CDEStoreModificationEventTypeBaseline];
    return fetch;
}

- (BOOL)baselineNeedsConsolidation
{
    __block BOOL result = NO;
    [self.eventStore.managedObjectContext performBlockAndWait:^{
        NSError *error = nil;
        NSFetchRequest *fetch = [self.class baselineFetchRequest];
        NSUInteger count = [self.eventStore.managedObjectContext countForFetchRequest:fetch error:&error];
        if (error) {
            CDELog(CDELoggingLevelError, @"Failed to get baseline count: %@", error);
        }
        else {
            result = count > 1;
        }
    }];
    return result;
}

- (void)consolidateBaselineWithCompletion:(CDECompletionBlock)completion
{
    NSManagedObjectContext *context = self.eventStore.managedObjectContext;
    [context performBlock:^{
        // Fetch existing baselines, ordered beginning with most recent
        NSError *error = nil;
        NSArray *baselineEvents = [self baselinesDecreasingInRecencyInManagedObjectContext:context error:&error];
        if (!baselineEvents) {
            [self failWithCompletion:completion error:error];
            return;
        }
        
        // Determine which baselines should be eliminated
        NSSet *baselinesToEliminate = [self redundantBaselinesInBaselines:baselineEvents];
        
        // Delete redundant baselines
        [CDEStoreModificationEvent prefetchRelatedObjectsForStoreModificationEvents:baselinesToEliminate.allObjects];
        for (CDEStoreModificationEvent *baseline in baselinesToEliminate) {
            [context deleteObject:baseline];
        }
        
        // Save
        BOOL success = [context save:&error];
        if (!success) {
            [self failWithCompletion:completion error:error];
            return;
        }
        
        // Merge surviving baselines
        NSMutableArray *survivingBaselines = [NSMutableArray arrayWithArray:baselineEvents];
        [survivingBaselines removeObjectsInArray:baselinesToEliminate.allObjects];
        CDEStoreModificationEvent *newBaseline = [self mergedBaselineFromBaselineEvents:survivingBaselines];
        [survivingBaselines removeObject:newBaseline];
        
        // Delete old baselines
        for (CDEStoreModificationEvent *baseline in survivingBaselines) {
            [context deleteObject:baseline];
        }
        
        // Save
        success = [context save:&error];
        if (!success) {
            [self failWithCompletion:completion error:error];
            return;
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(nil);
        });
    }];
}

- (void)failWithCompletion:(CDECompletionBlock)completion error:(NSError *)error
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (completion) completion(error);
    });
}

- (NSArray *)baselinesDecreasingInRecencyInManagedObjectContext:(NSManagedObjectContext *)context error:(NSError * __autoreleasing *)error
{
    NSFetchRequest *fetch = [self.class baselineFetchRequest];
    NSArray *sortDescriptors = @[
        [NSSortDescriptor sortDescriptorWithKey:@"globalCount" ascending:NO],
        [NSSortDescriptor sortDescriptorWithKey:@"timestamp" ascending:NO],
        [NSSortDescriptor sortDescriptorWithKey:@"eventRevision.persistentStoreIdentifier" ascending:NO]
    ];
    fetch.sortDescriptors = sortDescriptors;
    NSArray *baselineEvents = [context executeFetchRequest:fetch error:error];
    return baselineEvents;
}

- (NSSet *)redundantBaselinesInBaselines:(NSArray *)allBaselines
{
    NSMutableSet *baselinesToEliminate = [NSMutableSet setWithCapacity:allBaselines.count];
    for (CDEStoreModificationEvent *firstEvent in allBaselines) {
        for (CDEStoreModificationEvent *secondEvent in allBaselines) {
            if (firstEvent == secondEvent) continue;
            CDERevisionSet *firstSet = firstEvent.revisionSet;
            CDERevisionSet *secondSet = secondEvent.revisionSet;
            if ([firstSet compare:secondSet] == NSOrderedDescending) [baselinesToEliminate addObject:secondSet];
        }
    }
    return baselinesToEliminate;
}

- (CDEStoreModificationEvent *)mergedBaselineFromBaselineEvents:(NSArray *)baselines
{
    return nil;
}

@end
