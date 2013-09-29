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
    self.globalIdentifier = [[NSProcessInfo processInfo] globallyUniqueString];
}

+ (NSArray *)fetchGlobalIdentifiersForObjectIDs:(NSArray *)objectIDs inManagedObjectContext:(NSManagedObjectContext *)context
{
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

+ (NSArray *)fetchGlobalIdentifiersForIdentifierStrings:(NSArray *)idStrings inManagedObjectContext:(NSManagedObjectContext *)context
{
    if (!idStrings) return nil;
    
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"CDEGlobalIdentifier"];
    fetch.predicate = [NSPredicate predicateWithFormat:@"globalIdentifier IN %@", idStrings];
    
    NSError *error;
    NSArray *globalIds = [context executeFetchRequest:fetch error:&error];
    if (!globalIds) {
        CDELog(CDELoggingLevelError, @"Fetch for global ids failed: %@", error);
        return nil;
    }
    
    // Sort in same order as input strings
    NSDictionary *globalIdsByIdString = [NSDictionary dictionaryWithObjects:globalIds forKeys:[globalIds valueForKeyPath:@"globalIdentifier"]];
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:idStrings.count];
    for (NSManagedObjectID *idString in idStrings) {
        CDEGlobalIdentifier *globalId = globalIdsByIdString[idString];
        [result addObject:globalId ? : [NSNull null]];
    }
    
    return result;
}

@end
