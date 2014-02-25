//
//  CDEPropertyChangeDescriptor.h
//  Test App iOS
//
//  Created by Drew McCormack on 4/20/13.
//  Copyright (c) 2013 The Mental Faculty B.V. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

typedef NS_ENUM(NSInteger, CDEPropertyChangeType) {
    CDEPropertyChangeTypeAttribute,
    CDEPropertyChangeTypeToOneRelationship,
    CDEPropertyChangeTypeToManyRelationship,
    CDEPropertyChangeTypeOrderedToManyRelationship
};

@class CDEEventStore;

@interface CDEPropertyChangeValue : NSObject <NSCoding>

@property (nonatomic, assign, readonly) CDEPropertyChangeType type;
@property (nonatomic, strong, readonly) NSString *propertyName;
@property (nonatomic, weak, readwrite) CDEEventStore *eventStore;

// Relationship identifiers may be local object ids or global ids,
// depending on the context. When saved to the event store, they are global ids.
@property (nonatomic, strong, readwrite) id value; // for attributes
@property (nonatomic, strong, readwrite) NSString *filename; // for large binary data attributes
@property (nonatomic, strong, readwrite) id relatedIdentifier; // for to-one relationships
@property (nonatomic, strong, readwrite) NSSet *addedIdentifiers, *removedIdentifiers; // for to-many relationships
@property (nonatomic, strong, readwrite) NSDictionary *movedIdentifiersByIndex; // for ordered to-many relationships

// Transient properties
@property (nonatomic, strong, readonly) NSManagedObjectID *objectID;
@property (nonatomic, strong, readwrite) id relatedObjectIDs; // Used to determine to-many deltas

+ (NSArray *)propertyChangesForObject:(NSManagedObject *)object eventStore:(CDEEventStore *)eventStore propertyNames:(id)names isPreSave:(BOOL)isPreSave storeValues:(BOOL)storeValues;

- (instancetype)initWithObject:(NSManagedObject *)object propertyDescription:(NSPropertyDescription *)propertyDesc eventStore:(CDEEventStore *)eventStore isPreSave:(BOOL)isPreSave storeValues:(BOOL)storeValues;
- (instancetype)initWithType:(CDEPropertyChangeType)type propertyName:(NSString *)name;

- (id)attributeValueForAttributeDescription:(NSAttributeDescription *)attribute;

- (void)updateWithObject:(NSManagedObject *)object isPreSave:(BOOL)isPreSave storeValues:(BOOL)storeValues;

- (void)mergeToManyRelationshipFromSubordinatePropertyChangeValue:(CDEPropertyChangeValue *)propertyValue;

@end
