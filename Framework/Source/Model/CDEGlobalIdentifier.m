//
//  CDEGlobalIdentifier.m
//  Test App iOS
//
//  Created by Drew McCormack on 4/20/13.
//  Copyright (c) 2013 The Mental Faculty B.V. All rights reserved.
//

#import "CDEGlobalIdentifier.h"
#import "CDEDefines.h"


@implementation CDEGlobalIdentifier

@dynamic globalIdentifier;
@dynamic storeURI;
@dynamic nameOfEntity;

- (void)awakeFromInsert
{
    [super awakeFromInsert];
    if (!self.globalIdentifier) self.globalIdentifier = [[NSProcessInfo processInfo] globallyUniqueString];
}

+ (NSArray *)fetchGlobalIdentifiersForObjectIDs:(NSArray *)objectIDs inManagedObjectContext:(NSManagedObjectContext *)context
{
    if (objectIDs.count == 0) return @[];
    
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"CDEGlobalIdentifier"];
    NSArray *uriStrings = [objectIDs valueForKeyPath:@"URIRepresentation.absoluteString"];
    fetch.predicate = [NSPredicate predicateWithFormat:@"storeURI IN %@", uriStrings];
    
    NSError *error;
    NSArray *globalIds = [context executeFetchRequest:fetch error:&error];
    if (!globalIds) {
        CDELog(CDELoggingLevelError, @"Fetch for global ids failed: %@", error);
        return nil;
    }
    
    // Sort in same order
    NSDictionary *globalIdsByURI = [NSDictionary dictionaryWithObjects:globalIds forKeys:[globalIds valueForKeyPath:@"storeURI"]];
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:objectIDs.count];
    for (NSManagedObjectID *objectID in objectIDs) {
        CDEGlobalIdentifier *globalId = globalIdsByURI[objectID.URIRepresentation.absoluteString];
        [result addObject:globalId ? : [NSNull null]];
    }
    
    return result;
}

+ (NSArray *)fetchGlobalIdentifiersForIdentifierStrings:(NSArray *)idStrings withEntityNames:(NSArray *)entityNames inManagedObjectContext:(NSManagedObjectContext *)context
{
    NSParameterAssert(idStrings.count == entityNames.count);
    
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"CDEGlobalIdentifier"];
    fetch.predicate = [NSPredicate predicateWithFormat:@"globalIdentifier IN %@", idStrings];
    
    NSError *error;
    NSArray *globalIds = [context executeFetchRequest:fetch error:&error];
    if (!globalIds) {
        CDELog(CDELoggingLevelError, @"Fetch for global ids failed: %@", error);
        return nil;
    }
    
    // Group results by id string, and index on entity
    NSMutableDictionary *globalIdsByIdString = [NSMutableDictionary dictionaryWithCapacity:globalIds.count];
    for (CDEGlobalIdentifier *globalId in globalIds) {
        NSMutableDictionary *globalIdsByEntity = globalIdsByIdString[globalId.globalIdentifier];
        if (!globalIdsByEntity) globalIdsByEntity = [[NSMutableDictionary alloc] init];
        [globalIdsByEntity setObject:globalId forKey:globalId.nameOfEntity];
        [globalIdsByIdString setObject:globalIdsByEntity forKey:globalId.globalIdentifier];
    }
    
    // Create result in same order as input
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:idStrings.count];
    NSUInteger i = 0;
    for (NSManagedObjectID *idString in idStrings) {
        NSDictionary *globalIdsByEntity = globalIdsByIdString[idString];
        NSString *entityName = entityNames[i++];
        CDEGlobalIdentifier *entityGlobalId = globalIdsByEntity[entityName];
        [result addObject:entityGlobalId ? : [NSNull null]];
    }
    
    return result;
}

+ (NSArray *)fetchUnreferencedGlobalIdentifiersInManagedObjectContext:(NSManagedObjectContext *)context
{
    NSError *error = nil;
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"CDEGlobalIdentifier"];
    fetch.predicate = [NSPredicate predicateWithFormat:@"objectChanges.@count == 0"];
    NSArray *globalIds = [context executeFetchRequest:fetch error:&error];
    if (!globalIds) {
        CDELog(CDELoggingLevelError, @"Fetch for global ids failed: %@", error);
        return nil;
    }
    
    return globalIds;
}

@end
