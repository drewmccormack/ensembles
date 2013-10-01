//
//  CDEAsynchronousTaskQueue.h
//  Ensembles
//
//  Created by Drew McCormack on 4/13/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CDEDefines.h"

typedef void (^CDEAsynchronousTaskCallbackBlock)(NSError *error, BOOL stop);
typedef void (^CDEAsynchronousTaskBlock)(CDEAsynchronousTaskCallbackBlock next);

typedef enum {
    CDETaskQueueTerminationPolicyStopOnError,
    CDETaskQueueTerminationPolicyStopOnSuccess,
    CDETaskQueueTerminationPolicyCompleteAll
} CDETaskQueueTerminationPolicy;

@interface CDEAsynchronousTaskQueue : NSOperation

- (instancetype)initWithTasks:(NSArray *)tasks terminationPolicy:(CDETaskQueueTerminationPolicy)policy completion:(CDECompletionBlock)completion; // Designated
- (instancetype)initWithTasks:(NSArray *)tasks completion:(CDECompletionBlock)completion;
- (instancetype)initWithTask:(CDEAsynchronousTaskBlock)task repeatCount:(NSUInteger)count terminationPolicy:(CDETaskQueueTerminationPolicy)policy completion:(CDECompletionBlock)completion;

@end
