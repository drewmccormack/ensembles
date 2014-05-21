//
//  CDEIntegratorTestCase.m
//  Ensembles
//
//  Created by Drew McCormack on 20/08/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import "CDEIntegratorTestCase.h"

@implementation CDEIntegratorTestCase 

@synthesize integrator = integrator;

+ (void)setUp
{
    [super setUp];
    [self setUseDiskStore:YES];
}

- (void)setUp
{
    [super setUp];
    
    NSManagedObjectModel *model = self.testManagedObjectContext.persistentStoreCoordinator.managedObjectModel;
    integrator = [[CDEEventIntegrator alloc] initWithStoreURL:self.testStoreURL managedObjectModel:model eventStore:(id)self.eventStore];
    __weak NSManagedObjectContext *weakTestMoc = self.testManagedObjectContext;
    integrator.didSaveBlock = ^(NSManagedObjectContext *context, NSDictionary *info) {
        dispatch_sync(dispatch_get_main_queue(), ^{
            NSNotification *notif = [[NSNotification alloc] initWithName:NSManagedObjectContextDidSaveNotification object:context userInfo:info];
            [weakTestMoc mergeChangesFromContextDidSaveNotification:notif];
        });
    };
}

- (void)waitForAsyncOpToFinish
{
    CFRunLoopRun();
}

- (void)stopAsyncOp
{
    CFRunLoopStop(CFRunLoopGetCurrent());
}

- (void)mergeEvents
{
    [integrator mergeEventsWithCompletion:^(NSError *error) {
        [self stopAsyncOp];
    }];
    [self waitForAsyncOpToFinish];
    [self.eventStore updateRevisionsForMerge];
}

- (NSArray *)globalIdsFromIdStrings:(NSArray *)idStrings forEntity:(NSString *)entityName withExisting:(NSMutableDictionary *)existing
{
    NSMutableArray *globalIds = [NSMutableArray array];
    for (NSString *idString in idStrings) {
        CDEGlobalIdentifier *globalId = existing[idString];
        if (!globalId) {
            globalId = [self addGlobalIdentifier:idString forEntity:entityName];
            existing[idString] = globalId;
        }
        [globalIds addObject:globalId];
    }
    return globalIds;
}

- (void)addEventsFromJSONFile:(NSString *)path {
    NSData *data = [NSData dataWithContentsOfFile:path];
    NSArray *eventDicts = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    NSAssert(eventDicts != nil, @"Could not parse JSON");
    
    NSManagedObjectContext *moc = self.eventStore.managedObjectContext;
    NSManagedObjectModel *model = self.testManagedObjectContext.persistentStoreCoordinator.managedObjectModel;
    [moc performBlockAndWait:^{
        NSMutableDictionary *globalIds = [NSMutableDictionary dictionary];
        for (NSDictionary *eventDict in eventDicts) {
            CDEStoreModificationEvent *modEvent = [self addModEventForStore:eventDict[@"store"] revision:[eventDict[@"revision"] integerValue] globalCount:[eventDict[@"globalCount"] integerValue] timestamp:[eventDict[@"timestamp"] doubleValue]];
            
            NSMutableSet *otherRevs = [NSMutableSet set];
            for (NSDictionary *revDict in eventDict[@"otherstores"]) {
                CDEEventRevision *otherRev = [self addEventRevisionForStore:revDict[@"store"] revision:[revDict[@"revision"] integerValue]];
                [otherRevs addObject:otherRev];
            }
            
            modEvent.eventRevisionsOfOtherStores =  otherRevs;
            
            for (NSDictionary *changeDict in eventDict[@"changes"]) {
                CDEObjectChangeType type = -100;
                if ([changeDict[@"type"] isEqualToString:@"insert"])
                    type = CDEObjectChangeTypeInsert;
                else if ([changeDict[@"type"] isEqualToString:@"update"])
                    type = CDEObjectChangeTypeUpdate;
                else if ([changeDict[@"type"] isEqualToString:@"delete"])
                    type = CDEObjectChangeTypeDelete;
                
                NSString *entityName = changeDict[@"entity"];
                NSString *idString = changeDict[@"id"];
                NSArray *ids = [self globalIdsFromIdStrings:@[idString] forEntity:entityName withExisting:globalIds];
                CDEGlobalIdentifier *globalId = ids.lastObject;
                
                CDEObjectChange *change = [self addObjectChangeOfType:type withGlobalIdentifier:globalId toEvent:modEvent];
                
                NSEntityDescription *entity = model.entitiesByName[entityName];
                NSMutableArray *propertyChangeValues = [NSMutableArray array];
                [changeDict[@"properties"] enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
                    NSPropertyDescription *property = [entity propertiesByName][key];
                    if (obj == [NSNull null]) obj = nil;
                    
                    if ([property isKindOfClass:[NSRelationshipDescription class]]) {
                        if ([(id)property isToMany]) {
                            [propertyChangeValues addObject:[self toManyRelationshipChangeForName:key addedIdentifiers:obj[@"add"] removedIdentifiers:obj[@"remove"]]];
                        }
                        else {
                            [propertyChangeValues addObject:[self toOneRelationshipChangeForName:key relatedIdentifier:obj]];
                        }
                    }
                    else {
                        if (obj && [(id)property attributeType] == NSDateAttributeType) {
                            obj = [NSDate dateWithTimeIntervalSinceReferenceDate:[obj doubleValue]];
                        }
                        id attr = [self attributeChangeForName:key value:obj];
                        [propertyChangeValues addObject:attr];
                    }
                }];
                change.propertyChangeValues = propertyChangeValues;
            }
        }
        [moc save:NULL];
    }];
}

@end
