//
//  CDERevision.m
//  Ensembles
//
//  Created by Drew McCormack on 10/08/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import "CDERevision.h"

@implementation CDERevision

- (instancetype)initWithPersistentStoreIdentifier:(NSString *)identifier revisionNumber:(CDERevisionNumber)number globalCount:(CDEGlobalCount)newCount
{
    self = [super init];
    if (self) {
        self.persistentStoreIdentifier = identifier;
        self.revisionNumber = number;
        self.globalCount = newCount;
    }
    return self;
}

- (instancetype)initWithPersistentStoreIdentifier:(NSString *)identifier revisionNumber:(CDERevisionNumber)number
{
    return [self initWithPersistentStoreIdentifier:identifier revisionNumber:number globalCount:-1];
}

- (instancetype)init
{
    return [self initWithPersistentStoreIdentifier:nil revisionNumber:-1];
}

- (id <NSObject, NSCopying>)uniqueIdentifier
{
    return [NSString stringWithFormat:@"%li_%li_%@", (long)self.globalCount, (long)self.revisionNumber, self.persistentStoreIdentifier ? : @""];
}

- (NSComparisonResult)compare:(CDERevision *)other
{
    NSParameterAssert(other != nil);
    if (self.globalCount < other.globalCount)
        return NSOrderedAscending;
    else if (self.revisionNumber > other.revisionNumber)
        return NSOrderedDescending;
    else {
        if (self.revisionNumber < other.revisionNumber)
            return NSOrderedAscending;
        else if (self.revisionNumber > other.revisionNumber)
            return NSOrderedDescending;
        return [self.persistentStoreIdentifier compare:other.persistentStoreIdentifier];
    }
}

- (BOOL)isEqual:(CDERevision *)other
{
    if (![other isKindOfClass:[CDERevision class]]) return NO;
    return [self.uniqueIdentifier isEqual:other.uniqueIdentifier];
}

- (NSUInteger)hash
{
    return [self.uniqueIdentifier hash];
}

@end
