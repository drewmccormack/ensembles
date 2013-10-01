//
//  CDEDirectory.m
//  Ensembles
//
//  Created by Drew McCormack on 4/12/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import "CDECloudDirectory.h"

@implementation CDECloudDirectory

- (NSString *)description
{
    NSMutableString *result = [NSMutableString string];
    [result appendFormat:@"%@\r", super.description];
    NSArray *keys = @[@"path", @"name", @"contents"];
    for (NSString *key in keys) {
        [result appendFormat:@"%@: %@; \r", key, [[self valueForKey:key] description]];
    }
    return result;
}

@end
