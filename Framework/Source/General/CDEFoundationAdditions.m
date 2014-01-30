//
//  CDEFoundationAdditions.m
//  Test App iOS
//
//  Created by Drew McCormack on 4/19/13.
//  Copyright (c) 2013 The Mental Faculty B.V. All rights reserved.
//

#import "CDEFoundationAdditions.h"

@implementation NSArray (CDEFoundationAdditions)

-(void)cde_enumerateObjectsDrainingEveryIterations:(NSUInteger)iterationsBetweenDrains usingBlock:(void (^)(id object, NSUInteger index, BOOL *stop))block
{
    NSUInteger total = 0;
    NSUInteger count = self.count;
    NSUInteger numberOfChunks = (count / MAX(1,iterationsBetweenDrains) + 1);
    BOOL stop = NO;
    for ( NSUInteger chunk = 0; chunk < numberOfChunks; chunk++ ) {
        @autoreleasepool {
            for ( NSUInteger i = chunk*iterationsBetweenDrains; i < MIN(count, (chunk+1)*iterationsBetweenDrains); i++ ) {
                id object = self[i];
                block(object, total, &stop);
                if ( stop ) break;
                total++;
            }
        }
        if ( stop ) break;
    }
}

- (NSArray *)cde_arrayByTransformingObjectsWithBlock:(id(^)(id))block
{
    NSMutableArray *result = [[NSMutableArray alloc] init];
    for (id object in self) {
        [result addObject:block(object)];
    }
    return result;
}

@end
