//
//  NSManagedObjectModel+CDEAdditions.m
//  Ensembles
//
//  Created by Drew McCormack on 08/11/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import "NSManagedObjectModel+CDEAdditions.h"
#import "CDEDefines.h"

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

- (NSString *)cde_entityHashesPropertyList
{
    NSString *error = nil;
    NSData *data = [NSPropertyListSerialization dataFromPropertyList:self.entityVersionHashesByName format:NSPropertyListXMLFormat_v1_0 errorDescription:&error];
    if (!data) CDELog(CDELoggingLevelError, @"Error generating property list: %@", error);
    
    NSString *string = nil;
    if (data) string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    
    return string;
}

+ (NSDictionary *)cde_entityHashesByNameFromPropertyList:(NSString *)propertyList
{
    NSData *data = [propertyList dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return nil;
    
    NSString *error;
    NSPropertyListFormat format;
    NSDictionary *entitiesByName = [NSPropertyListSerialization propertyListFromData:data mutabilityOption:NSPropertyListImmutable format:&format errorDescription:&error];
    if (!entitiesByName) CDELog(CDELoggingLevelError, @"Error reading property list: %@", error);
    
    return entitiesByName;
}

@end
