//
//  CDEAsynchronousOperation.m
//  Ensembles iOS
//
//  Created by Drew McCormack on 01/03/14.
//  Copyright (c) 2014 The Mental Faculty B.V. All rights reserved.
//

#import "CDEAsynchronousOperation.h"

@implementation CDEAsynchronousOperation {
    BOOL isFinished, isExecuting;
}

- (BOOL)isConcurrent
{
    return YES;
}

- (BOOL)isExecuting
{
    @synchronized (self) {
        return isExecuting;
    }
}

- (BOOL)isFinished
{
    @synchronized (self) {
        return isFinished;
    }
}

- (void)start
{
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:@selector(start) withObject:nil waitUntilDone:NO];
        return;
    }
    
    @synchronized (self) {
        [self willChangeValueForKey:@"isFinished"];
        [self willChangeValueForKey:@"isExecuting"];
        isFinished = NO;
        isExecuting = YES;
        [self didChangeValueForKey:@"isExecuting"];
        [self didChangeValueForKey:@"isFinished"];
    }
    
    [self beginAsynchronousTask];
}

- (void)beginAsynchronousTask
{
    // By default, just terminate immediately
    [self endAsynchronousTask];
}

- (void)endAsynchronousTask
{
    @synchronized (self) {
        [self willChangeValueForKey:@"isFinished"];
        [self willChangeValueForKey:@"isExecuting"];
        isFinished = YES;
        isExecuting = NO;
        [self didChangeValueForKey:@"isExecuting"];
        [self didChangeValueForKey:@"isFinished"];
    }
}

@end