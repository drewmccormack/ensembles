//
//  NSMapTable+CDEAdditions.m
//  Test App iOS
//
//  Created by Drew McCormack on 5/26/13.
//  Copyright (c) 2013 The Mental Faculty B.V. All rights reserved.
//

#import "NSMapTable+CDEAdditions.h"

@implementation NSMapTable (CDEAdditions)

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

@end
