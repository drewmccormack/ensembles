//
//  CDEIntegratorTestCase.h
//  Ensembles
//
//  Created by Drew McCormack on 20/08/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import "CDEEventStoreTestCase.h"
#import "CDEStoreModificationEvent.h"
#import "CDEObjectChange.h"
#import "CDEGlobalIdentifier.h"
#import "CDEEventRevision.h"
#import "CDEPropertyChangeValue.h"
#import "CDEEventIntegrator.h"

@interface CDEIntegratorTestCase : CDEEventStoreTestCase {
}

@property (strong) CDEEventIntegrator *integrator;

- (void)waitForAsyncOpToFinish;
- (void)stopAsyncOp;

- (void)mergeEvents;
    
- (void)addEventsFromJSONFile:(NSString *)path;

@end
