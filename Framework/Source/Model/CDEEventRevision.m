//
//  CDERevision.m
//  Ensembles
//
//  Created by Drew McCormack on 09/07/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import "CDEEventRevision.h"
#import "CDEStoreModificationEvent.h"
#import "CDERevision.h"
#import "CDERevisionSet.h"

@implementation CDEEventRevision

@dynamic revisionNumber;
@dynamic persistentStoreIdentifier;
@dynamic storeModificationEvent;
@dynamic storeModificationEventForOtherStores;

+ (instancetype)makeEventRevisionForPersistentStoreIdentifier:(NSString *)identifier revisionNumber:(CDERevisionNumber)revision inManagedObjectContext:(NSManagedObjectContext *)context
{
    NSParameterAssert(identifier != nil);
    NSParameterAssert(context != nil);
    
    CDEEventRevision *newObject = [NSEntityDescription insertNewObjectForEntityForName:@"CDEEventRevision" inManagedObjectContext:context];
    newObject.revisionNumber = revision;
    newObject.persistentStoreIdentifier = identifier;
    
    return newObject;
}

+ (NSSet *)fetchPersistentStoreIdentifiersInManagedObjectContext:(NSManagedObjectContext *)context
{
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"CDEEventRevision"];
    NSError *error = nil;
    NSArray *result = [context executeFetchRequest:fetch error:&error];
    if (!result) {
        CDELog(CDELoggingLevelError, @"Error in fetching: %@", error);
        return nil;
    }
    return [NSSet setWithArray:[result valueForKeyPath:@"persistentStoreIdentifier"]];
}

- (CDERevision *)revision
{
    if (self.storeModificationEvent)
        return [[CDERevision alloc] initWithPersistentStoreIdentifier:self.persistentStoreIdentifier revisionNumber:self.revisionNumber globalCount:self.storeModificationEvent.globalCount];
    else if (self.storeModificationEventForOtherStores)
        return [[CDERevision alloc] initWithPersistentStoreIdentifier:self.persistentStoreIdentifier revisionNumber:self.revisionNumber globalCount:self.storeModificationEventForOtherStores.globalCount];
    else
        return [[CDERevision alloc] initWithPersistentStoreIdentifier:self.persistentStoreIdentifier revisionNumber:self.revisionNumber];
}

+ (NSSet *)makeEventRevisionsForRevisionSet:(CDERevisionSet *)revisionSet inManagedObjectContext:(NSManagedObjectContext *)context
{
    NSMutableSet *eventRevisions = [[NSMutableSet alloc] initWithCapacity:revisionSet.numberOfRevisions];
    for (CDERevision *revision in revisionSet.revisions) {
        CDEEventRevision *eventRevision = [self makeEventRevisionForPersistentStoreIdentifier:revision.persistentStoreIdentifier revisionNumber:revision.revisionNumber inManagedObjectContext:context];
        [eventRevisions addObject:eventRevision];
    }
    return eventRevisions;
}

@end
