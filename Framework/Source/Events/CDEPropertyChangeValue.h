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

@interface CDEPropertyChangeValue : NSObject <NSCoding>

@property (nonatomic, readonly) CDEPropertyChangeType type;
@property (nonatomic, readonly) NSString *propertyName;

// Relationship identifiers may be local object ids or global ids,
// depending on the context. When saved to the event store, they are global ids.
@property (nonatomic, readwrite) id value; // for attributes
@property (nonatomic, readwrite) id relatedIdentifier; // for to-one relationships
@property (nonatomic, readwrite) NSSet *addedIdentifiers, *removedIdentifiers; // for to-many relationships
@property (nonatomic, readwrite) NSDictionary *movedIdentifiersByIndex; // for ordered to-many relationships

// Transient properties
@property (nonatomic, readonly) NSManagedObjectID *objectID;
@property (nonatomic, readwrite) id relatedObjectIDs; // Used to determine to-many deltas

+ (NSArray *)propertyChangesForObject:(NSManagedObject *)object propertyNames:(id)names isPreSave:(BOOL)isPreSave storeValues:(BOOL)storeValues;

- (instancetype)initWithObject:(NSManagedObject *)object propertyDescription:(NSPropertyDescription *)propertyDesc isPreSave:(BOOL)isPreSave storeValues:(BOOL)storeValues;
- (instancetype)initWithType:(CDEPropertyChangeType)type propertyName:(NSString *)name;

- (void)updateWithObject:(NSManagedObject *)object isPreSave:(BOOL)isPreSave storeValues:(BOOL)storeValues;

@end
