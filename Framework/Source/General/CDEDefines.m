//
//  CDEDefines.m
//  SyncophantFramework
//
//  Created by Drew McCormack on 4/11/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import "CDEDefines.h"

NSString * const CDEException = @"CDEException";
NSString * const CDEErrorDomain = @"CDEErrorDomain";

NSUInteger currentLoggingLevel = CDELoggingLevelError;

void CDESetCurrentLoggingLevel(NSUInteger newLevel)
{
    currentLoggingLevel = newLevel;
}

void CDELog(NSUInteger level, NSString *format, ...)
{
    va_list arglist;
    va_start(arglist, format);
    if (currentLoggingLevel >= level) NSLogv(format, arglist);
    va_end(arglist);
}

void CDEDispatchCompletionBlockToMainQueue(CDECompletionBlock block, NSError *error)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (block) block(error);
    });
}

CDECompletionBlock CDEMainQueueCompletionFromCompletion(CDECompletionBlock block)
{
    if (!block) return NULL;
    return ^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            block(error);
        });
    };
}