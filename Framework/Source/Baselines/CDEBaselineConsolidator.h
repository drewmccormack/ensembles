//
//  CDEBaselineConsolidator.h
//  Ensembles Mac
//
//  Created by Drew McCormack on 27/11/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CDEDefines.h"

@class CDEEventStore;

@interface CDEBaselineConsolidator : NSObject

@property (nonatomic, readonly) CDEEventStore *eventStore;

- (id)initWithEventStore:(CDEEventStore *)eventStore;

- (BOOL)baselineNeedsConsolidation;
- (void)consolidateBaselineWithCompletion:(CDECompletionBlock)completion;

@end
