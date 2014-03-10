//
//  CDEDefines.h
//  Ensembles
//
//  Created by Drew McCormack on 4/11/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import <Foundation/Foundation.h>

#pragma mark Exceptions

extern NSString * const CDEException;
extern NSString * const CDEErrorDomain;


#pragma mark Types

typedef int64_t CDERevisionNumber;
typedef int64_t CDEGlobalCount;


#pragma mark Errors

typedef NS_ENUM(NSInteger, CDEErrorCode) {
    /// An unknown error occurred.
    CDEErrorCodeUnknown                     = -1,
    
    /// The operation was cancelled.
    CDEErrorCodeCancelled                   = 101,
    
    /// Multiple errors occurred. The `errors` key of `userInfo` has them all.
    CDEErrorCodeMultipleErrors              = 102,
    
    /// A request for an invalid state transition was made. Eg Merge during leeching.
    CDEErrorCodeDisallowedStateChange       = 103,
    
    /// An unexpected internal exception was raised and caught.
    CDEErrorCodeExceptionRaised             = 104,
    
    /// An attempt to write a file failed.
    CDEErrorCodeFailedToWriteFile           = 105,
    
    /// Accessing a file with a coordinator timed out. Often because iCloud is still downloading. Retry later.
    CDEErrorCodeFileCoordinatorTimedOut     = 106,
    
    /// An attempt to access a file failed.
    CDEErrorCodeFileAccessFailed            = 107,
    
    /// Some change sets are missing. Usually temporarily missing data. Retry a bit later.
    CDEErrorCodeDiscontinuousRevisions      = 200,
    
    /// Some change sets are missing. Usually temporarily missing data. Retry a bit later.
    CDEErrorCodeMissingDependencies         = 201,
    
    /// User changed cloud identity. This forces a deleech.
    CDEErrorCodeCloudIdentityChanged        = 202,
    
    /// Some left over, incomplete data has been found. Probably due to a crash.
    CDEErrorCodeDataCorruptionDetected      = 203,
    
    /// A model version exists in the cloud that is unknown. Merge will succeed again after update.
    CDEErrorCodeUnknownModelVersion         = 204,
    
    /// The ensemble is no longer registered in the cloud. Usually due to cloud data removal.
    CDEErrorCodeStoreUnregistered           = 205,
    
    /// A save to the persistent store occurred during leech. This is not allowed.
    CDEErrorCodeSaveOccurredDuringLeeching  = 206,
    
    /// A save to the persistent store occurred during merge. You can simply retry the merge.
    CDEErrorCodeSaveOccurredDuringMerge     = 207,
    
    /// No snapshot of existing cloud files exists. This is a bug in the framework.
    CDEErrorCodeMissingCloudSnapshot        = 208,
    
    /// There is no persistent store at the path. Ensure a store exists and try again.
    CDEErrorCodeMissingStore                = 209,
    
    /// Files used to store large NSData attributes are missing. Usually temporary. Retry a bit later.
    CDEErrorCodeMissingDataFiles            = 210,
    
    /// A generic networking error occurred.
    CDEErrorCodeNetworkError                = 1000,
    
    /// An error from a server was received.
    CDEErrorCodeServerError                 = 1001,
    
    /// The cloud file system could not connect.
    CDEErrorCodeConnectionError             = 1002,
    
    /// The user failed to authenticate.
    CDEErrorCodeAuthenticationFailure       = 1003,
    
    /// A sync data reset occurred.
    CDEErrorCodeSyncDataWasReset            = 2000,
};


#pragma mark Logging

typedef NS_ENUM(NSUInteger, CDELoggingLevel) {
    /// No logging.
    CDELoggingLevelNone,
    
    /// Log only errors.
    CDELoggingLevelError,
    
    /// Log warnings and errors.
    CDELoggingLevelWarning,
    
    /// Log everything.
    CDELoggingLevelVerbose
};

// Log callback support. Use CDESetLogCallback to supply a function that
// will receive all Ensembles logging.  Default log output goes to NSLog().
typedef void (*CDELogCallbackFunction)(NSString *format, ...);
void CDESetLogCallback(CDELogCallbackFunction callback);
extern CDELogCallbackFunction CDECurrentLogCallbackFunction;

#define CDELog(level, ...)                                                                                  \
do {                                                                                                        \
    if (CDECurrentLoggingLevel() >= level) {                                                                \
CDECurrentLogCallbackFunction(@"%s line %d: %@", __PRETTY_FUNCTION__, __LINE__, [NSString stringWithFormat:__VA_ARGS__]);   \
    }                                                                                                       \
} while (0)


/**
 Set the level of messages to be printed to the console.
 */
void CDESetCurrentLoggingLevel(NSUInteger newLevel);
NSUInteger CDECurrentLoggingLevel(void);


#pragma mark Callbacks

typedef void (^CDECodeBlock)(void);
typedef void (^CDEBooleanQueryBlock)(NSError *error, BOOL result);
typedef void (^CDECompletionBlock)(NSError *error);


#pragma mark Functions

void CDEDispatchCompletionBlockToMainQueue(CDECompletionBlock block, NSError *error);
CDECompletionBlock CDEMainQueueCompletionFromCompletion(CDECompletionBlock block);


#pragma mark Useful Macros

#define CDENSNullToNil(object) ((id)object == (id)[NSNull null] ? nil : object)
#define CDENilToNSNull(object) (object ? : [NSNull null])

