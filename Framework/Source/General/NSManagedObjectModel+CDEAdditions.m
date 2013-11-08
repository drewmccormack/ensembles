//
//  NSManagedObjectModel+CDEAdditions.m
//  Ensembles Mac
//
//  Created by Drew McCormack on 08/11/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import "NSManagedObjectModel+CDEAdditions.h"

@implementation NSManagedObjectModel (CDEAdditions)

- (NSString *)cde_modelHash
{
    NSDictionary *entityHashesByName = [self entityVersionHashesByName];
    NSMutableString *result = [[NSMutableString alloc] init];
    NSArray *sortedNames = [entityHashesByName.allKeys sortedArrayUsingSelector:@selector(compare:)];
    [sortedNames enumerateObjectsUsingBlock:^(NSString *entityName, NSUInteger index, BOOL *stop) {
        NSString *separator = index > 0 ? @"__" : @"";
        NSString *entityString = [NSString stringWithFormat:@"%@%@_%@", separator, entityName, entityHashesByName[entityName]];
        [result appendString:entityString];
    }];
    return result;
}

@end
