//
//  CDEAsynchronousOperation.h
//  Ensembles iOS
//
//  Created by Drew McCormack on 01/03/14.
//  Copyright (c) 2014 The Mental Faculty B.V. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface CDEAsynchronousOperation : NSOperation

- (void)beginAsynchronousTask; // Override to initiate task
- (void)endAsynchronousTask; // Call on completion of task

@end
