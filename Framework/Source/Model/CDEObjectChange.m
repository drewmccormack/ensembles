//
//  CDEObjectChange.m
//  Test App iOS
//
//  Created by Drew McCormack on 4/14/13.
//  Copyright (c) 2013 The Mental Faculty B.V. All rights reserved.
//

#import "CDEObjectChange.h"
#import "CDEDefines.h"
#import "CDEDataFile.h"
#import "CDEStoreModificationEvent.h"
#import "CDEPropertyChangeValue.h"

@implementation CDEObjectChange

@dynamic type;
@dynamic globalIdentifier;
@dynamic storeModificationEvent;
@dynamic nameOfEntity;
@dynamic propertyChangeValues;
@dynamic dataFiles;

- (BOOL)validatePropertyChangeValues:(id *)value error:(NSError * __autoreleasing *)error
{
    if (self.type != CDEObjectChangeTypeDelete && *value == nil) {
        if (error) *error = [NSError errorWithDomain:CDEErrorDomain code:-1 userInfo:nil];
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

- (void)setPropertyChangeValues:(NSArray *)newValues
{
    [self willChangeValueForKey:@"propertyChangeValues"];
    [self setPrimitiveValue:newValues forKey:@"propertyChangeValues"];
    [self didChangeValueForKey:@"propertyChangeValues"];
    [self updateDataFiles];
}


#pragma mark Data Files

- (void)updateDataFiles
{
    NSMutableSet *newFilenames = nil;
    for (CDEPropertyChangeValue *value in self.propertyChangeValues) {
        if (value.filename) {
            if (!newFilenames) newFilenames = [[NSMutableSet alloc] init];
            [newFilenames addObject:value.filename];
        }
    }
    
    if (self.dataFiles.count == 0 && newFilenames.count == 0) return;
    
    NSArray *orderedFiles = self.dataFiles.allObjects;
    NSDictionary *oldFilesByName = [[NSDictionary alloc] initWithObjects:orderedFiles forKeys:[orderedFiles valueForKeyPath:@"filename"]];
    NSSet *oldFilenames = [[NSSet alloc] initWithArray:oldFilesByName.allKeys];
    NSMutableSet *addedFilenames = [newFilenames mutableCopy];
    [addedFilenames minusSet:oldFilenames];
    for (NSString *filename in addedFilenames) {
        CDEDataFile *file = [NSEntityDescription insertNewObjectForEntityForName:@"CDEDataFile" inManagedObjectContext:self.managedObjectContext];
        file.filename = filename;
        file.objectChange = self;
    }
    
    NSMutableSet *removeFilenames = [oldFilenames mutableCopy];
    [removeFilenames minusSet:newFilenames];
    for (NSString *filename in removeFilenames) {
        CDEDataFile *file = oldFilesByName[filename];
        [self.managedObjectContext deleteObject:file];
    }
}


#pragma mark Merging

- (void)mergeValuesFromSubordinateObjectChange:(CDEObjectChange *)change
{
    NSDictionary *existingPropertiesByName = [[NSDictionary alloc] initWithObjects:self.propertyChangeValues forKeys:[self.propertyChangeValues valueForKeyPath:@"propertyName"]];
    
    NSMutableArray *addedPropertyChangeValues = nil;
    for (CDEPropertyChangeValue *propertyValue in change.propertyChangeValues) {
        NSString *propertyName = propertyValue.propertyName;
        CDEPropertyChangeValue *existingValue = existingPropertiesByName[propertyName];
        
        // If this property name is not already present, just copy it in
        if (nil == existingValue) {
            if (!addedPropertyChangeValues) addedPropertyChangeValues = [[NSMutableArray alloc] initWithCapacity:10];
            [addedPropertyChangeValues addObject:propertyValue];
            continue;
        }
        
        // If it is a to-many relationship, take the union
        BOOL isToMany = propertyValue.type == CDEPropertyChangeTypeToManyRelationship;
        isToMany = isToMany || propertyValue.type == CDEPropertyChangeTypeOrderedToManyRelationship;
        if (isToMany) {
            [existingValue mergeToManyRelationshipFromSubordinatePropertyChangeValue:propertyValue];
        }
    }
    
    if (addedPropertyChangeValues.count > 0) {
        self.propertyChangeValues = [self.propertyChangeValues arrayByAddingObjectsFromArray:addedPropertyChangeValues];
    }
}

@end
