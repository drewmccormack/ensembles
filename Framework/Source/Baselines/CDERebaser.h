//
//  CDEBaselinePropagator.h
//  Ensembles
//
//  Created by Drew McCormack on 05/01/14.
//  Copyright (c) 2014 Drew McCormack. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CDEDefines.h"

@class CDEEventStore;
@class CDEPersistentStoreEnsemble;

@interface CDERebaser : NSObject

@property (nonatomic, readonly) CDEEventStore *eventStore;
@property (nonatomic, weak, readwrite) CDEPersistentStoreEnsemble *ensemble;

- (instancetype)initWithEventStore:(CDEEventStore *)eventStore;

- (CGFloat)estimatedEventStoreCompactionFollowingRebase;
- (BOOL)shouldRebase;

- (void)rebaseWithCompletion:(CDECompletionBlock)completion;

@end
