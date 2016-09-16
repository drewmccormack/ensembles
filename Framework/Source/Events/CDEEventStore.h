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

@property (nonatomic, strong, readonly) NSString *ensembleIdentifier;
@property (nonatomic, strong, readwrite) id <NSObject, NSCopying, NSCoding> cloudFileSystemIdentityToken;
@property (nonatomic, copy, readonly) NSString *persistentStoreIdentifier;
@property (nonatomic, assign, readonly) BOOL verifiesStoreRegistrationInCloud;

@property (nonatomic, copy, readonly) NSString *pathToEventDataRootDirectory;
@property (nonatomic, strong, readonly) NSManagedObjectContext *managedObjectContext;
@property (nonatomic, assign, readonly) BOOL containsEventData;

@property (nonatomic, strong, readonly) NSArray *incompleteEventIdentifiers;
@property (nonatomic, strong, readonly) NSArray *incompleteMandatoryEventIdentifiers;

@property (nonatomic, assign, readonly) CDERevisionNumber lastSaveRevisionSaved;
@property (nonatomic, assign, readonly) CDERevisionNumber lastMergeRevisionSaved;
@property (nonatomic, assign, readonly) CDERevisionNumber lastRevisionSaved;
@property (nonatomic, assign, readonly) CDERevisionNumber baselineRevision;

@property (nonatomic, strong, readonly) NSSet *allDataFilenames;
@property (nonatomic, strong, readonly) NSSet *newlyImportedDataFilenames;
@property (nonatomic, strong, readonly) NSSet *previouslyReferencedDataFilenames;

@property (nonatomic, copy, readwrite) NSString *identifierOfBaselineUsedToConstructStore;
@property (nonatomic, copy, readonly) NSString *currentBaselineIdentifier;

+(void)setDefaultPathToEventDataRootDirectory:(NSString *)newPath;
+(NSString *)defaultPathToEventDataRootDirectory;

+ (NSString *)pathToEventDataRootDirectoryForRootDirectory:(NSString *)rootDir ensembleIdentifier:(NSString *)identifier;

- (instancetype)initWithEnsembleIdentifier:(NSString *)identifier pathToEventDataRootDirectory:(NSString *)rootDirectory;

- (void)dismantle;

- (void)flushWithCompletion:(CDECompletionBlock)completion;

- (BOOL)removeEventStore;
- (BOOL)prepareNewEventStore:(NSError * __autoreleasing *)error;

- (void)registerIncompleteEventIdentifier:(NSString *)identifier isMandatory:(BOOL)mandatory;
- (void)deregisterIncompleteEventIdentifier:(NSString *)identifier;

- (void)removeUnusedDataWithCompletion:(CDECompletionBlock)completion;

- (BOOL)importDataFile:(NSString *)path;
- (NSString *)storeDataInFile:(NSData *)data; // Returns filename
- (BOOL)exportDataFile:(NSString *)filename toDirectory:(NSString *)dirPath;
- (NSData *)dataForFile:(NSString *)filename;

- (BOOL)removePreviouslyReferencedDataFile:(NSString *)filename;
- (BOOL)removeNewlyImportedDataFile:(NSString *)filename;
- (void)removeUnreferencedDataFiles;

@end
