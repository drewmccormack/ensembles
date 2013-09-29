//
//  CDEStoreModificationEvent.m
//  Test App iOS
//
//  Created by Drew McCormack on 4/14/13.
//  Copyright (c) 2013 The Mental Faculty B.V. All rights reserved.
//

#import "CDEStoreModificationEvent.h"
#import "CDEDefines.h"
#import "CDEGlobalIdentifier.h"
#import "CDEEventRevision.h"
#import "CDERevisionSet.h"
#import "CDERevision.h"

@implementation CDEStoreModificationEvent

@dynamic type;
@dynamic timestamp;
@dynamic eventRevision;
@dynamic eventRevisionsOfOtherStores;
@dynamic modelVersion;
@dynamic objectChanges;
@dynamic globalCount;

#pragma mark - Revisions

- (CDERevisionSet *)revisionSet
{
    CDERevisionSet *set = [self revisionSetOfOtherStoresAtCreation];
    [set addRevision:self.eventRevision.revision];
    return set;
}

- (void)setRevisionSetOfOtherStoresAtCreation:(CDERevisionSet *)newSet
{
    NSSet *eventRevisions = [CDEEventRevision makeEventRevisionsForRevisionSet:newSet inManagedObjectContext:self.managedObjectContext];
    self.eventRevisionsOfOtherStores = eventRevisions;
}

- (CDERevisionSet *)revisionSetOfOtherStoresAtCreation
{
    CDERevisionSet *set = [[CDERevisionSet alloc] init];
    for (CDEEventRevision *rev in self.eventRevisionsOfOtherStores) {
        [set addRevision:rev.revision];
    }
    return set;
}


#pragma mark - Fetching

+ (instancetype)fetchStoreModificationEventForPersistentStoreIdentifier:(NSString *)persistentStoreId revisionNumber:(CDERevisionNumber)revision inManagedObjectContext:(NSManagedObjectContext *)context
{
    if (persistentStoreId == nil || revision < 0) return nil;
    
    NSFetchRequest *fetch = [[NSFetchRequest alloc] initWithEntityName:@"CDEStoreModificationEvent"];
    fetch.predicate = [NSPredicate predicateWithFormat:@"eventRevision.persistentStoreIdentifier = %@ && eventRevision.revisionNumber = %lld", persistentStoreId, revision];
    NSArray *events = [context executeFetchRequest:fetch error:NULL];
    NSAssert(events.count < 2, @"Multiple events with same revision");

    return events.lastObject;
}

+ (NSArray *)fetchStoreModificationEventsForPersistentStoreIdentifier:(NSString *)persistentStoreId sinceRevisionNumber:(CDERevisionNumber)revision inManagedObjectContext:(NSManagedObjectContext *)context
{
    NSFetchRequest *fetch = [[NSFetchRequest alloc] initWithEntityName:@"CDEStoreModificationEvent"];
    fetch.predicate = [NSPredicate predicateWithFormat:@"eventRevision.persistentStoreIdentifier = %@ && eventRevision.revisionNumber > %lld", persistentStoreId, revision];
    NSArray *events = [context executeFetchRequest:fetch error:NULL];
    return events;
}

+ (void)prefetchRelatedObjectsForStoreModificationEvents:(NSArray *)storeModEvents
{
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"CDEStoreModificationEvent"];
    fetch.predicate = [NSPredicate predicateWithFormat:@"SELF IN %@", storeModEvents];
    fetch.relationshipKeyPathsForPrefetching = @[@"objectChanges", @"objectChanges.globalIdentifier", @"eventRevision", @"eventRevisionsOfOtherStores"];
    NSManagedObjectContext *context = [storeModEvents.lastObject managedObjectContext];
    [context executeFetchRequest:fetch error:NULL];
}

@end
