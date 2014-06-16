//
//  NSMapTable+CDEAdditions.m
//  Test App iOS
//
//  Created by Drew McCormack on 5/26/13.
//  Copyright (c) 2013 The Mental Faculty B.V. All rights reserved.
//

#import "NSMapTable+CDEAdditions.h"

@implementation NSMapTable (CDEAdditions)

+ (instancetype)cde_weakToStrongObjectsMapTable
{
    id result = nil;
    
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#if TARGET_OS_IPHONE
    result = [NSMapTable weakToStrongObjectsMapTable];
#else
    result = [NSMapTable respondsToSelector:@selector(weakToStrongObjectsMapTable)] ? [NSMapTable weakToStrongObjectsMapTable] : [NSMapTable mapTableWithWeakToStrongObjects];
#endif
#pragma clang diagnostic pop
    
    return result;
}

+ (instancetype)cde_strongToStrongObjectsMapTable
{
    id result = nil;
    
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#if TARGET_OS_IPHONE
    result = [NSMapTable strongToStrongObjectsMapTable];
#else
    result = [NSMapTable respondsToSelector:@selector(strongToStrongObjectsMapTable)] ? [NSMapTable strongToStrongObjectsMapTable] : [NSMapTable mapTableWithStrongToStrongObjects];
#endif
#pragma clang diagnostic pop
    
    return result;
}

- (void)cde_addEntriesFromMapTable:(NSMapTable *)otherTable
{
    for (id key in otherTable) {
        [self setObject:[otherTable objectForKey:key] forKey:key];
    }
}

- (NSArray *)cde_allValues
{
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:self.count];
    for (id key in self) {
        [result addObject:[self objectForKey:key]];
    }
    return result;
}

- (NSArray *)cde_allKeys
{
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:self.count];
    for (id key in self) {
        [result addObject:key];
    }
    return result;
}


@end
