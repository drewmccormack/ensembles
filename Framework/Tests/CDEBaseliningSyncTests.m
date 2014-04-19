//
//  CDEBaseliningSyncTests.m
//  Ensembles Mac
//
//  Created by Drew McCormack on 27/01/14.
//  Copyright (c) 2014 Drew McCormack. All rights reserved.
//

#import "CDESyncTest.h"
#import "CDEEventStore.h"
#import "CDEPersistentStoreEnsemble.h"

@interface CDEBaseliningSyncTests : CDESyncTest

@end

@implementation CDEBaseliningSyncTests {
    NSString *cloudBaselinesDir, *cloudEventsDir;
}

- (void)setUp
{
    [super setUp];
    cloudBaselinesDir = [cloudRootDir stringByAppendingPathComponent:@"com.ensembles.synctest/baselines"];
    cloudEventsDir = [cloudRootDir stringByAppendingPathComponent:@"com.ensembles.synctest/events"];
}

- (void)testCloudBaselineUniquenessWithNoInitialData
{
    [self leechStores];
    XCTAssertNil([self syncChanges], @"Sync failed");
    NSArray *baselineFiles = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:cloudBaselinesDir error:NULL];
    XCTAssertEqual(baselineFiles.count, (NSUInteger)1, @"Should only be one baseline");
    
    NSArray *eventFiles = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:cloudEventsDir error:NULL];
    XCTAssertEqual(eventFiles.count, (NSUInteger)0, @"Should only be one baseline");
}

- (void)testCloudBaselineFileContentDuringLeechAndSync
{
    NSManagedObject *parentOnDevice1 = [NSEntityDescription insertNewObjectForEntityForName:@"Parent" inManagedObjectContext:context1];
    [parentOnDevice1 setValue:@"bob" forKey:@"name"];
    XCTAssertTrue([context1 save:NULL], @"Could not save");
    
    // Leech and merge first store
    [ensemble1 leechPersistentStoreWithCompletion:^(NSError *error) {
        XCTAssertNil(error, @"Error leeching first store");
        [self completeAsync];
    }];
    [self waitForAsync];
    [self mergeEnsemble:ensemble1];
    
    // Check cloud files and contents
    NSArray *baselineFiles = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:cloudBaselinesDir error:NULL];
    NSString *baseline1 = baselineFiles.lastObject;
    NSString *baseline1Path = [cloudBaselinesDir stringByAppendingPathComponent:baseline1];
    XCTAssertEqual(baselineFiles.count, (NSUInteger)1, @"Should be a baseline");
    
    NSArray *events = [self fetchEventsInEventFile:baseline1Path];
    XCTAssertEqual(events.count, (NSUInteger)1, @"Should be a parent object in baseline file after the first context first merges");
    
    // Leech second store
    [ensemble2 leechPersistentStoreWithCompletion:^(NSError *error) {
        XCTAssertNil(error, @"Error leeching second store");
        [self completeAsync];
    }];
    [self waitForAsync];
    
    // Check cloud file is unchanged
    events = [self fetchEventsInEventFile:baseline1Path];
    XCTAssertEqual(events.count, (NSUInteger)1, @"Should be a parent object in baseline before store two merges");
    
    // Merge second store. Should consolidate baselines.
    [self mergeEnsemble:ensemble2];
    
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:baseline1Path], @"After second store merges, first baseline should not exist");
    
    // Check new baseline file
    baselineFiles = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:cloudBaselinesDir error:NULL];
    NSString *baseline2 = baselineFiles.lastObject;
    NSString *baseline2Path = [cloudBaselinesDir stringByAppendingPathComponent:baseline2];
    XCTAssertEqual(baselineFiles.count, (NSUInteger)1, @"Should be a baseline");
    XCTAssertNotEqualObjects(baseline1, baseline2, @"Baselines not have same file name");
    
    // Check content
    events = [self fetchEventsInEventFile:baseline2Path];
    XCTAssertEqual(events.count, (NSUInteger)1, @"Should have one baseline");
    
    // Check things are still OK after several merges
    [self syncChanges];
    baselineFiles = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:cloudBaselinesDir error:NULL];
    XCTAssertEqual(baselineFiles.count, (NSUInteger)1, @"Should be a baseline");
}

- (void)testBaselineConsolidation
{    
    NSManagedObject *parentOnDevice1 = [NSEntityDescription insertNewObjectForEntityForName:@"Parent" inManagedObjectContext:context1];
    [parentOnDevice1 setValue:@"bob" forKey:@"name"];
    XCTAssertTrue([context1 save:NULL], @"Could not save");
    
    NSManagedObject *parentOnDevice2 = [NSEntityDescription insertNewObjectForEntityForName:@"Parent" inManagedObjectContext:context2];
    [parentOnDevice2 setValue:@"john" forKey:@"name"];
    XCTAssertTrue([context2 save:NULL], @"Could not save");
    
    [self leechStores];

    NSArray *baselineFiles = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:cloudBaselinesDir error:NULL];
    XCTAssertEqual(baselineFiles.count, (NSUInteger)2, @"Should be two baseline files after leeching");

    [self mergeEnsemble:ensemble1];
    
    baselineFiles = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:cloudBaselinesDir error:NULL];
    XCTAssertEqual(baselineFiles.count, (NSUInteger)1, @"Should only be one baseline files after merge");
    
    [self mergeEnsemble:ensemble2];
    
    baselineFiles = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:cloudBaselinesDir error:NULL];
    XCTAssertEqual(baselineFiles.count, (NSUInteger)1, @"Should only be one baseline files after merge");
    
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Parent"];
    NSArray *parents = [context1 executeFetchRequest:fetch error:NULL];
    XCTAssertEqual(parents.count, (NSUInteger)2, @"Should be a parent object in context1");
    
    parents = [context2 executeFetchRequest:fetch error:NULL];
    XCTAssertEqual(parents.count, (NSUInteger)2, @"Should be a parent object in context2");
}

- (void)testRebasingIsTriggered
{
    [self leechStores];
    [self mergeEnsemble:ensemble1];

    for (NSUInteger i = 0; i < 500; i++) {
        NSManagedObject *parentOnDevice1 = [NSEntityDescription insertNewObjectForEntityForName:@"Parent" inManagedObjectContext:context1];
        [parentOnDevice1 setValue:@"bob" forKey:@"name"];
    }
    XCTAssertTrue([context1 save:NULL], @"Could not save");
    
    // Each update is worth 0.2, so we need more than 5 for each object to trigger a rebase.
    NSArray *parents = [context1 executeFetchRequest:[NSFetchRequest fetchRequestWithEntityName:@"Parent"] error:NULL];
    for (NSInteger i = 0; i < 6; i++) {
        for (id parent in parents) {
            [parent setValue:@"tom" forKey:@"name"];
        }
        XCTAssertTrue([context1 save:NULL], @"Could not save");
    }
    
    [self mergeEnsemble:ensemble1];
    
    NSArray *baselineFiles = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:cloudBaselinesDir error:NULL];
    NSArray *eventFiles = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:cloudEventsDir error:NULL];
    XCTAssertEqual(baselineFiles.count, (NSUInteger)1, @"Should be one baseline file");
    XCTAssertEqual(eventFiles.count, (NSUInteger)0, @"Should be no event file");
    
    [self mergeEnsemble:ensemble2];
    
    NSArray *parentsIn2 = [context2 executeFetchRequest:[NSFetchRequest fetchRequestWithEntityName:@"Parent"] error:NULL];
    XCTAssertEqual(parentsIn2.count, (NSUInteger)500, @"Wrong parent count in second context");
}

- (void)testRebasingGoesToMinimumGlobalCountFromAnyDevice
{
    [self leechStores];
    [self mergeEnsemble:ensemble1];
    
    NSArray *baselineFiles = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:cloudBaselinesDir error:NULL];
    NSArray *eventFiles = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:cloudEventsDir error:NULL];
    XCTAssertEqual(baselineFiles.count, (NSUInteger)1, @"Should be one baseline file");
    XCTAssertEqual(eventFiles.count, (NSUInteger)0, @"Should be no event file");

    // Should generate event with global count 1
    for (NSUInteger i = 0; i < 500; i++) {
        NSManagedObject *parentOnDevice2 = [NSEntityDescription insertNewObjectForEntityForName:@"Parent" inManagedObjectContext:context2];
        [parentOnDevice2 setValue:@"jane" forKey:@"name"];
    }
    XCTAssertTrue([context2 save:NULL], @"Could not save");
    [self mergeEnsemble:ensemble2];
    
    baselineFiles = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:cloudBaselinesDir error:NULL];
    eventFiles = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:cloudEventsDir error:NULL];
    XCTAssertEqual(baselineFiles.count, (NSUInteger)1, @"Should be one baseline file");
    XCTAssertEqual(eventFiles.count, (NSUInteger)1, @"Should be one event file");
    
    // Should generate event with global count 1
    for (NSUInteger i = 0; i < 500; i++) {
        NSManagedObject *parentOnDevice1 = [NSEntityDescription insertNewObjectForEntityForName:@"Parent" inManagedObjectContext:context1];
        [parentOnDevice1 setValue:@"bob" forKey:@"name"];
    }
    XCTAssertTrue([context1 save:NULL], @"Could not save");
    
    // Should generate events with global counts 2-12
    NSArray *parents = [context1 executeFetchRequest:[NSFetchRequest fetchRequestWithEntityName:@"Parent"] error:NULL];
    for (NSInteger i = 0; i < 11; i++) {
        for (id parent in parents) {
            [parent setValue:@"tom" forKey:@"name"];
        }
        XCTAssertTrue([context1 save:NULL], @"Could not save");
    }
    
    // Should generate a merge event with global count 13, and rebase up to global count 1 (lowest from any store)
    [self mergeEnsemble:ensemble1];
    
    baselineFiles = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:cloudBaselinesDir error:NULL];
    eventFiles = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:cloudEventsDir error:NULL];
    XCTAssertEqual(baselineFiles.count, (NSUInteger)1, @"Should be one baseline file");
    XCTAssertEqual(eventFiles.count, (NSUInteger)11, @"Should be 5 events from store 1 after rebasing");
    XCTAssertEqual([baselineFiles.lastObject integerValue], (NSInteger)1, @"Wrong global count for baseline");
}

- (NSManagedObjectContext *)eventFileContextForURL:(NSURL *)baselineURL
{
    NSManagedObjectContext *baselineContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSConfinementConcurrencyType];
    NSURL *modelURL = [[NSBundle bundleForClass:[CDEEventStore class]] URLForResource:@"CDEEventStoreModel" withExtension:@"momd"];
    NSManagedObjectModel *eventModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
    NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:eventModel];
    baselineContext.persistentStoreCoordinator = coordinator;
    NSPersistentStore *store = [coordinator addPersistentStoreWithType:NSBinaryStoreType configuration:nil URL:baselineURL options:nil error:NULL];
    XCTAssertNotNil(store, @"Store was nil");
    return baselineContext;
}

- (NSArray *)fetchEventsInEventFile:(NSString *)path
{
    NSManagedObjectContext *context = [self eventFileContextForURL:[NSURL fileURLWithPath:path]];
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"CDEStoreModificationEvent"];
    NSArray *events = [context executeFetchRequest:fetch error:NULL];
    return events;
}

@end
