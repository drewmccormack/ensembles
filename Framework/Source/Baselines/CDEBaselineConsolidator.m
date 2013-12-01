//
//  CDEBaselineConsolidator.m
//  Ensembles Mac
//
//  Created by Drew McCormack on 27/11/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import "CDEBaselineConsolidator.h"
#import "CDEFoundationAdditions.h"
#import "NSMapTable+CDEAdditions.h"
#import "CDEEventStore.h"
#import "CDEStoreModificationEvent.h"
#import "CDERevisionSet.h"
#import "CDEObjectChange.h"
#import "CDEGlobalIdentifier.h"
#import "CDEPropertyChangeValue.h"

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
        CDEStoreModificationEvent *newBaseline = [self mergedBaselineFromBaselineEvents:survivingBaselines error:&error];
        if (!newBaseline) {
            [self failWithCompletion:completion error:error];
            return;
        }
        
        // Delete old baselines
        [survivingBaselines removeObject:newBaseline];
        for (CDEStoreModificationEvent *baseline in survivingBaselines) {
            [context deleteObject:baseline];
        }
        
        // Save
        if (context.hasChanges) success = [context save:&error];
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

- (CDEStoreModificationEvent *)mergedBaselineFromBaselineEvents:(NSArray *)baselines error:(NSError * __autoreleasing *)error
{
    if (baselines.count == 0) return nil;
    if (baselines.count == 1) return baselines.lastObject;
    
    // Change the first baseline into our new baseline by assigning a different unique id
    CDEStoreModificationEvent *firstBaseline = baselines.firstObject;
    firstBaseline.uniqueIdentifier = [[NSProcessInfo processInfo] globallyUniqueString];
    firstBaseline.timestamp = [NSDate timeIntervalSinceReferenceDate];
    
    // Retrieve all global identifiers. Map global ids to object changes.
    [CDEStoreModificationEvent prefetchRelatedObjectsForStoreModificationEvents:@[firstBaseline]];
    NSMapTable *objectChangesByGlobalId = [NSMapTable strongToStrongObjectsMapTable];
    NSSet *objectChanges = firstBaseline.objectChanges;
    for (CDEObjectChange *change in objectChanges) {
        [objectChangesByGlobalId setObject:change forKey:change.globalIdentifier];
    }
    
    // Get other baselines
    NSMutableArray *otherBaselines = [baselines mutableCopy];
    [otherBaselines removeObject:firstBaseline];
    [CDEStoreModificationEvent prefetchRelatedObjectsForStoreModificationEvents:otherBaselines];
    
    // Apply changes from others
    for (CDEStoreModificationEvent *baseline in otherBaselines) {
        [baseline.objectChanges.allObjects cde_enumerateObjectsDrainingEveryIterations:100 usingBlock:^(CDEObjectChange *change, NSUInteger index, BOOL *stop) {
            CDEObjectChange *existingChange = [objectChangesByGlobalId objectForKey:change.globalIdentifier];
            if (!existingChange) {
                // Move change to new baseline
                change.storeModificationEvent = firstBaseline;
                [objectChangesByGlobalId setObject:change forKey:change.globalIdentifier];
            }
            else {
                [self mergeValuesIntoObjectChange:existingChange fromObjectChange:change];
            }
        }];
    }
    
    return firstBaseline;
}

- (void)mergeValuesIntoObjectChange:(CDEObjectChange *)existingChange fromObjectChange:(CDEObjectChange *)change
{
    // Check if there are new property values to include, or values to merge
    NSSet *existingNames = [[NSSet alloc] initWithArray:[existingChange.propertyChangeValues valueForKeyPath:@"propertyName"]];
    
    NSMutableArray *addedPropertyChangeValues = nil;
    for (CDEPropertyChangeValue *propertyValue in change.propertyChangeValues) {
        NSString *propertyName = propertyValue.propertyName;
        
        // If this property name is not already present, just copy it in
        if (![existingNames containsObject:propertyName]) {
            if (!addedPropertyChangeValues) addedPropertyChangeValues = [[NSMutableArray alloc] initWithCapacity:10];
            [addedPropertyChangeValues addObject:propertyValue];
            continue;
        }
        
        
        // If it is a to-many relationship, take the union
        BOOL isToMany = propertyValue.type == CDEPropertyChangeTypeToManyRelationship;
        isToMany = isToMany || propertyValue.type == CDEPropertyChangeTypeOrderedToManyRelationship;
        if (isToMany) {
            CDEPropertyChangeValue *existingValue = [existingChange propertyChangeValueForPropertyName:propertyName];
            [self mergeToManyRelationshipIntoValue:existingValue fromValue:propertyValue];
        }
    }
    
    if (addedPropertyChangeValues.count > 0) {
        existingChange.propertyChangeValues = [existingChange.propertyChangeValues arrayByAddingObjectsFromArray:addedPropertyChangeValues];
    }
}

- (void)mergeToManyRelationshipIntoValue:(CDEPropertyChangeValue *)existingValue fromValue:(CDEPropertyChangeValue *)propertyValue
{
    NSSet *originalAddedIdentifiers = existingValue.addedIdentifiers;
    if ([propertyValue.addedIdentifiers isEqualToSet:originalAddedIdentifiers]) return;

    // Add the missing identifiers
    existingValue.addedIdentifiers = [originalAddedIdentifiers setByAddingObjectsFromSet:propertyValue.addedIdentifiers];
    if (propertyValue.type != CDEPropertyChangeTypeOrderedToManyRelationship) return;
    
    // If it is an ordered to-many, update ordering. Order new identifiers after the existing ones.
    NSMutableDictionary *newMovedIdentifiersByIndex = [[NSMutableDictionary alloc] initWithDictionary:existingValue.movedIdentifiersByIndex];
    NSUInteger newIndex = existingValue.movedIdentifiersByIndex.count;
    for (NSUInteger oldIndex = 0; oldIndex < propertyValue.movedIdentifiersByIndex.count; oldIndex++) {
        NSString *identifier = propertyValue.movedIdentifiersByIndex[@(oldIndex)];
        if (!identifier || [originalAddedIdentifiers containsObject:identifier]) continue;
        newMovedIdentifiersByIndex[@(newIndex++)] = identifier;
    }
    
    existingValue.movedIdentifiersByIndex = newMovedIdentifiersByIndex;
}

@end
