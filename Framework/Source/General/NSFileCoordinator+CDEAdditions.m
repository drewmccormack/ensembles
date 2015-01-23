//
//  NSFileCoordinator+CDEAdditions.m
//  Ensembles Mac
//
//  Created by Drew McCormack on 23/01/15.
//  Copyright (c) 2015 Drew McCormack. All rights reserved.
//

#import "NSFileCoordinator+CDEAdditions.h"
#import "CDEDefines.h"


@implementation NSFileCoordinator (CDEAdditions)

#ifndef __clang_analyzer__

+ (dispatch_queue_t)cde_timeoutQueue
{
    static dispatch_queue_t queue = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.mentalfaculty.ensembles.queue.filecoordinatortimeout", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

- (void)cde_coordinateReadingItemAtURL:(NSURL *)url options:(NSFileCoordinatorReadingOptions)options timeout:(NSTimeInterval)timeout error:(NSError *__autoreleasing *)outError byAccessor:(void (^)(NSURL *))reader
{
    __block BOOL coordinatorExecuted = NO;
    __block NSError *timeoutError = nil;
    
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, timeout * NSEC_PER_SEC);
    dispatch_after(popTime, self.class.cde_timeoutQueue, ^{
        if (!coordinatorExecuted) {
            [self cancel];
            timeoutError = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeFileCoordinatorTimedOut userInfo:nil];
        }
    });
    
    NSError *fileCoordinatorError = nil;
    [self coordinateReadingItemAtURL:url options:options error:&fileCoordinatorError byAccessor:^(NSURL *newURL) {
        dispatch_sync(self.class.cde_timeoutQueue, ^{ coordinatorExecuted = YES; });
        if (timeoutError) return;
        reader(newURL);
    }];
    
    if (timeoutError) *outError = timeoutError;
    if (fileCoordinatorError) *outError = fileCoordinatorError;
}

- (void)cde_coordinateReadingItemAtURL:(NSURL *)readingURL options:(NSFileCoordinatorReadingOptions)readingOptions writingItemAtURL:(NSURL *)writingURL options:(NSFileCoordinatorWritingOptions)writingOptions timeout:(NSTimeInterval)timeout error:(NSError *__autoreleasing *)outError byAccessor:(void (^)(NSURL *, NSURL *))readerWriter
{
    __block BOOL coordinatorExecuted = NO;
    __block NSError *timeoutError = nil;
    
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, timeout * NSEC_PER_SEC);
    dispatch_after(popTime, self.class.cde_timeoutQueue, ^{
        if (!coordinatorExecuted) {
            [self cancel];
            timeoutError = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeFileCoordinatorTimedOut userInfo:nil];
        }
    });
    
    NSError *fileCoordinatorError = nil;
    [self coordinateReadingItemAtURL:readingURL options:readingOptions writingItemAtURL:writingURL options:writingOptions error:&fileCoordinatorError byAccessor:^(NSURL *newReadingURL, NSURL *newWritingURL) {
        dispatch_sync(self.class.cde_timeoutQueue, ^{ coordinatorExecuted = YES; });
        if (timeoutError) return;
        readerWriter(newReadingURL, newWritingURL);
    }];
    
    if (timeoutError) *outError = timeoutError;
    if (fileCoordinatorError) *outError = fileCoordinatorError;
}

- (void)cde_coordinateWritingItemAtURL:(NSURL *)url options:(NSFileCoordinatorWritingOptions)options timeout:(NSTimeInterval)timeout error:(NSError *__autoreleasing *)outError byAccessor:(void (^)(NSURL *))writer
{
    __block BOOL coordinatorExecuted = NO;
    __block NSError *timeoutError = nil;
    
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, timeout * NSEC_PER_SEC);
    dispatch_after(popTime, self.class.cde_timeoutQueue, ^{
        if (!coordinatorExecuted) {
            [self cancel];
            timeoutError = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeFileCoordinatorTimedOut userInfo:nil];
        }
    });
    
    NSError *fileCoordinatorError = nil;
    [self coordinateWritingItemAtURL:url options:options error:&fileCoordinatorError byAccessor:^(NSURL *newURL) {
        dispatch_sync(self.class.cde_timeoutQueue, ^{ coordinatorExecuted = YES; });
        if (timeoutError) return;
        writer(newURL);
    }];
    
    if (timeoutError) *outError = timeoutError;
    if (fileCoordinatorError) *outError = fileCoordinatorError;
}

#endif

@end

