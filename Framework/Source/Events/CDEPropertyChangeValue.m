//
//  CDEPropertyChangeValue.m
//  Test App iOS
//
//  Created by Drew McCormack on 4/20/13.
//  Copyright (c) 2013 The Mental Faculty B.V. All rights reserved.
//

#import "CDEPropertyChangeValue.h"
#import "CDEDefines.h"

@interface CDEPropertyChangeValue ()

@property (nonatomic, readwrite) NSManagedObjectID *objectID;
@property (nonatomic, readwrite) NSString *propertyName;
@property (nonatomic, readwrite) CDEPropertyChangeType type;

@end


@implementation CDEPropertyChangeValue

+ (NSArray *)propertyChangesForObject:(NSManagedObject *)object propertyNames:(id)names
{
    NSMutableArray *propertyChanges = [[NSMutableArray alloc] initWithCapacity:[names count]];
    NSEntityDescription *entity = object.entity;
    
    for (NSString *propertyName in names) {
        NSPropertyDescription *propertyDesc = entity.propertiesByName[propertyName];
        CDEPropertyChangeValue *change = [[CDEPropertyChangeValue alloc] initWithObject:object propertyDescription:propertyDesc];
        [propertyChanges addObject:change];
    }
    
    return propertyChanges;
}

- (instancetype)initWithObject:(NSManagedObject *)object propertyDescription:(NSPropertyDescription *)propertyDesc
{
    NSAssert(!object.objectID.isTemporaryID, @"Object has a temporary id in initWithObject: of CDEPropertyChangeValue");
    
    self = [self initWithType:CDEPropertyChangeTypeAttribute propertyName:propertyDesc.name];
    if (self) {
        self.objectID = object.objectID;
        
        id newValue = [object valueForKey:propertyDesc.name];
        if ([propertyDesc isKindOfClass:[NSAttributeDescription class]]) {
            [self storeAttributeChangeForDescription:(id)propertyDesc newValue:newValue];
        }
        else if ([propertyDesc isKindOfClass:[NSRelationshipDescription class]] && [(NSRelationshipDescription *)propertyDesc isToMany]) {
            id committed = nil;
            if (object.changedValues.count != 0) {
                NSDictionary *committedValues = [object committedValuesForKeys:@[propertyDesc.name]];
                committed = committedValues[propertyDesc.name];

            }

            NSRelationshipDescription *relationshipDescription = (NSRelationshipDescription *)propertyDesc;
            if (relationshipDescription.isOrdered) {
                [self storeOrderedToManyRelationshipChangeForDescription:relationshipDescription committedValue:committed newValue:newValue];
            } else {
                [self storeToManyRelationshipChangeForDescription:(id)propertyDesc committedValue:committed newValue:newValue];
            }
        }
        else if ([propertyDesc isKindOfClass:[NSRelationshipDescription class]] && ![(NSRelationshipDescription *)propertyDesc isToMany]) {
            [self storeToOneRelationshipChangeForDescription:(id)propertyDesc newValue:newValue];
        }
    }
    return self;
}

- (instancetype)initWithType:(CDEPropertyChangeType)type propertyName:(NSString *)name
{
    self = [super init];
    if (self) {
        self.propertyName = name;
        self.type = type;
        self.objectID = nil;
        self.value = nil;
        self.relatedIdentifier = nil;
        self.addedIdentifiers = nil;
        self.removedIdentifiers = nil;
        self.movedIdentifiersByIndex = nil;
    }
    return self;
}


#pragma mark NSCoding

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];
    if (self) {
        self.propertyName = [aDecoder decodeObjectForKey:@"propertyName"];
        self.value = [aDecoder decodeObjectForKey:@"value"];
        self.relatedIdentifier = [aDecoder decodeObjectForKey:@"relatedIdentifier"];
        self.addedIdentifiers = [aDecoder decodeObjectForKey:@"addedIdentifiers"];
        self.removedIdentifiers = [aDecoder decodeObjectForKey:@"removedIdentifiers"];
        self.movedIdentifiersByIndex = [aDecoder decodeObjectForKey:@"movedIdentifiersByIndex"];
        self.type = [aDecoder decodeIntegerForKey:@"type"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    static const NSInteger classVersion = 0;
    [aCoder encodeInteger:classVersion forKey:@"classVersion"];
    [aCoder encodeObject:self.propertyName forKey:@"propertyName"];
    [aCoder encodeObject:self.value forKey:@"value"];
    [aCoder encodeObject:self.relatedIdentifier forKey:@"relatedIdentifier"];
    [aCoder encodeObject:self.addedIdentifiers forKey:@"addedIdentifiers"];
    [aCoder encodeObject:self.removedIdentifiers forKey:@"removedIdentifiers"];
    [aCoder encodeObject:self.movedIdentifiersByIndex forKey:@"movedIdentifiersByIndex"];
    [aCoder encodeInteger:self.type forKey:@"type"];
}


#pragma mark Storing Changes

- (void)storeAttributeChangeForDescription:(NSAttributeDescription *)propertyDesc newValue:(id)newValue
{
    NSAttributeDescription *attribute = (id)propertyDesc;
    if ([attribute valueTransformerName]) {
        NSValueTransformer *valueTransformer = [NSValueTransformer valueTransformerForName:attribute.valueTransformerName];
        newValue = [valueTransformer transformedValue:newValue];
    }
    self.value = newValue;
    self.type = CDEPropertyChangeTypeAttribute;
}

- (void)storeToOneRelationshipChangeForDescription:(NSRelationshipDescription *)relationDesc newValue:(id)newValue
{
    NSManagedObject *relatedObject = newValue;
    NSError *error = nil;
    if (relatedObject && ![relatedObject.managedObjectContext obtainPermanentIDsForObjects:@[relatedObject] error:&error]) {
        NSLog(@"Could not get permanent ID for object: %@", error);
    }
    
    self.relatedIdentifier = relatedObject.objectID;
    self.type = CDEPropertyChangeTypeToOneRelationship;
}

- (void)storeToManyRelationshipChangeForDescription:(NSPropertyDescription *)propertyDesc committedValue:(NSSet *)committedValue newValue:(NSSet *)newValue
{
    NSSet *newRelatedObjects = newValue;
    NSSet *addedObjects, *removedObjects;
    if (committedValue) {
        // Determine the added and removed by comparing with committed values        
        NSMutableSet *mutableAdded = [newRelatedObjects mutableCopy];
        [mutableAdded minusSet:committedValue];
        addedObjects = mutableAdded;
        
        NSMutableSet *mutableRemoved = [committedValue mutableCopy];
        [mutableRemoved minusSet:newRelatedObjects];
        removedObjects = mutableRemoved;
    }
    else {
        addedObjects = newRelatedObjects;
        removedObjects = [NSSet set];
    }
    
    NSError *error;
    NSManagedObjectContext *context = nil;
    
    context = [addedObjects.anyObject managedObjectContext];
    if (context && ![context obtainPermanentIDsForObjects:addedObjects.allObjects error:&error]) {
        NSLog(@"Failed to get permanent ids: %@", error);
    }
    
    context = [removedObjects.anyObject managedObjectContext];
    if (context && ![context obtainPermanentIDsForObjects:removedObjects.allObjects error:&error]) {
        NSLog(@"Failed to get permanent ids: %@", error);
    }
    
    self.addedIdentifiers = [addedObjects valueForKeyPath:@"objectID"];
    self.removedIdentifiers = [removedObjects valueForKeyPath:@"objectID"];
    self.movedIdentifiersByIndex = nil;
    self.type = CDEPropertyChangeTypeToManyRelationship;
}

- (void)storeOrderedToManyRelationshipChangeForDescription:(NSRelationshipDescription *)propertyDesc committedValue:(NSOrderedSet *)committedValue newValue:(NSOrderedSet *)newValue
{
    // Store the added and removed identifiers, just as for a standard unordered to-many relationships
    [self storeToManyRelationshipChangeForDescription:propertyDesc committedValue:committedValue.set newValue:newValue.set];
    
    // Set property change type
    self.type = CDEPropertyChangeTypeOrderedToManyRelationship;

    // Store indexes for all new entries
    NSOrderedSet *newRelatedObjects = newValue;
    NSMutableDictionary *orderedIndexes = [[NSMutableDictionary alloc] initWithCapacity:newRelatedObjects.count];
    for (NSInteger index = 0; index < newRelatedObjects.count; index++) {
        [orderedIndexes setObject:newRelatedObjects[index] forKey:@(index)];
    }

    // Turn moved objects into objectIDs
    NSError *error;
    NSManagedObjectContext *context = [[orderedIndexes.allValues lastObject] managedObjectContext];
    if (context && ![context obtainPermanentIDsForObjects:orderedIndexes.allValues error:&error]) {
        NSLog(@"Failed to get permanent ids: %@", error);
    }

    NSMutableDictionary *finalMovedObjects = [[NSMutableDictionary alloc] initWithCapacity:orderedIndexes.count];
    [orderedIndexes enumerateKeysAndObjectsUsingBlock:^(NSNumber *index, NSManagedObject *obj, BOOL *stop) {
        [finalMovedObjects setObject:obj.objectID forKey:index];
    }];
    self.movedIdentifiersByIndex = finalMovedObjects;
}

- (NSString *)description
{
    NSString *result = [NSString stringWithFormat:@"Name: %@\rType: %d\rObjectID: %@\rValue: %@\rRelated: %@\rAdded: %@\rRemoved: %@\nMoved: %@", self.propertyName, (int)self.type, self.objectID, self.value, self.relatedIdentifier, self.addedIdentifiers, self.removedIdentifiers, self.movedIdentifiersByIndex];
    return result;
}

@end


