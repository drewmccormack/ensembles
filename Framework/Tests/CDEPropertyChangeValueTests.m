//
//  CDEPropertyChangeValueTests.m
//  Ensembles
//
//  Created by Drew McCormack on 7/2/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "CDEPropertyChangeValue.h"
#import "CDEEventStoreTestCase.h"

@interface CDEPropertyChangeValueTests : CDEEventStoreTestCase

@end

@implementation CDEPropertyChangeValueTests {
    NSManagedObject *parent, *child;
    NSSet *siblingChildren;
}

- (void)setUp
{
    [super setUp];
    parent = [NSEntityDescription insertNewObjectForEntityForName:@"Parent" inManagedObjectContext:self.testManagedObjectContext];
    child = [NSEntityDescription insertNewObjectForEntityForName:@"Child" inManagedObjectContext:self.testManagedObjectContext];
    [child setValue:parent forKey:@"parent"];
    
    id child1 = [NSEntityDescription insertNewObjectForEntityForName:@"Child" inManagedObjectContext:self.testManagedObjectContext];
    id child2 = [NSEntityDescription insertNewObjectForEntityForName:@"Child" inManagedObjectContext:self.testManagedObjectContext];
    siblingChildren = [NSSet setWithObjects:child1, child2, nil];
    [parent setValue:siblingChildren forKey:@"children"];

    [self.testManagedObjectContext obtainPermanentIDsForObjects:@[child, parent] error:NULL];
    [self.testManagedObjectContext processPendingChanges];
}

- (void)tearDown
{
    child = nil;
    parent = nil;
    [super tearDown];
}

- (void)testFactoryMethod
{
    NSArray *propertyChanges = [CDEPropertyChangeValue propertyChangesForObject:parent eventStore:nil propertyNames:parent.entity.propertiesByName.allKeys isPreSave:YES storeValues:YES];
    NSUInteger expectedPropertyCount = [[parent entity] properties].count;
    XCTAssertEqual(propertyChanges.count, expectedPropertyCount, @"Wrong number of property changes");
}

- (void)testAttributeChange
{
    id newValue = [NSDate date];
    [parent setValue:newValue forKey:@"date"];

    NSPropertyDescription *propertyDesc = parent.entity.propertiesByName[@"date"];
    CDEPropertyChangeValue *changeValue = [[CDEPropertyChangeValue alloc] initWithObject:parent propertyDescription:propertyDesc eventStore:nil isPreSave:YES storeValues:YES];
    XCTAssertEqual(changeValue.type, CDEPropertyChangeTypeAttribute, @"Wrong type for change value");
    XCTAssertEqualObjects(changeValue.value, newValue, @"Wrong value in change value");
}

- (void)testAttributeChangeNoStore
{
    id newValue = [NSDate date];
    [parent setValue:newValue forKey:@"date"];
    
    NSPropertyDescription *propertyDesc = parent.entity.propertiesByName[@"date"];
    CDEPropertyChangeValue *changeValue = [[CDEPropertyChangeValue alloc] initWithObject:parent propertyDescription:propertyDesc eventStore:nil isPreSave:YES storeValues:NO];
    XCTAssertEqual(changeValue.type, CDEPropertyChangeTypeAttribute, @"Wrong type for change value");
    XCTAssertNil(changeValue.value, @"Should be no stored value");
}

- (void)testAttributeChangePostSave
{
    id newValue = [NSDate date];
    [parent setValue:newValue forKey:@"date"];
    [self.testManagedObjectContext save:NULL];

    NSPropertyDescription *propertyDesc = parent.entity.propertiesByName[@"date"];
    CDEPropertyChangeValue *changeValue = [[CDEPropertyChangeValue alloc] initWithObject:parent propertyDescription:propertyDesc eventStore:nil isPreSave:NO storeValues:YES];
    XCTAssertEqual(changeValue.type, CDEPropertyChangeTypeAttribute, @"Wrong type for change value");
    XCTAssertEqualObjects(changeValue.value, newValue, @"Wrong value in change value");
}

- (void)testToOneRelationship
{
    NSPropertyDescription *propertyDesc = child.entity.propertiesByName[@"parent"];
    
    CDEPropertyChangeValue *changeValue = [[CDEPropertyChangeValue alloc] initWithObject:child propertyDescription:propertyDesc eventStore:nil isPreSave:YES storeValues:YES];
    XCTAssertEqual(changeValue.type, CDEPropertyChangeTypeToOneRelationship, @"Wrong type for change value");
    XCTAssertEqualObjects(changeValue.propertyName, propertyDesc.name, @"Wrong property name for relationship");
    XCTAssertEqualObjects(changeValue.relatedIdentifier, parent.objectID, @"Wrong related identifier");
}

- (void)testToOneRelationshipNoStore
{
    NSPropertyDescription *propertyDesc = child.entity.propertiesByName[@"parent"];
    
    CDEPropertyChangeValue *changeValue = [[CDEPropertyChangeValue alloc] initWithObject:child propertyDescription:propertyDesc eventStore:nil isPreSave:YES storeValues:NO];
    XCTAssertEqual(changeValue.type, CDEPropertyChangeTypeToOneRelationship, @"Wrong type for change value");
    XCTAssertEqualObjects(changeValue.propertyName, propertyDesc.name, @"Wrong property name for relationship");
    XCTAssertNil(changeValue.relatedIdentifier, @"Wrong related identifier");
}

- (void)testToOneRelationshipPostSave
{
    NSPropertyDescription *propertyDesc = child.entity.propertiesByName[@"parent"];
    [self.testManagedObjectContext save:NULL];
    
    CDEPropertyChangeValue *changeValue = [[CDEPropertyChangeValue alloc] initWithObject:child propertyDescription:propertyDesc eventStore:nil isPreSave:NO storeValues:YES];
    XCTAssertEqual(changeValue.type, CDEPropertyChangeTypeToOneRelationship, @"Wrong type for change value");
    XCTAssertEqualObjects(changeValue.propertyName, propertyDesc.name, @"Wrong property name for relationship");
    XCTAssertEqualObjects(changeValue.relatedIdentifier, parent.objectID, @"Wrong related identifier");
}

- (void)testSetToOneRelationshipToNil
{
    [child setValue:nil forKey:@"parent"];
    NSPropertyDescription *propertyDesc = child.entity.propertiesByName[@"parent"];
    
    CDEPropertyChangeValue *changeValue = [[CDEPropertyChangeValue alloc] initWithObject:child propertyDescription:propertyDesc eventStore:nil isPreSave:YES storeValues:YES];
    XCTAssertNil(changeValue.relatedIdentifier, @"Wrong related identifier");
}

- (void)testAddingToToManyRelationship
{
    NSPropertyDescription *propertyDesc = parent.entity.propertiesByName[@"children"];
    
    CDEPropertyChangeValue *changeValue = [[CDEPropertyChangeValue alloc] initWithObject:parent propertyDescription:propertyDesc eventStore:nil isPreSave:YES storeValues:YES];
    XCTAssertEqual(changeValue.type, CDEPropertyChangeTypeToManyRelationship, @"Wrong type for change value");
    XCTAssertEqualObjects(changeValue.propertyName, propertyDesc.name, @"Wrong property name for relationship");
    
    NSSet *childSet = [siblingChildren valueForKeyPath:@"objectID"];
    XCTAssertTrue([changeValue.addedIdentifiers isEqualToSet:childSet], @"Wrong added identifiers");
    XCTAssertTrue([changeValue.removedIdentifiers isEqualToSet:[NSSet set]], @"Wrong removed identifiers");
}

- (void)testAddingToToManyRelationshipNoStore
{
    NSPropertyDescription *propertyDesc = parent.entity.propertiesByName[@"children"];
    [self.testManagedObjectContext save:NULL];

    CDEPropertyChangeValue *changeValue = [[CDEPropertyChangeValue alloc] initWithObject:parent propertyDescription:propertyDesc eventStore:nil isPreSave:YES storeValues:NO];
    XCTAssertEqual(changeValue.type, CDEPropertyChangeTypeToManyRelationship, @"Wrong type for change value");
    XCTAssertEqualObjects(changeValue.propertyName, propertyDesc.name, @"Wrong property name for relationship");
    
    NSSet *childSet = [siblingChildren valueForKeyPath:@"objectID"];
    XCTAssertTrue([changeValue.relatedObjectIDs isEqualToSet:childSet], @"Wrong related identifiers");
    XCTAssertNil(changeValue.addedIdentifiers, @"Added should be nil");
    XCTAssertNil(changeValue.removedIdentifiers, @"Removed should be nil");
}

- (void)testRemovalFromToManyRelationship
{
    [self.testManagedObjectContext save:NULL];
    
    id childSibling = siblingChildren.anyObject;
    NSSet *newChildrenSet = [NSSet setWithObject:childSibling];
    [parent setValue:newChildrenSet forKey:@"children"];
    
    NSPropertyDescription *propertyDesc = parent.entity.propertiesByName[@"children"];
    CDEPropertyChangeValue *changeValue = [[CDEPropertyChangeValue alloc] initWithObject:parent propertyDescription:propertyDesc eventStore:nil isPreSave:YES storeValues:YES];

    NSMutableSet *removedChildren = [siblingChildren mutableCopy];
    [removedChildren minusSet:newChildrenSet];
    NSSet *childSet = [removedChildren valueForKeyPath:@"objectID"];
    XCTAssertTrue([changeValue.addedIdentifiers isEqualToSet:[NSSet set]], @"Wrong added identifiers");
    XCTAssertTrue([changeValue.removedIdentifiers isEqualToSet:childSet], @"Wrong removed identifiers");
}

- (void)testRemovalFromToManyRelationshipNoStore
{
    [self.testManagedObjectContext save:NULL];
    
    NSSet *originalChildSet = [[parent valueForKeyPath:@"children"] valueForKeyPath:@"objectID"];

    id childSibling = siblingChildren.anyObject;
    NSSet *newChildrenSet = [NSSet setWithObject:childSibling];
    [parent setValue:newChildrenSet forKey:@"children"];
    
    NSPropertyDescription *propertyDesc = parent.entity.propertiesByName[@"children"];
    CDEPropertyChangeValue *changeValue = [[CDEPropertyChangeValue alloc] initWithObject:parent propertyDescription:propertyDesc eventStore:nil isPreSave:YES storeValues:NO];
    
    XCTAssertTrue([changeValue.relatedObjectIDs isEqualToSet:originalChildSet], @"Wrong related identifiers");
    XCTAssertNil(changeValue.addedIdentifiers, @"Added should be nil");
    XCTAssertNil(changeValue.removedIdentifiers, @"Removed should be nil");
}

- (void)testArchiving
{
    NSPropertyDescription *propertyDesc = parent.entity.propertiesByName[@"children"];
    CDEPropertyChangeValue *changeValue = [[CDEPropertyChangeValue alloc] initWithObject:parent propertyDescription:propertyDesc eventStore:nil isPreSave:YES storeValues:YES];
    
    NSSet *childSet = [siblingChildren valueForKeyPath:@"objectID.URIRepresentation"]; // Pretend global ids
    changeValue.addedIdentifiers = childSet;
    
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:changeValue];
    CDEPropertyChangeValue *copiedChangeValue = [NSKeyedUnarchiver unarchiveObjectWithData:data];

    XCTAssertEqual(copiedChangeValue.type, CDEPropertyChangeTypeToManyRelationship, @"Wrong type for change value");
    XCTAssertEqualObjects(copiedChangeValue.propertyName, propertyDesc.name, @"Wrong property name for relationship");
    
    XCTAssertTrue([copiedChangeValue.addedIdentifiers isEqualToSet:childSet], @"Wrong added identifiers");
}

- (void)testMergingToManyRelationship
{
    CDEPropertyChangeValue *value1 = [[CDEPropertyChangeValue alloc] initWithType:CDEPropertyChangeTypeToManyRelationship propertyName:@"property"];
    value1.addedIdentifiers = [NSSet setWithObjects:@"11", @"12", nil];
    value1.removedIdentifiers = [NSSet set];
    
    CDEPropertyChangeValue *value2 = [[CDEPropertyChangeValue alloc] initWithType:CDEPropertyChangeTypeToManyRelationship propertyName:@"property"];
    value2.addedIdentifiers = [NSSet setWithObjects:@"11", nil];
    value2.removedIdentifiers = [NSSet setWithObjects:@"12", nil];
    
    [value2 mergeToManyRelationshipFromSubordinatePropertyChangeValue:value1];
    
    NSSet *added = [NSSet setWithObjects:@"11", nil];
    
    XCTAssertEqualObjects(value2.addedIdentifiers, added, @"Wrong added ids");
    XCTAssertEqualObjects(value2.removedIdentifiers, [NSSet new], @"Removes should always end up empty");
}

- (void)testMergingOrderedToManyRelationship
{
    CDEPropertyChangeValue *value1 = [[CDEPropertyChangeValue alloc] initWithType:CDEPropertyChangeTypeOrderedToManyRelationship propertyName:@"property"];
    value1.addedIdentifiers = [NSSet setWithObjects:@"11", @"12", @"13", nil];
    value1.removedIdentifiers = [NSSet set];
    value1.movedIdentifiersByIndex = @{@0 : @"12", @1 : @"13", @2 : @"11"};
    
    CDEPropertyChangeValue *value2 = [[CDEPropertyChangeValue alloc] initWithType:CDEPropertyChangeTypeOrderedToManyRelationship propertyName:@"property"];
    value2.addedIdentifiers = [NSSet setWithObjects:@"11", nil];
    value2.removedIdentifiers = [NSSet setWithObjects:@"12", nil];
    value2.movedIdentifiersByIndex = @{@0 : @"11"};
    
    [value2 mergeToManyRelationshipFromSubordinatePropertyChangeValue:value1];
    
    NSSet *added = [NSSet setWithObjects:@"11", @"13", nil];
    NSDictionary *moved = @{@0 : @"11", @1 : @"13"};

    XCTAssertEqualObjects(value2.addedIdentifiers, added, @"Wrong added ids");
    XCTAssertEqualObjects(value2.removedIdentifiers, [NSSet set], @"Removes should be empty");
    XCTAssertEqualObjects(value2.movedIdentifiersByIndex, moved, @"Wrong removed ids");
}

@end
