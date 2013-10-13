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

@interface CDEEventStore : NSObject

@property (nonatomic, readonly) NSString *ensembleIdentifier;
@property (nonatomic, readwrite) id <NSObject, NSCopying, NSCoding> cloudFileSystemIdentityToken;
@property (nonatomic, readonly, copy) NSString *pathToEventDataRootDirectory;
@property (nonatomic, readonly, copy) NSString *persistentStoreIdentifier;
@property (nonatomic, readonly) NSManagedObjectContext *managedObjectContext;
@property (nonatomic, readonly) BOOL containsEventData;

@property (nonatomic, readonly) NSArray *incompleteEventIdentifiers;
@property (nonatomic, readonly) NSArray *incompleteMandatoryEventIdentifiers;

@property (nonatomic, readonly) CDERevisionNumber lastSaveRevision;
@property (nonatomic, readonly) CDERevisionNumber lastMergeRevision;
@property (nonatomic, readonly) CDERevisionNumber lastRevision;

+(void)setDefaultPathToEventDataRootDirectory:(NSString *)newPath;
+(NSString *)defaultPathToEventDataRootDirectory;

- (instancetype)initWithEnsembleIdentifier:(NSString *)identifier pathToEventDataRootDirectory:(NSString *)rootDirectory;

- (void)flush:(NSError * __autoreleasing *)error;

- (BOOL)removeEventStore;
- (BOOL)prepareNewEventStore:(NSError * __autoreleasing *)error;

- (void)registerIncompleteEventIdentifier:(NSString *)identifier isMandatory:(BOOL)mandatory;
- (void)deregisterIncompleteEventIdentifier:(NSString *)identifier;

@end
