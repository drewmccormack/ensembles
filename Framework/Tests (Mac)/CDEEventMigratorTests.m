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
    CDEGlobalIdentifier *globalId1, *globalId2;
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
        
        objectChange1 = [NSEntityDescription insertNewObjectForEntityForName:@"CDEObjectChange" inManagedObjectContext:moc];
        objectChange1.nameOfEntity = @"Hello";
        objectChange1.type = CDEObjectChangeTypeInsert;
        objectChange1.storeModificationEvent = modEvent;
        objectChange1.globalIdentifier = globalId1;
        objectChange1.propertyChangeValues = @[@"a", @"b"];
        
        objectChange2 = [NSEntityDescription insertNewObjectForEntityForName:@"CDEObjectChange" inManagedObjectContext:moc];
        objectChange2.nameOfEntity = @"Blah";
        objectChange2.type = CDEObjectChangeTypeUpdate;
        objectChange2.storeModificationEvent = modEvent;
        objectChange2.globalIdentifier = globalId2;
        objectChange2.propertyChangeValues = @[@"a", @"b"];
        
        objectChange3 = [NSEntityDescription insertNewObjectForEntityForName:@"CDEObjectChange" inManagedObjectContext:moc];
        objectChange3.nameOfEntity = @"Blah";
        objectChange3.type = CDEObjectChangeTypeDelete;
        objectChange3.storeModificationEvent = modEvent;
        objectChange3.globalIdentifier = globalId2;
        
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
    [migrator migrateLocalEventsSinceRevision:rev toFile:exportedEventsFile completion:^(NSError *error) {
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

- (void)testReimportAddsNoNewEvents
{
    [migrator migrateLocalEventsSinceRevision:-1 toFile:exportedEventsFile completion:^(NSError *error) {
        finishedAsyncOp = YES;
        XCTAssertNil(error, @"Error migrating to file");
    }];
    [self waitForAsyncOpToFinish];
    
    finishedAsyncOp = NO;
    [migrator migrateEventsInFromFiles:@[exportedEventsFile] completion:^(NSError *error) {
        finishedAsyncOp = YES;
        XCTAssertNil(error, @"Error migrating in from file");
    }];
    [self waitForAsyncOpToFinish];
    
    [moc performBlockAndWait:^{
        NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"CDEStoreModificationEvent"];
        NSArray *events = [moc executeFetchRequest:request error:NULL];
        XCTAssertNotNil(events, @"Fetch failed");
        XCTAssertEqual(events.count, (NSUInteger)1, @"Wrong store count");
    }];
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
        
        CDEObjectChange *change = newEvent.objectChanges.anyObject;
        XCTAssertNotNil(change.globalIdentifier, @"No global id");
    }];
}

@end
