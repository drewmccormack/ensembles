//
//  CDEManagedObjectContextSaveMonitorRelationshipTests.m
//  Ensembles
//
//  Created by Drew McCormack on 17/08/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import <XCTest/XCTest.h>
#import <XCTest/XCTest.h>
#import "CDEEventStoreTestCase.h"
#import "CDESaveMonitor.h"
#import "CDEStoreModificationEvent.h"
#import "CDEObjectChange.h"
#import "CDEEventRevision.h"
#import "CDEGlobalIdentifier.h"
#import "CDEPropertyChangeValue.h"

@interface CDESaveMonitorRelationshipTests : CDEEventStoreTestCase

@end

@implementation CDESaveMonitorRelationshipTests {
    CDESaveMonitor *saveMonitor;
    NSPersistentStore *persistentStore;
    NSManagedObject *parent;
    NSManagedObjectContext *eventMOC;
    NSURL *child3URI, *parent1URI;
}

+ (void)setUp
{
    [super setUp];
    [self setUseDiskStore:YES];
}

- (void)setUp
{
    [super setUp];
    
    persistentStore = self.testManagedObjectContext.persistentStoreCoordinator.persistentStores[0];
    
    saveMonitor = [[CDESaveMonitor alloc] init];
    saveMonitor.eventStore = (id)self.eventStore;
    saveMonitor.storePath = persistentStore.URL.path;
    
    eventMOC = self.eventStore.managedObjectContext;
    parent = [NSEntityDescription insertNewObjectForEntityForName:@"Parent" inManagedObjectContext:self.testManagedObjectContext];
    NSDate *date = [NSDate dateWithTimeIntervalSinceReferenceDate:0.0];
    [parent setValue:date forKey:@"date"];
    
    [self save]; // Save 0
    
    id child = [NSEntityDescription insertNewObjectForEntityForName:@"Child" inManagedObjectContext:self.testManagedObjectContext];
    [child setValue:parent forKey:@"parent"];
    
    [self save]; // Save 1
    
    id child1 = [NSEntityDescription insertNewObjectForEntityForName:@"Child" inManagedObjectContext:self.testManagedObjectContext];
    id child2 = [NSEntityDescription insertNewObjectForEntityForName:@"Child" inManagedObjectContext:self.testManagedObjectContext];
    NSSet *children = [NSSet setWithObjects:child1, child2, nil];
    [parent setValue:children forKey:@"children"];
    
    [self save]; // Save 2
    
    NSManagedObject *parent1 = [NSEntityDescription insertNewObjectForEntityForName:@"Parent" inManagedObjectContext:self.testManagedObjectContext];
    NSManagedObject *parent2 = [NSEntityDescription insertNewObjectForEntityForName:@"Parent" inManagedObjectContext:self.testManagedObjectContext];
    NSManagedObject *child3 = [NSEntityDescription insertNewObjectForEntityForName:@"Child" inManagedObjectContext:self.testManagedObjectContext];
    NSManagedObject *child4 = [NSEntityDescription insertNewObjectForEntityForName:@"Child" inManagedObjectContext:self.testManagedObjectContext];
    [parent1 setValue:[NSSet setWithObjects:child3, child4, nil] forKey:@"friends"];
    [parent2 setValue:[NSSet setWithObjects:child3, nil] forKey:@"friends"];
    
    [self save]; // Save 3
    
    child3URI = child3.objectID.URIRepresentation;
    
    NSManagedObject *child5 = [NSEntityDescription insertNewObjectForEntityForName:@"Child" inManagedObjectContext:self.testManagedObjectContext];
    [[child5 mutableSetValueForKey:@"testFriends"] addObject:parent1];
    
    [self save]; // Save 4

    parent1URI = parent1.objectID.URIRepresentation;
}

- (void)tearDown
{
    [saveMonitor stopMonitoring];
    saveMonitor = nil;
    persistentStore = nil;
    [super tearDown];
}

- (void)save
{
    [self.testManagedObjectContext save:NULL];
    
    // Make sure async recording of save is complete
    [eventMOC performBlockAndWait:^{
        [self.eventStore updateRevisionsForSave];
    }];
}

- (NSArray *)fetchModEvents
{
    NSError *error = nil;
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"CDEStoreModificationEvent"];
    fetch.sortDescriptors = @[
        [NSSortDescriptor sortDescriptorWithKey:@"eventRevision.persistentStoreIdentifier" ascending:YES],
        [NSSortDescriptor sortDescriptorWithKey:@"eventRevision.revisionNumber" ascending:YES]
    ];
    NSArray *modEvents = [eventMOC executeFetchRequest:fetch error:&error];
    return modEvents;
}

- (CDEStoreModificationEvent *)modEventAtIndex:(NSUInteger)index
{
    NSArray *modEvents = [self fetchModEvents];
    CDEStoreModificationEvent *modEvent = modEvents[index];
    return modEvent;
}

- (NSSet *)insertsInModEvent:(CDEStoreModificationEvent *)event
{
    NSSet *inserts = [event.objectChanges filteredSetUsingPredicate:[NSPredicate predicateWithFormat:@"type = %d", CDEObjectChangeTypeInsert]];
    return inserts;
}

- (NSSet *)updatesInModEvent:(CDEStoreModificationEvent *)event
{
    NSSet *changes = [event.objectChanges filteredSetUsingPredicate:[NSPredicate predicateWithFormat:@"type = %d", CDEObjectChangeTypeUpdate]];
    return changes;
}

- (NSSet *)deletesInModEvent:(CDEStoreModificationEvent *)event
{
    NSSet *changes = [event.objectChanges filteredSetUsingPredicate:[NSPredicate predicateWithFormat:@"type = %d", CDEObjectChangeTypeDelete]];
    return changes;
}

- (void)testUpdatingOneToOneRelationship
{
    [eventMOC performBlockAndWait:^{
        CDEStoreModificationEvent *modEvent = [self modEventAtIndex:1];
        NSSet *objectChanges = modEvent.objectChanges;
        XCTAssertEqual(objectChanges.count, (NSUInteger)2, @"Wrong number of object changes.");
        
        NSSet *inserts = [self insertsInModEvent:modEvent];
        XCTAssertEqual(inserts.count, (NSUInteger)1, @"Wrong number of insert object changes.");
        
        CDEObjectChange *insert = inserts.anyObject;
        XCTAssertEqualObjects(insert.nameOfEntity, @"Child", @"Wrong entity for insert");
        
        NSArray *propertyChanges = insert.propertyChangeValues;
        XCTAssertEqual(propertyChanges.count, (NSUInteger)6, @"Wrong number of property changes for insert");
        
        CDEPropertyChangeValue *parentChangeValue = [insert propertyChangeValueForPropertyName:@"parent"];
        XCTAssertNotNil(parentChangeValue, @"Should be a change value for the parent");
        XCTAssertNil(parentChangeValue.value, @"Parent change value should have no new value");
        XCTAssertNotNil(parentChangeValue.relatedIdentifier, @"No related value for parent relationship");
        XCTAssertNil(parentChangeValue.addedIdentifiers, @"Should be no added ids for a to-one");
        XCTAssertNil(parentChangeValue.removedIdentifiers, @"Should be no removed ids for a to-one");
        
        NSSet *updates = [self updatesInModEvent:modEvent];
        XCTAssertEqual(updates.count, (NSUInteger)1, @"Wrong number of update object changes.");
        
        CDEObjectChange *update = updates.anyObject;
        CDEPropertyChangeValue *childChangeValue = [update propertyChangeValueForPropertyName:@"child"];
        XCTAssertNotNil(childChangeValue, @"Should be a change value for the parent");
        XCTAssertNil(childChangeValue.value, @"Parent change value should have no new value");
        XCTAssertNotNil(childChangeValue.relatedIdentifier, @"No related value for parent relationship");
        XCTAssertNil(childChangeValue.addedIdentifiers, @"Should be no added ids for a to-one");
        XCTAssertNil(childChangeValue.removedIdentifiers, @"Should be no removed ids for a to-one");
    }];
}

- (void)testUpdatingOneToManyRelationship
{
    [eventMOC performBlockAndWait:^{
        CDEStoreModificationEvent *modEvent = [self modEventAtIndex:2];
        NSSet *objectChanges = modEvent.objectChanges;
        XCTAssertEqual(objectChanges.count, (NSUInteger)3, @"Wrong number of object changes.");
        
        NSSet *inserts = [self insertsInModEvent:modEvent];
        XCTAssertEqual(inserts.count, (NSUInteger)2, @"Wrong number of insert object changes.");
        
        CDEObjectChange *insert = inserts.anyObject;
        XCTAssertEqualObjects(insert.nameOfEntity, @"Child", @"Wrong entity for insert");
        
        NSArray *propertyChanges = insert.propertyChangeValues;
        XCTAssertEqual(propertyChanges.count, (NSUInteger)6, @"Wrong number of property changes for insert");
        
        CDEPropertyChangeValue *parentChangeValue = [insert propertyChangeValueForPropertyName:@"parentWithSiblings"];
        XCTAssertNotNil(parentChangeValue, @"Should be a change value for the parent");
        XCTAssertNil(parentChangeValue.value, @"Parent change value should have no new value");
        XCTAssertNotNil(parentChangeValue.relatedIdentifier, @"No related value for parent relationship");
        XCTAssertNil(parentChangeValue.addedIdentifiers, @"Should be no added ids for a to-one");
        XCTAssertNil(parentChangeValue.removedIdentifiers, @"Should be no removed ids for a to-one");
        
        NSSet *updates = [self updatesInModEvent:modEvent];
        XCTAssertEqual(updates.count, (NSUInteger)1, @"Wrong number of update object changes.");
        
        CDEObjectChange *update = updates.anyObject;
        CDEPropertyChangeValue *childChangeValue = [update propertyChangeValueForPropertyName:@"children"];
        XCTAssertNotNil(childChangeValue, @"Should be a change value for the parent");
        XCTAssertNil(childChangeValue.value, @"Parent change value should have no new value");
        XCTAssertNil(childChangeValue.relatedIdentifier, @"No related value for parent relationship");
        XCTAssertNotNil(childChangeValue.addedIdentifiers, @"Should be no added ids for a to-one");
        XCTAssertEqual(childChangeValue.addedIdentifiers.count, (NSUInteger)2, @"Wrong number of children added");
        XCTAssertEqual(childChangeValue.removedIdentifiers.count, (NSUInteger)0, @"Should be no removed ids for a to-one");
    }];
}

- (void)testInitializingManyToManyRelationship
{
    [eventMOC performBlockAndWait:^{
        CDEStoreModificationEvent *modEvent = [self modEventAtIndex:3];
        NSSet *objectChanges = modEvent.objectChanges;
        XCTAssertEqual(objectChanges.count, (NSUInteger)4, @"Wrong number of object changes.");
        
        NSSet *inserts = [self insertsInModEvent:modEvent];
        XCTAssertEqual(inserts.count, (NSUInteger)4, @"Wrong number of insert object changes.");
        
        NSPredicate *pred = [NSPredicate predicateWithFormat:@"globalIdentifier.storeURI = %@", child3URI.absoluteString];
        NSSet *insertsForURI = [inserts filteredSetUsingPredicate:pred];
        XCTAssertEqual(insertsForURI.count, (NSUInteger)1, @"Wrong number of insert object changes for URI.");

        CDEObjectChange *childInsert = [insertsForURI anyObject];
        XCTAssertEqualObjects(childInsert.nameOfEntity, @"Child", @"Wrong entity for insert");
        
        NSArray *propertyChanges = childInsert.propertyChangeValues;
        XCTAssertEqual(propertyChanges.count, (NSUInteger)6, @"Wrong number of property changes for insert");
        
        CDEPropertyChangeValue *changeValue = [childInsert propertyChangeValueForPropertyName:@"testFriends"];
        XCTAssertNotNil(changeValue, @"Should be a change value for the testFriends");
        XCTAssertNil(changeValue.value, @"Parent change value should have no new value");
        XCTAssertNil(changeValue.relatedIdentifier, @"Should be no related value for parent relationship");
        XCTAssertEqual(changeValue.addedIdentifiers.count, (NSUInteger)2, @"Wrong number of added ids");
        XCTAssertEqual(changeValue.removedIdentifiers.count, (NSUInteger)0, @"Wrong number of removed ids");
    }];
}

- (void)testAddingToManyToManyRelationshipAddsUpdateChangeToRelatedObject
{
    [eventMOC performBlockAndWait:^{
        CDEStoreModificationEvent *modEvent = [self modEventAtIndex:4];
        NSSet *updates = [self updatesInModEvent:modEvent];
        NSPredicate *pred = [NSPredicate predicateWithFormat:@"globalIdentifier.storeURI = %@", parent1URI.absoluteString];
        NSSet *updatesForURI = [updates filteredSetUsingPredicate:pred];
        CDEObjectChange *parentUpdate = [updatesForURI anyObject];
        CDEPropertyChangeValue *changeValue = [parentUpdate propertyChangeValueForPropertyName:@"friends"];
        XCTAssertEqual(changeValue.addedIdentifiers.count, (NSUInteger)1, @"Wrong number of added ids");
        XCTAssertEqual(changeValue.removedIdentifiers.count, (NSUInteger)0, @"Wrong number of removed ids");
    }];
}

@end
