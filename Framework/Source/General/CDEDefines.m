//
//  CDEDefines.m
//  Ensembles
//
//  Created by Drew McCormack on 4/11/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import "CDEDefines.h"

NSString * const CDEException = @"CDEException";
NSString * const CDEErrorDomain = @"CDEErrorDomain";

NSUInteger currentLoggingLevel = CDELoggingLevelError;

CDELogCallbackFunction CDECurrentLogCallbackFunction = NSLog;

void CDESetCurrentLoggingLevel(NSUInteger newLevel)
{
    currentLoggingLevel = newLevel;
}

NSUInteger CDECurrentLoggingLevel(void)
{
    return currentLoggingLevel;
}

void CDESetLogCallback(CDELogCallbackFunction logFunction)
{
    CDECurrentLogCallbackFunction = logFunction;
}

CDELogCallbackFunction CDEGetLogCallback()
{
    return CDECurrentLogCallbackFunction;
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