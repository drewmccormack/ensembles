//
//  CDEEventStoreTestCase.m
//  Ensembles
//
//  Created by Drew McCormack on 01/07/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import "CDEEventStoreTestCase.h"
#import "CDEStoreModificationEvent.h"
#import "CDEGlobalIdentifier.h"
#import "CDEPropertyChangeValue.h"
#import "CDEEventRevision.h"

static BOOL useDiskStore = NO;
static NSString *testRootDirectory;
static NSString *testStoreFile;

@implementation CDEMockEventStore {
    NSRecursiveLock *_lock;
}

- (instancetype)init
{
    self = [super init];
    _lastRevisionSaved = -1;
    _lastSaveRevisionSaved = -1;
    _lastMergeRevisionSaved = -1;
    _identifierOfBaselineUsedToConstructStore = @"store1baseline";
    _currentBaselineIdentifier = @"store1";
    _allDataFilenames = [NSSet set];
    _lock = [[NSRecursiveLock alloc] init];
    return self;
}

- (void)updateRevisionsForSave
{
    _lastRevisionSaved++;
    _lastSaveRevisionSaved = _lastRevisionSaved;
}

- (void)updateRevisionsForMerge
{
    _lastRevisionSaved++;
    _lastMergeRevisionSaved = _lastRevisionSaved;
}

- (NSString *)persistentStoreIdentifier
{
    if (_persistentStoreIdentifier) return _persistentStoreIdentifier;
    return @"store1";
}

- (NSString *)ensembleIdentifier
{
    return @"ensemble1";
}

- (void)registerIncompleteEventIdentifier:(NSString *)identifier isMandatory:(BOOL)mandatory
{
}

- (void)deregisterIncompleteEventIdentifier:(NSString *)identifier
{
}

@end


@implementation CDEEventStoreTestCase

@synthesize eventStore = eventStore;
@synthesize testManagedObjectContext = testManagedObjectContext;
@synthesize testStoreURL = testStoreURL;
@synthesize testModelURL = testModelURL;

+ (void)initialize
{
    testRootDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:@"CDEEventStoreTestCase"];
    testStoreFile = [testRootDirectory stringByAppendingPathComponent:@"store.sql"];
}

+ (void)setUseDiskStore:(BOOL)yn
{
    useDiskStore = yn;
}

+ (void)setUp
{
    [super setUp];
    [self setUseDiskStore:NO];
}

- (void)setUp
{
    [super setUp];
    
    // Event store
    NSURL *modelURL = [[NSBundle bundleForClass:self.class] URLForResource:@"CDEEventStoreModel" withExtension:@"momd"];
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
    NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
    NSDictionary *options = @{NSMigratePersistentStoresAutomaticallyOption: @YES, NSInferMappingModelAutomaticallyOption: @YES};
    [psc addPersistentStoreWithType:NSInMemoryStoreType configuration:nil URL:nil options:options error:NULL];
    
    eventStore = [[CDEMockEventStore alloc] init];
    eventStore.containsEventData = YES;
    eventStore.managedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    [eventStore.managedObjectContext performBlockAndWait:^{
        eventStore.managedObjectContext.persistentStoreCoordinator = psc;
    }];
    
    // Test Coordinator
    testModelURL = [[NSBundle bundleForClass:self.class] URLForResource:@"CDEStoreModificationEventTestsModel" withExtension:@"momd"];
    NSManagedObjectModel *testModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:testModelURL];
    NSPersistentStoreCoordinator *testPSC = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:testModel];
    
    // Test Store
    if (useDiskStore) {
        [[NSFileManager defaultManager] createDirectoryAtPath:testRootDirectory withIntermediateDirectories:YES attributes:nil error:NULL];
        testStoreURL = [NSURL fileURLWithPath:testStoreFile];
        [testPSC addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:testStoreURL options:nil error:NULL];
    }
    else {
        [testPSC addPersistentStoreWithType:NSInMemoryStoreType configuration:nil URL:nil options:nil error:NULL];
    }
    
    testManagedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    [testManagedObjectContext performBlockAndWait:^{
        testManagedObjectContext.persistentStoreCoordinator = testPSC;
    }];
}

- (void)tearDown
{    
    [eventStore.managedObjectContext performBlockAndWait:^{
        [eventStore.managedObjectContext reset];
        eventStore = nil;
    }];
    
    [testManagedObjectContext performBlockAndWait:^{
        [testManagedObjectContext reset];
    }];
    testManagedObjectContext = nil;
    
    [[NSFileManager defaultManager] removeItemAtPath:testRootDirectory error:NULL];
    
    testStoreURL = nil;
    
    [super tearDown];
}

- (CDEEventRevision *)addEventRevisionForStore:(NSString *)store revision:(CDERevisionNumber)revision
{
    NSManagedObjectContext *moc = self.eventStore.managedObjectContext;
    CDEEventRevision *eventRevision = [NSEntityDescription insertNewObjectForEntityForName:@"CDEEventRevision" inManagedObjectContext:moc];
    eventRevision.persistentStoreIdentifier = store;
    eventRevision.revisionNumber = revision;
    return eventRevision;
}

- (CDEStoreModificationEvent *)addModEventForStore:(NSString *)store revision:(CDERevisionNumber)rev timestamp:(NSTimeInterval)timestamp
{
    return [self addModEventForStore:store revision:rev globalCount:0 timestamp:timestamp];
}

- (CDEStoreModificationEvent *)addModEventForStore:(NSString *)store revision:(CDERevisionNumber)rev globalCount:(CDEGlobalCount)globalCount timestamp:(NSTimeInterval)timestamp
{
    NSManagedObjectContext *moc = self.eventStore.managedObjectContext;
    CDEStoreModificationEvent *event = [NSEntityDescription insertNewObjectForEntityForName:@"CDEStoreModificationEvent" inManagedObjectContext:moc];
    event.type = CDEStoreModificationEventTypeSave;
    event.timestamp = timestamp;
    event.eventRevision = [self addEventRevisionForStore:store revision:rev];
    event.globalCount = globalCount;
    return event;
}

- (CDEGlobalIdentifier *)addGlobalIdentifier:(NSString *)identifier forEntity:(NSString *)entity
{
    NSManagedObjectContext *moc = self.eventStore.managedObjectContext;
    CDEGlobalIdentifier *result = [NSEntityDescription insertNewObjectForEntityForName:@"CDEGlobalIdentifier" inManagedObjectContext:moc];
    result.globalIdentifier = identifier;
    result.storeURI = nil;
    result.nameOfEntity = entity;
    return result;
}

- (CDEObjectChange *)addObjectChangeOfType:(CDEObjectChangeType)type withGlobalIdentifier:(CDEGlobalIdentifier *)globalIdentifier toEvent:(CDEStoreModificationEvent *)event
{
    NSManagedObjectContext *moc = self.eventStore.managedObjectContext;
    CDEObjectChange *change = [NSEntityDescription insertNewObjectForEntityForName:@"CDEObjectChange" inManagedObjectContext:moc];
    change.nameOfEntity = globalIdentifier.nameOfEntity;
    change.type = type;
    change.storeModificationEvent = event;
    change.globalIdentifier = globalIdentifier;
    return change;
}

- (CDEPropertyChangeValue *)attributeChangeForName:(NSString *)name value:(id)value
{
    CDEPropertyChangeValue *newValue = [[CDEPropertyChangeValue alloc] initWithType:CDEPropertyChangeTypeAttribute propertyName:name];
    newValue.value = value;
    return newValue;
}

- (CDEPropertyChangeValue *)toOneRelationshipChangeForName:(NSString *)name relatedIdentifier:(id)newId
{
    CDEPropertyChangeValue *newValue = [[CDEPropertyChangeValue alloc] initWithType:CDEPropertyChangeTypeToOneRelationship propertyName:name];
    newValue.relatedIdentifier = newId;
    return newValue;
}

- (CDEPropertyChangeValue *)toManyRelationshipChangeForName:(NSString *)name addedIdentifiers:(NSArray *)added removedIdentifiers:(NSArray *)removed
{
    CDEPropertyChangeValue *newValue = [[CDEPropertyChangeValue alloc] initWithType:CDEPropertyChangeTypeToManyRelationship propertyName:name];
    newValue.addedIdentifiers = [NSSet setWithArray:added];
    newValue.removedIdentifiers = [NSSet setWithArray:removed];
    return newValue;
}

@end
