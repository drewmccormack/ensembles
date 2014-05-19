//
//  CDEEventStoreTestCase.h
//  Ensembles
//
//  Created by Drew McCormack on 01/07/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "CDEDefines.h"  
#import "CDEObjectChange.h"


@class CDEEventRevision;
@class CDEStoreModificationEvent;
@class CDEGlobalIdentifier;


@interface CDEMockEventStore : NSObject 

@property (strong) NSManagedObjectContext *managedObjectContext;
@property (readwrite) BOOL containsEventData;
@property (nonatomic, readwrite) NSString *persistentStoreIdentifier;
@property (nonatomic) NSString *identifierOfBaselineUsedToConstructStore;
@property (nonatomic) NSString *currentBaselineIdentifier;
@property (readwrite) CDERevisionNumber lastRevisionSaved, lastSaveRevisionSaved, lastMergeRevisionSaved;
@property (readwrite) NSString *pathToEventDataRootDirectory;
@property (readwrite) NSSet *allDataFilenames;

- (void)updateRevisionsForSave;
- (void)updateRevisionsForMerge;

- (void)registerIncompleteEventIdentifier:(NSString *)identifier isMandatory:(BOOL)mandatory;
- (void)deregisterIncompleteEventIdentifier:(NSString *)identifier;

@end


@interface CDEEventStoreTestCase : XCTestCase

@property (strong) CDEMockEventStore *eventStore;
@property (strong) NSManagedObjectContext *testManagedObjectContext;
@property (readonly) NSURL *testStoreURL; // Only set for a disk store
@property (readonly) NSURL *testModelURL;

+ (void)setUseDiskStore:(BOOL)yn;

- (CDEEventRevision *)addEventRevisionForStore:(NSString *)store revision:(CDERevisionNumber)revision;

- (CDEStoreModificationEvent *)addModEventForStore:(NSString *)store revision:(CDERevisionNumber)rev timestamp:(NSTimeInterval)timestamp;
- (CDEStoreModificationEvent *)addModEventForStore:(NSString *)store revision:(CDERevisionNumber)rev globalCount:(CDEGlobalCount)globalCount timestamp:(NSTimeInterval)timestamp;

- (CDEGlobalIdentifier *)addGlobalIdentifier:(NSString *)identifier forEntity:(NSString *)entity;
- (CDEObjectChange *)addObjectChangeOfType:(CDEObjectChangeType)type withGlobalIdentifier:(CDEGlobalIdentifier *)globalIdentifier toEvent:(CDEStoreModificationEvent *)event;

- (CDEPropertyChangeValue *)attributeChangeForName:(NSString *)name value:(id)value;
- (CDEPropertyChangeValue *)toOneRelationshipChangeForName:(NSString *)name relatedIdentifier:(id)newId;
- (CDEPropertyChangeValue *)toManyRelationshipChangeForName:(NSString *)name addedIdentifiers:(NSArray *)added removedIdentifiers:(NSArray *)removed;

@end
