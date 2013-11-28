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

@implementation CDEBaselineConsolidator

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
    NSManagedObjectContext *childStoreContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    [childStoreContext performBlock:^{
        childStoreContext.parentContext = self.eventStore.managedObjectContext;
        
        // Fetch existing baselines, ordered beginning with most recent
        NSError *error = nil;
        NSFetchRequest *fetch = [self.class baselineFetchRequest];
        NSArray *sortDescriptors = @[
            [NSSortDescriptor sortDescriptorWithKey:@"globalCount" ascending:NO],
            [NSSortDescriptor sortDescriptorWithKey:@"timestamp" ascending:NO],
            [NSSortDescriptor sortDescriptorWithKey:@"eventRevision.persistentStoreIdentifier" ascending:NO]
        ];
        fetch.sortDescriptors = sortDescriptors;
        NSArray *baselineEvents = [childStoreContext executeFetchRequest:fetch error:&error];
        
        // Eliminate any baselines that are subsets of other baselines
        NSMutableSet *baselinesToEliminate = [NSMutableSet setWithCapacity:baselineEvents.count];
        for (CDEStoreModificationEvent *baselineEvent in baselineEvents) {
            for (CDEStoreModificationEvent *otherEvent in baselineEvents) {
                if (baselineEvent == otherEvent) continue;
                CDERevisionSet *baselineSet = baselineEvent.revisionSet;
                CDERevisionSet *otherSet = otherEvent.revisionSet;
                if ([baselineSet compare:otherSet] == NSOrderedDescending) [baselinesToEliminate addObject:otherSet];
            }
        }
    }];
}

- (CDEStoreModificationEvent *)mergedBaselineFromBaselineEvents:(NSArray *)baselines
{
    return nil;
}

@end
