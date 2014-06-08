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
        [result addObject:(block(object) ? : [NSNull null])];
    }
    return result;
}

@end


@implementation NSData (CDEFoundationAdditions)

- (NSString *)cde_base64String
{
#if (__IPHONE_OS_VERSION_MIN_REQUIRED < 70000) && (__MAC_OS_X_VERSION_MIN_REQUIRED < 1090)
    NSString *string = [self base64Encoding];
#else
    NSString *string = [self base64EncodedStringWithOptions:0];
#endif
    return string;
}

@end
