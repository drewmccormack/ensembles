//
//  CDEObjectChange.m
//  Test App iOS
//
//  Created by Drew McCormack on 4/14/13.
//  Copyright (c) 2013 The Mental Faculty B.V. All rights reserved.
//

#import "CDEObjectChange.h"
#import "CDEStoreModificationEvent.h"
#import "CDEDefines.h"

@implementation CDEObjectChange

@dynamic type;
@dynamic globalIdentifier;
@dynamic storeModificationEvent;
@dynamic nameOfEntity;
@dynamic propertyChangeValues;

- (BOOL)validatePropertyChangeValues:(id *)value error:(NSError * __autoreleasing *)error
{
    if (self.type != CDEObjectChangeTypeDelete && *value == nil) {
        *error = [NSError errorWithDomain:CDEErrorDomain code:-1 userInfo:nil];
        return NO;
    }
    return YES;
}

- (CDEPropertyChangeValue *)propertyChangeValueForPropertyName:(NSString *)name
{
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"propertyName = %@", name];
    NSArray *values = [self.propertyChangeValues filteredArrayUsingPredicate:predicate];
    CDEPropertyChangeValue *value = values.lastObject;
    return value;
}

@end
