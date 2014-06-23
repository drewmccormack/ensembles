//
//  CDEBaselineConsolidator.h
//  Ensembles
//
//  Created by Drew McCormack on 27/11/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CDEDefines.h"

@class CDEEventStore;
@class CDEPersistentStoreEnsemble;

@interface CDEBaselineConsolidator : NSObject

@property (nonatomic, readonly) CDEEventStore *eventStore;
@property (nonatomic, weak, readwrite) CDEPersistentStoreEnsemble *ensemble;

- (instancetype)initWithEventStore:(CDEEventStore *)eventStore;

- (BOOL)baselineNeedsConsolidation;
- (void)consolidateBaselineWithCompletion:(CDECompletionBlock)completion;

@end
