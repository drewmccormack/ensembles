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
    CDEErrorCodeUnknown                     = -1,
    CDEErrorCodeCancelled                   = 101,
    CDEErrorCodeMultipleErrors              = 102,
    CDEErrorCodeDisallowedStateChange       = 103,
    CDEErrorCodeExceptionRaised             = 104,
    CDEErrorCodeFailedToWriteFile           = 105,
    CDEErrorCodeFileCoordinatorTimedOut     = 106, // Usually because a service like iCloud is still downloading the file
    CDEErrorCodeFileAccessFailed            = 107,
    CDEErrorCodeDiscontinuousRevisions      = 200,
    CDEErrorCodeMissingDependencies         = 201,
    CDEErrorCodeCloudIdentityChanged        = 202,
    CDEErrorCodeDataCorruptionDetected      = 203,
    CDEErrorCodeUnknownModelVersion         = 204,
    CDEErrorCodeStoreUnregistered           = 205,
    CDEErrorSaveOccurredDuringLeeching      = 206,
    CDEErrorCodeSaveOccurredDuringMerge     = 207,
    CDEErrorCodeNetworkError                = 1000,
    CDEErrorCodeServerError                 = 1001,
    CDEErrorConnectionError                 = 1002,
    CDEErrorCodeAuthenticationFailure       = 1003,
    CDEErrorCodeSyncDataWasReset            = 2000,
};


#pragma mark Logging

typedef NS_ENUM(NSUInteger, CDELoggingLevel) {
    CDELoggingLevelNone,
    CDELoggingLevelError,
    CDELoggingLevelWarning,
    CDELoggingLevelVerbose
};

void CDELog(NSUInteger level, NSString *format, ...);
void CDESetCurrentLoggingLevel(NSUInteger newLevel);


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

