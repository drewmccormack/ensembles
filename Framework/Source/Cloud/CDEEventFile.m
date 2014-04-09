//
//  CDEEventFile.m
//  Ensembles Mac
//
//  Created by Drew McCormack on 08/04/14.
//  Copyright (c) 2014 Drew McCormack. All rights reserved.
//

#import "CDEEventFile.h"
#import "CDEStoreModificationEvent.h"

@implementation CDEEventFile 

@synthesize preferredFilename = preferredFilename;
@synthesize aliases = aliases;
@synthesize eventShouldBeUnique = eventShouldBeUnique;
@synthesize baseline = baseline;
@synthesize persistentStoreIdentifier;
@synthesize persistentStorePrefix;
@synthesize uniqueIdentifier;
@synthesize globalCount;
@synthesize revisionNumber;

- (id)initWithStoreModificationEvent:(CDEStoreModificationEvent *)event
{
    self = [super init];
    if (self) {
        baseline = event.type == CDEStoreModificationEventTypeBaseline;
        globalCount = event.globalCount;
        uniqueIdentifier = event.uniqueIdentifier;
        revisionNumber = event.eventRevision.revisionNumber;
        persistentStoreIdentifier = event.eventRevision.persistentStoreIdentifier;
        persistentStorePrefix = [persistentStoreIdentifier substringToIndex:MIN(8,persistentStoreIdentifier.length)];
        eventShouldBeUnique = YES;
    }
    return self;
}

- (id)initWithFilename:(NSString *)filename
{
    self = [super init];
    if (self) {
        NSArray *components = [[filename stringByDeletingPathExtension] componentsSeparatedByString:@"_"];
        if (components.count == 3 && [components[2] length] == 8) {
            baseline = YES;
            globalCount = [components[0] longLongValue];
            revisionNumber = -1;
            persistentStoreIdentifier = nil;
            persistentStorePrefix = components[2];
            uniqueIdentifier = components[1];
            eventShouldBeUnique = YES;
        }
        else if (components.count == 3) {
            baseline = NO;
            globalCount = [components[0] longLongValue];
            revisionNumber = [components[2] longLongValue];
            persistentStoreIdentifier = components[1];
            persistentStorePrefix = [persistentStoreIdentifier substringToIndex:MIN(8, persistentStoreIdentifier.length)];
            uniqueIdentifier = nil;
            eventShouldBeUnique = YES;
        }
        else if (components.count == 2) {
            // Legacy baseline
            baseline = YES;
            globalCount = [components[0] longLongValue];
            revisionNumber = -1;
            persistentStoreIdentifier = nil;
            persistentStorePrefix = nil;
            uniqueIdentifier = components[1];
            eventShouldBeUnique = NO;
        }
        else {
            self = nil;
        }
    }
    return self;
}

- (NSPredicate *)eventFetchPredicate
{
    NSPredicate *predicate = nil;
    if (baseline) {
        NSPredicate *basePredicate = [NSPredicate predicateWithFormat:@"type = %d AND globalCount = %lld AND uniqueIdentifier = %@", CDEStoreModificationEventTypeBaseline, globalCount, uniqueIdentifier];
        if (persistentStorePrefix) {
            NSPredicate *storePredicate = [NSPredicate predicateWithFormat:@"eventRevision.persistentStoreIdentifier BEGINSWITH %@", persistentStorePrefix];
            predicate = [NSCompoundPredicate andPredicateWithSubpredicates:@[basePredicate, storePredicate]];
        }
        else {
            predicate = basePredicate;
        }
    }
    else {
        predicate = [NSPredicate predicateWithFormat:@"(type = %d OR type = %d) AND globalCount = %lld AND eventRevision.persistentStoreIdentifier = %@ AND eventRevision.revisionNumber = %lld", CDEStoreModificationEventTypeSave, CDEStoreModificationEventTypeMerge, globalCount, persistentStoreIdentifier, revisionNumber];
    }
    return predicate;
}

- (NSString *)preferredFilename
{
    NSString *result = nil;
    if (baseline) {
        NSString *storeSubstring = [persistentStoreIdentifier substringToIndex:8];
        result = [NSString stringWithFormat:@"%lli_%@_%@.cdeevent", globalCount, uniqueIdentifier, storeSubstring];
    }
    else {
        result = [NSString stringWithFormat:@"%lli_%@_%lli.cdeevent", globalCount, persistentStoreIdentifier, revisionNumber];
    }
    return result;
}

- (NSSet *)aliases
{
    NSSet *result = nil;
    if (baseline) {
        NSString *storeSubstring = [persistentStoreIdentifier substringToIndex:8];
        NSString *s1 = [NSString stringWithFormat:@"%lli_%@_%@.cdeevent", globalCount, uniqueIdentifier, storeSubstring];
        NSString *s2 = [NSString stringWithFormat:@"%lli_%@.cdeevent", globalCount, uniqueIdentifier];
        result = [NSSet setWithObjects:s1, s2, nil];
    }
    else {
        NSString *s1 = [NSString stringWithFormat:@"%lli_%@_%lli.cdeevent", globalCount, persistentStoreIdentifier, revisionNumber];
        result = [NSSet setWithObject:s1];
    }
    return result;
}


@end
