//
//  CDEEventMigratorTests.m
//  Ensembles
//
//  Created by Drew McCormack on 10/08/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "CDEEventStoreTestCase.h"
#import "CDEStoreModificationEvent.h"
#import "CDEObjectChange.h"
#import "CDEGlobalIdentifier.h"
#import "CDEEventRevision.h"
#import "CDEEventMigrator.h"

@interface CDEEventMigratorTests : CDEEventStoreTestCase

@end

@implementation CDEEventMigratorTests  {
    CDEStoreModificationEvent *modEvent;
    CDEGlobalIdentifier *globalId1, *globalId2, *globalId3;
    CDEObjectChange *objectChange1, *objectChange2, *objectChange3;
    NSManagedObjectContext *moc;
    CDEEventMigrator *migrator;
    NSString *exportedEventsFile;
    NSManagedObjectContext *fileContext;
    BOOL finishedAsyncOp;
}

- (void)setUp
{
    [super setUp];
    fileContext = nil;
    moc = self.eventStore.managedObjectContext;
    [moc performBlockAndWait:^{
        modEvent = [NSEntityDescription insertNewObjectForEntityForName:@"CDEStoreModificationEvent" inManagedObjectContext:moc];
        modEvent.timestamp = 123;
        modEvent.type = CDEStoreModificationEventTypeMerge;
        
        CDEEventRevision *revision = [NSEntityDescription insertNewObjectForEntityForName:@"CDEEventRevision" inManagedObjectContext:moc];
        revision.persistentStoreIdentifier = [self.eventStore persistentStoreIdentifier];
        revision.revisionNumber = 0;
        modEvent.eventRevision = revision;
        
        globalId1 = [NSEntityDescription insertNewObjectForEntityForName:@"CDEGlobalIdentifier" inManagedObjectContext:moc];
        globalId1.globalIdentifier = @"123";
        globalId1.nameOfEntity = @"Hello";
        
        globalId2 = [NSEntityDescription insertNewObjectForEntityForName:@"CDEGlobalIdentifier" inManagedObjectContext:moc];
        globalId2.globalIdentifier = @"1234";
        globalId2.nameOfEntity = @"Hello";
        
        globalId3 = [NSEntityDescription insertNewObjectForEntityForName:@"CDEGlobalIdentifier" inManagedObjectContext:moc];
        globalId3.globalIdentifier = @"1234";
        globalId3.nameOfEntity = @"Blah";
        
        objectChange1 = [NSEntityDescription insertNewObjectForEntityForName:@"CDEObjectChange" inManagedObjectContext:moc];
        objectChange1.nameOfEntity = @"Hello";
        objectChange1.type = CDEObjectChangeTypeInsert;
        objectChange1.storeModificationEvent = modEvent;
        objectChange1.globalIdentifier = globalId1;
        objectChange1.propertyChangeValues = @[];
        
        objectChange2 = [NSEntityDescription insertNewObjectForEntityForName:@"CDEObjectChange" inManagedObjectContext:moc];
        objectChange2.nameOfEntity = @"Hello";
        objectChange2.type = CDEObjectChangeTypeUpdate;
        objectChange2.storeModificationEvent = modEvent;
        objectChange2.globalIdentifier = globalId2;
        objectChange2.propertyChangeValues = @[];
        
        objectChange3 = [NSEntityDescription insertNewObjectForEntityForName:@"CDEObjectChange" inManagedObjectContext:moc];
        objectChange3.nameOfEntity = @"Blah";
        objectChange3.type = CDEObjectChangeTypeDelete;
        objectChange3.storeModificationEvent = modEvent;
        objectChange3.globalIdentifier = globalId3;
        
        [moc save:NULL];
    }];
    
    migrator = [[CDEEventMigrator alloc] initWithEventStore:(id)self.eventStore];
    
    exportedEventsFile = [NSTemporaryDirectory() stringByAppendingPathComponent:@"CDEEventMigratorTestFile"];
    [[NSFileManager defaultManager] removeItemAtPath:exportedEventsFile error:NULL];
    
    finishedAsyncOp = NO;
}

- (void)tearDown
{
    [fileContext reset];
    fileContext = nil;
    [[NSFileManager defaultManager] removeItemAtPath:exportedEventsFile error:NULL];
    [super tearDown];
}

- (void)waitForAsyncOpToFinish
{
    while (!finishedAsyncOp) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate date]];
}

- (void)migrateToFileFromRevision:(CDERevisionNumber)rev
{
    finishedAsyncOp = NO;
    [migrator migrateNonBaselineEventsSinceRevision:rev toFile:exportedEventsFile completion:^(NSError *error) {
        finishedAsyncOp = YES;
        XCTAssertNil(error, @"Error migrating to file");
    }];
    [self waitForAsyncOpToFinish];
}

- (NSManagedObjectContext *)makeFileContext
{
    NSURL *url = [NSURL fileURLWithPath:exportedEventsFile];
    NSManagedObjectModel *model = self.eventStore.managedObjectContext.persistentStoreCoordinator.managedObjectModel;
    NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
    [psc addPersistentStoreWithType:NSBinaryStoreType configuration:nil URL:url options:nil error:NULL];
    NSManagedObjectContext *newContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    newContext.persistentStoreCoordinator = psc;
    return newContext;
}

- (NSArray *)eventsInFile
{
    if (!fileContext) fileContext = [self makeFileContext];
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"CDEStoreModificationEvent"];
    NSArray *events = [fileContext executeFetchRequest:request error:NULL];
    return events;
}

- (NSArray *)changesInFile
{
    if (!fileContext) fileContext = [self makeFileContext];
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"CDEObjectChange"];
    NSArray *objectChanges = [fileContext executeFetchRequest:request error:NULL];
    return objectChanges;
}

- (void)testMigrationToFileGeneratesFile
{
    [self migrateToFileFromRevision:-1];
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:exportedEventsFile], @"File not generated");
}

- (void)testMigrationToFileMigratesEvents
{
    [self migrateToFileFromRevision:-1];
    NSArray *events = [self eventsInFile];
    XCTAssertNotNil(events, @"Fetch failed");
    XCTAssertEqual(events.count, (NSUInteger)1, @"Wrong number of events");
}

- (void)testMigrationToFileMigratesEventProperties
{
    [self migrateToFileFromRevision:-1];
    NSArray *events = [self eventsInFile];
    CDEStoreModificationEvent *event = events.lastObject;
    XCTAssertNotNil(event, @"event should not be nil");
    XCTAssertEqual(event.timestamp, (NSTimeInterval)123, @"Wrong save timestamp");
    XCTAssertEqual(event.objectChanges.count, (NSUInteger)3, @"Wrong number of changes");
}

- (void)testMigrationToFileMigratesObjectChanges
{
    [self migrateToFileFromRevision:-1];
    NSArray *changes = [self changesInFile];
    CDEObjectChange *change = changes.lastObject;
    XCTAssertNotNil(changes, @"Fetch failed");
    XCTAssertEqual(changes.count, (NSUInteger)3, @"Wrong number of changes");
    XCTAssertNotNil(change, @"change should not be nil");
    XCTAssertNotNil(change.storeModificationEvent, @"mod event should not be nil");
    XCTAssertNotNil(change.globalIdentifier, @"global id should not be nil");
}

- (void)testMigrationToFileWithNoNewEvents
{
    [self migrateToFileFromRevision:0];
    NSArray *events = [self eventsInFile];
    XCTAssertNotNil(events, @"Fetch failed");
    XCTAssertEqual(events.count, (NSUInteger)0, @"Wrong number of events");
}

- (void)testSingleEventIsMigratedWhenMultipleEventsExist
{
    [moc performBlockAndWait:^{
        // Setup extra event with a shared global identifier.
        // In the past, this caused the migration to pull in extra events. This shouldn't happen.
        CDEStoreModificationEvent *extraEvent = [NSEntityDescription insertNewObjectForEntityForName:@"CDEStoreModificationEvent" inManagedObjectContext:moc];
        extraEvent.timestamp = 124;
        extraEvent.type = CDEStoreModificationEventTypeSave;
        
        CDEEventRevision *revision = [NSEntityDescription insertNewObjectForEntityForName:@"CDEEventRevision" inManagedObjectContext:moc];
        revision.persistentStoreIdentifier = [self.eventStore persistentStoreIdentifier];
        revision.revisionNumber = 1;
        extraEvent.eventRevision = revision;
        
        CDEObjectChange *objectChange = [NSEntityDescription insertNewObjectForEntityForName:@"CDEObjectChange" inManagedObjectContext:moc];
        objectChange.nameOfEntity = @"Hello";
        objectChange.type = CDEObjectChangeTypeUpdate;
        objectChange.storeModificationEvent = extraEvent;
        objectChange.globalIdentifier = globalId1;
        objectChange.propertyChangeValues = @[];
        
        [moc save:NULL];
    }];
    
    finishedAsyncOp = NO;
    NSArray *types = @[@(CDEStoreModificationEventTypeMerge), @(CDEStoreModificationEventTypeSave)];
    [migrator migrateLocalEventWithRevision:0 toFile:exportedEventsFile allowedTypes:types completion:^(NSError *error) {
        finishedAsyncOp = YES;
        XCTAssertNil(error, @"Error migrating to file");
    }];
    [self waitForAsyncOpToFinish];
    
    NSArray *events = [self eventsInFile];
    XCTAssertEqual(events.count, (NSUInteger)1, @"Should only be one event.");
    
    CDEStoreModificationEvent *event = events.lastObject;
    XCTAssertEqual(event.eventRevision.revisionNumber, (CDERevisionNumber)0, @"Wrong revision exported");
}

- (void)testNonLocalEventsAreNotMigratedToFile
{
    [moc performBlockAndWait:^{
        modEvent.eventRevision.persistentStoreIdentifier = @"otherstore";
        XCTAssertTrue([moc save:NULL], @"Failed save");
    }];
    [self migrateToFileFromRevision:-1];

    NSArray *events = [self eventsInFile];
    XCTAssertNotNil(events, @"Fetch failed");
    XCTAssertEqual(events.count, (NSUInteger)0, @"Should be no local events");
}

- (void)testImportFromOtherStore
{
    [self migrateToFileFromRevision:-1];
    NSArray *events = [self eventsInFile];
    CDEStoreModificationEvent *event = events.lastObject;
    XCTAssertNotNil(event, @"No event in file");
    
    // Change store id in file and reimport
    event.eventRevision.persistentStoreIdentifier = @"otherstore";
    XCTAssertTrue([fileContext save:NULL], @"Save failed");
    
    finishedAsyncOp = NO;
    [migrator migrateEventsInFromFiles:@[exportedEventsFile] completion:^(NSError *error) {
        finishedAsyncOp = YES;
        XCTAssertNil(error, @"Error migrating in from file");
    }];
    [self waitForAsyncOpToFinish];
    
    [moc performBlockAndWait:^{
        NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"CDEStoreModificationEvent"];
        NSArray *storeEvents = [moc executeFetchRequest:request error:NULL];
        XCTAssertNotNil(storeEvents, @"Fetch failed");
        XCTAssertEqual(storeEvents.count, (NSUInteger)2, @"Wrong store count");
        
        CDEStoreModificationEvent *newEvent = [[storeEvents filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"eventRevision.persistentStoreIdentifier = \"otherstore\""]] lastObject];
        XCTAssertNotNil(newEvent, @"Could not retrieve new event");
        XCTAssertEqual(newEvent.objectChanges.count, (NSUInteger)3, @"Wrong number of object changes");
        
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"globalIdentifier.globalIdentifier = \"123\" AND globalIdentifier.nameOfEntity = \"Hello\""];
        CDEObjectChange *change = [[newEvent.objectChanges filteredSetUsingPredicate:predicate] anyObject];
        XCTAssertNotNil(change, @"No change found");
        
        predicate = [NSPredicate predicateWithFormat:@"globalIdentifier.globalIdentifier = \"1234\" AND globalIdentifier.nameOfEntity = \"Blah\""];
        change = [[newEvent.objectChanges filteredSetUsingPredicate:predicate] anyObject];
        XCTAssertNotNil(change, @"No change found");
        
        predicate = [NSPredicate predicateWithFormat:@"globalIdentifier.globalIdentifier = \"1234\" AND globalIdentifier.nameOfEntity = \"Blah\""];
        change = [[newEvent.objectChanges filteredSetUsingPredicate:predicate] anyObject];
        XCTAssertNotNil(change, @"No change found");
    }];
}

@end
