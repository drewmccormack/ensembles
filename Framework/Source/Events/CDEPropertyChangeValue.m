//
//  CDEPropertyChangeValue.m
//  Test App iOS
//
//  Created by Drew McCormack on 4/20/13.
//  Copyright (c) 2013 The Mental Faculty B.V. All rights reserved.
//

#import "CDEPropertyChangeValue.h"
#import "CDEDefines.h"
#import "CDEEventStore.h"

@interface CDEPropertyChangeValue ()

@property (nonatomic, strong, readwrite) NSManagedObjectID *objectID;
@property (nonatomic, strong, readwrite) NSString *propertyName;
@property (nonatomic, assign, readwrite) CDEPropertyChangeType type;

@end


@implementation CDEPropertyChangeValue

+ (NSArray *)propertyChangesForObject:(NSManagedObject *)object eventStore:(CDEEventStore *)newEventStore propertyNames:(id)names isPreSave:(BOOL)isPreSave storeValues:(BOOL)storeValues
{
    NSMutableArray *propertyChanges = [[NSMutableArray alloc] initWithCapacity:[names count]];
    NSEntityDescription *entity = object.entity;
    
    for (NSString *propertyName in names) {
        NSPropertyDescription *propertyDesc = entity.propertiesByName[propertyName];
        
        if ([propertyDesc isKindOfClass:[NSFetchedPropertyDescription class]]) {
            continue;
        }
        
        CDEPropertyChangeValue *change = [[CDEPropertyChangeValue alloc] initWithObject:object propertyDescription:propertyDesc eventStore:newEventStore isPreSave:isPreSave storeValues:storeValues];
        [propertyChanges addObject:change];
    }
    
    return propertyChanges;
}

- (instancetype)initWithObject:(NSManagedObject *)object propertyDescription:(NSPropertyDescription *)propertyDesc eventStore:(CDEEventStore *)newEventStore isPreSave:(BOOL)isPreSave storeValues:(BOOL)storeValues
{
    NSAssert(!object.objectID.isTemporaryID, @"Object has a temporary id in initWithObject: of CDEPropertyChangeValue");
    CDEPropertyChangeType newType = [self.class propertyChangeTypeForPropertyDescription:propertyDesc];
    self = [self initWithType:newType propertyName:propertyDesc.name];
    if (self) {
        self.eventStore = newEventStore;
        self.objectID = object.objectID;
        [self updateWithObject:object isPreSave:isPreSave storeValues:storeValues];
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
        self.filename = nil;
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
        self.type = [aDecoder decodeIntegerForKey:@"type"];
        self.filename = [aDecoder decodeObjectForKey:@"filename"];
        self.value = [aDecoder decodeObjectForKey:@"value"];
        self.relatedIdentifier = [aDecoder decodeObjectForKey:@"relatedIdentifier"];
        self.addedIdentifiers = [aDecoder decodeObjectForKey:@"addedIdentifiers"];
        self.removedIdentifiers = [aDecoder decodeObjectForKey:@"removedIdentifiers"];
        self.movedIdentifiersByIndex = [aDecoder decodeObjectForKey:@"movedIdentifiersByIndex"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    static const NSInteger classVersion = 1;
    [aCoder encodeInteger:classVersion forKey:@"classVersion"];
    [aCoder encodeObject:self.propertyName forKey:@"propertyName"];
    [aCoder encodeInteger:self.type forKey:@"type"];

    if (self.value) [aCoder encodeObject:self.value forKey:@"value"];
    if (self.filename) [aCoder encodeObject:self.filename forKey:@"filename"];
    if (self.relatedIdentifier) [aCoder encodeObject:self.relatedIdentifier forKey:@"relatedIdentifier"];
    if (self.addedIdentifiers) [aCoder encodeObject:self.addedIdentifiers forKey:@"addedIdentifiers"];
    if (self.removedIdentifiers) [aCoder encodeObject:self.removedIdentifiers forKey:@"removedIdentifiers"];
    if (self.movedIdentifiersByIndex) [aCoder encodeObject:self.movedIdentifiersByIndex forKey:@"movedIdentifiersByIndex"];
}


#pragma mark Property Types

+ (CDEPropertyChangeType)propertyChangeTypeForPropertyDescription:(NSPropertyDescription *)propertyDesc
{
    CDEPropertyChangeType newType;
    if ([propertyDesc isKindOfClass:[NSAttributeDescription class]])
        newType = CDEPropertyChangeTypeAttribute;
    else {
        NSRelationshipDescription *relationship = (id)propertyDesc;
        if (relationship.isToMany) {
            newType = relationship.isOrdered ? CDEPropertyChangeTypeOrderedToManyRelationship : CDEPropertyChangeTypeToManyRelationship;
        }
        else {
            newType = CDEPropertyChangeTypeToOneRelationship;
        }
    }
    return newType;
}


#pragma mark Storing Values

- (void)updateWithObject:(NSManagedObject *)object isPreSave:(BOOL)isPreSave storeValues:(BOOL)storeValues
{
    NSPropertyDescription *propertyDesc = object.entity.propertiesByName[self.propertyName];
    BOOL isToMany = [propertyDesc isKindOfClass:[NSRelationshipDescription class]] && [(id)propertyDesc isToMany];
    BOOL isToOne = [propertyDesc isKindOfClass:[NSRelationshipDescription class]] && ![(id)propertyDesc isToMany];
    BOOL isAttribute = [propertyDesc isKindOfClass:[NSAttributeDescription class]];
    
    if (isToMany && isPreSave) {
        // Store object ids for related objects. These are used post-save to determine
        // added and removed identifiers
        NSRelationshipDescription *relationshipDescription = (id)propertyDesc;
        NSDictionary *committedValues = [object committedValuesForKeys:@[propertyDesc.name]];
        id committed = committedValues[propertyDesc.name];
        id objectIDs = [committed valueForKeyPath:@"objectID"];
        self.relatedObjectIDs = relationshipDescription.isOrdered ? [(NSOrderedSet *)objectIDs set] : objectIDs;
    }
    
    if (!storeValues) return;
    
    // Get the new value
    id newValue;
    if (isPreSave) {
        newValue = object.changedValues[self.propertyName];
    }
    else {
        NSDictionary *committedValues = [object committedValuesForKeys:@[self.propertyName]];
        newValue = committedValues[self.propertyName];
    }
    newValue = CDENSNullToNil(newValue);
    
    // Store the new value
    if (isAttribute) {
        [self storeAttributeChangeForDescription:(id)propertyDesc newValue:newValue];
    }
    else if (isToMany) {
        NSRelationshipDescription *relationshipDescription = (id)propertyDesc;
        if (relationshipDescription.isOrdered) {
            [self storeOrderedToManyRelationshipChangeForDescription:relationshipDescription newValue:newValue];
        } else {
            [self storeToManyRelationshipChangeForDescription:(id)propertyDesc newValue:newValue];
        }
    }
    else if (isToOne) {
        [self storeToOneRelationshipChangeForDescription:(id)propertyDesc newValue:newValue];
    }
}


#pragma mark Storing Changes

- (void)storeAttributeChangeForDescription:(NSAttributeDescription *)propertyDesc newValue:(id)newValue
{
    NSAttributeDescription *attribute = (id)propertyDesc;
    if ([attribute valueTransformerName]) {
        NSValueTransformer *valueTransformer = [NSValueTransformer valueTransformerForName:attribute.valueTransformerName];
        newValue = [valueTransformer transformedValue:newValue];
    }
    
    // Put data bigger than 10KB or so in an external file
    if ([newValue isKindOfClass:[NSData class]] && [(NSData *)newValue length] > 10e3) {
        NSAssert(self.eventStore, @"Storing large data attribute requires event store");
        self.filename = [self.eventStore storeDataInFile:newValue];
        self.value = nil;
        if (self.filename) return; // If success, return. Otherwise just store normally below.
    }

    self.value = newValue;
    self.filename = nil;
}

- (void)storeToOneRelationshipChangeForDescription:(NSRelationshipDescription *)relationDesc newValue:(id)newValue
{
    NSManagedObject *relatedObject = newValue;
    NSError *error = nil;
    if (relatedObject && ![relatedObject.managedObjectContext obtainPermanentIDsForObjects:@[relatedObject] error:&error]) {
        CDELog(CDELoggingLevelError, @"Could not get permanent ID for object: %@", error);
    }
    
    self.relatedIdentifier = relatedObject.objectID;
}

- (void)storeToManyRelationshipChangeForDescription:(NSPropertyDescription *)propertyDesc newValue:(NSSet *)newValue
{
    NSSet *originalObjectIDs = self.relatedObjectIDs;
    
    NSError *error;
    NSSet *newRelatedObjects = newValue;
    NSManagedObjectContext *context = [newRelatedObjects.anyObject managedObjectContext];
    if (context && ![context obtainPermanentIDsForObjects:newRelatedObjects.allObjects error:&error]) {
        CDELog(CDELoggingLevelError, @"Failed to get permanent ids: %@", error);
    }
    NSSet *newRelatedObjectIDs = [newValue valueForKeyPath:@"objectID"];
    
    NSSet *addedObjectIDs, *removedObjectIDs;
    if (originalObjectIDs) {
        // Determine the added and removed by comparing with original values
        NSMutableSet *mutableAdded = [newRelatedObjectIDs mutableCopy];
        [mutableAdded minusSet:originalObjectIDs];
        addedObjectIDs = mutableAdded;
        
        NSMutableSet *mutableRemoved = [originalObjectIDs mutableCopy];
        [mutableRemoved minusSet:newRelatedObjectIDs];
        removedObjectIDs = mutableRemoved;
    }
    else {
        addedObjectIDs = newRelatedObjectIDs;
        removedObjectIDs = [NSSet set];
    }
    
    self.addedIdentifiers = addedObjectIDs;
    self.removedIdentifiers = removedObjectIDs;
    self.movedIdentifiersByIndex = nil;
}

- (void)storeOrderedToManyRelationshipChangeForDescription:(NSRelationshipDescription *)propertyDesc newValue:(NSOrderedSet *)newValue
{
    // Store the added and removed identifiers, just as for a standard unordered to-many relationships
    [self storeToManyRelationshipChangeForDescription:propertyDesc newValue:newValue.set];

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
        CDELog(CDELoggingLevelError, @"Failed to get permanent ids: %@", error);
    }

    NSMutableDictionary *finalMovedObjects = [[NSMutableDictionary alloc] initWithCapacity:orderedIndexes.count];
    [orderedIndexes enumerateKeysAndObjectsUsingBlock:^(NSNumber *index, NSManagedObject *obj, BOOL *stop) {
        [finalMovedObjects setObject:obj.objectID forKey:index];
    }];
    self.movedIdentifiersByIndex = finalMovedObjects;
}


#pragma mark Extracting Values

- (id)attributeValueForAttributeDescription:(NSAttributeDescription *)attribute
{
    id returnValue = nil;
    if (self.filename) {
        NSAssert(self.eventStore, @"Retrieving attribute requires event store");
        returnValue = [self.eventStore dataForFile:self.filename];
    }
    else if (self.value) {
        returnValue = self.value == [NSNull null] ? nil : self.value;
    }
    
    if (attribute.valueTransformerName) {
        NSValueTransformer *valueTransformer = [NSValueTransformer valueTransformerForName:attribute.valueTransformerName];
        if (!valueTransformer) {
            CDELog(CDELoggingLevelWarning, @"Failed to retrieve value transformer: %@", attribute.valueTransformerName);
            returnValue = nil;
        }
        else {
            returnValue = [valueTransformer reverseTransformedValue:returnValue];
        }
    }
    
    return returnValue;
}


#pragma mark Merging

- (void)mergeToManyRelationshipFromSubordinatePropertyChangeValue:(CDEPropertyChangeValue *)propertyValue
{
    static NSString *globalIdErrorMessage = @"Encountered NSNull in relationship merge. This should not arise. It usually indicates that at some point, multiple objects were saved at once with the same global id.";
    
    // Adds
    NSMutableSet *newAdded = [[NSMutableSet alloc] initWithSet:self.addedIdentifiers];
    [newAdded unionSet:propertyValue.addedIdentifiers];
    [newAdded minusSet:self.removedIdentifiers]; // removes override adds in other value
    
    // Check for NSNull. Should not be there.
    if ([newAdded containsObject:[NSNull null]]) {
        CDELog(CDELoggingLevelError, @"%@", globalIdErrorMessage);
        [newAdded removeObject:[NSNull null]];
    }
    
    // Set
    self.addedIdentifiers = newAdded;
    self.removedIdentifiers = [[NSSet alloc] init];
    
    // Non-ordered relationships are done
    if (propertyValue.type != CDEPropertyChangeTypeOrderedToManyRelationship) return;
    
    // If it is an ordered to-many, update ordering.
    NSMutableDictionary *indexesByGlobalId = [[NSMutableDictionary alloc] init];
    for (NSNumber *indexNum in propertyValue.movedIdentifiersByIndex) {
        NSString *globalId = propertyValue.movedIdentifiersByIndex[indexNum];
        if ((id)globalId == [NSNull null]) {
            CDELog(CDELoggingLevelError, @"%@", globalIdErrorMessage);
            continue;
        }
        indexesByGlobalId[globalId] = indexNum;
    }
    
    for (NSNumber *indexNum in self.movedIdentifiersByIndex) {
        NSString *globalId = self.movedIdentifiersByIndex[indexNum];
        if ((id)globalId == [NSNull null]) {
            CDELog(CDELoggingLevelError, @"%@", globalIdErrorMessage);
            continue;
        }
        indexesByGlobalId[globalId] = indexNum;
    }
    
    // Sort first on index, and use global id to resolve conflicts.
    NSMutableArray *sortedIdentifiers = [self.addedIdentifiers.allObjects mutableCopy];
    [sortedIdentifiers sortUsingComparator:^NSComparisonResult(NSString *globalId1, NSString *globalId2) {
        NSNumber *index1 = [indexesByGlobalId objectForKey:globalId1];
        NSNumber *index2 = [indexesByGlobalId objectForKey:globalId2];
        NSComparisonResult indexResult = [index1 compare:index2];
        if (indexResult != NSOrderedSame) return indexResult;
        NSComparisonResult globalIdResult = [globalId1 compare:globalId2];
        return globalIdResult;
    }];
    
    NSMutableDictionary *newMovedIdentifiersByIndex = [[NSMutableDictionary alloc] init];
    [sortedIdentifiers enumerateObjectsUsingBlock:^(NSString *globalId, NSUInteger i, BOOL *stop) {
        newMovedIdentifiersByIndex[@(i)] = globalId;
    }];
    
    self.movedIdentifiersByIndex = newMovedIdentifiersByIndex;
}


#pragma mark Inherited

- (NSString *)description
{
    NSString *result = [NSString stringWithFormat:@"Name: %@\rType: %d\rObjectID: %@\rValue: %@\rFilename: %@\rRelated: %@\rAdded: %@\rRemoved: %@\nMoved: %@\nRelated IDs: %@", self.propertyName, (int)self.type, self.objectID, self.value, self.filename, self.relatedIdentifier, self.addedIdentifiers, self.removedIdentifiers, self.movedIdentifiersByIndex, self.relatedObjectIDs];
    return result;
}

@end


