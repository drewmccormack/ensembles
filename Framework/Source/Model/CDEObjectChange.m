//
//  CDEObjectChange.m
//  Test App iOS
//
//  Created by Drew McCormack on 4/14/13.
//  Copyright (c) 2013 The Mental Faculty B.V. All rights reserved.
//

#import "CDEObjectChange.h"
#import "CDEDefines.h"
#import "CDEStoreModificationEvent.h"
#import "CDEPropertyChangeValue.h"

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


#pragma mark Merging

- (void)mergeValuesFromSubordinateObjectChange:(CDEObjectChange *)change
{
    NSSet *existingNames = [[NSSet alloc] initWithArray:[self.propertyChangeValues valueForKeyPath:@"propertyName"]];
    
    NSMutableArray *addedPropertyChangeValues = nil;
    for (CDEPropertyChangeValue *propertyValue in change.propertyChangeValues) {
        NSString *propertyName = propertyValue.propertyName;
        
        // If this property name is not already present, just copy it in
        if (![existingNames containsObject:propertyName]) {
            if (!addedPropertyChangeValues) addedPropertyChangeValues = [[NSMutableArray alloc] initWithCapacity:10];
            [addedPropertyChangeValues addObject:propertyValue];
            continue;
        }
        
        // If it is a to-many relationship, take the union
        BOOL isToMany = propertyValue.type == CDEPropertyChangeTypeToManyRelationship;
        isToMany = isToMany || propertyValue.type == CDEPropertyChangeTypeOrderedToManyRelationship;
        if (isToMany) {
            CDEPropertyChangeValue *existingValue = [self propertyChangeValueForPropertyName:propertyName];
            [existingValue mergeToManyRelationshipFromPropertyChangeValue:propertyValue];
        }
    }
    
    if (addedPropertyChangeValues.count > 0) {
        self.propertyChangeValues = [self.propertyChangeValues arrayByAddingObjectsFromArray:addedPropertyChangeValues];
    }
}

@end
