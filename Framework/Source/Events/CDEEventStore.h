//
//  CDEEventStore.h
//  Test App iOS
//
//  Created by Drew McCormack on 4/15/13.
//  Copyright (c) 2013 The Mental Faculty B.V. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CDEDefines.h"
#import <CoreData/CoreData.h>

@interface CDEEventStore : NSObject <NSLocking>

@property (nonatomic, strong, readonly) NSString *ensembleIdentifier;
@property (nonatomic, strong, readwrite) id <NSObject, NSCopying, NSCoding> cloudFileSystemIdentityToken;
@property (nonatomic, copy, readonly) NSString *persistentStoreIdentifier;
@property (nonatomic, assign, readonly) BOOL verifiesStoreRegistrationInCloud;

@property (nonatomic, copy, readonly) NSString *pathToEventDataRootDirectory;
@property (nonatomic, strong, readonly) NSManagedObjectContext *managedObjectContext;
@property (nonatomic, assign, readonly) BOOL containsEventData;

@property (nonatomic, strong, readonly) NSArray *incompleteEventIdentifiers;
@property (nonatomic, strong, readonly) NSArray *incompleteMandatoryEventIdentifiers;

@property (nonatomic, assign, readonly) CDERevisionNumber lastSaveRevision;
@property (nonatomic, assign, readonly) CDERevisionNumber lastMergeRevision;
@property (nonatomic, assign, readonly) CDERevisionNumber lastRevision;
@property (nonatomic, assign, readonly) CDERevisionNumber baselineRevision;

@property (nonatomic, copy, readwrite) NSString *persistentStoreBaselineIdentifier;
@property (nonatomic, copy, readonly) NSString *currentBaselineIdentifier;

+(void)setDefaultPathToEventDataRootDirectory:(NSString *)newPath;
+(NSString *)defaultPathToEventDataRootDirectory;

- (instancetype)initWithEnsembleIdentifier:(NSString *)identifier pathToEventDataRootDirectory:(NSString *)rootDirectory;

- (void)flush:(NSError * __autoreleasing *)error;

- (BOOL)removeEventStore;
- (BOOL)prepareNewEventStore:(NSError * __autoreleasing *)error;

- (void)registerIncompleteEventIdentifier:(NSString *)identifier isMandatory:(BOOL)mandatory;
- (void)deregisterIncompleteEventIdentifier:(NSString *)identifier;

@end
