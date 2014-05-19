//
//  CDEDataFile.m
//  Ensembles iOS
//
//  Created by Drew McCormack on 17/02/14.
//  Copyright (c) 2014 The Mental Faculty B.V. All rights reserved.
//

#import "CDEDataFile.h"
#import "CDEDefines.h"
#import "CDEObjectChange.h"
#import "CDEStoreModificationEvent.h"

@implementation CDEDataFile

@dynamic filename;
@dynamic objectChange;

+ (NSSet *)allFilenamesInManagedObjectContext:(NSManagedObjectContext *)context
{
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"CDEDataFile"];
    fetch.predicate = [NSPredicate predicateWithFormat:@"objectChange != NIL"];
    
    NSError *error;
    NSArray *results = [context executeFetchRequest:fetch error:&error];
    if (!results) CDELog(CDELoggingLevelError, @"Could not fetch data files: %@", error);
    
    NSSet *filenames = [NSSet setWithArray:[results valueForKeyPath:@"filename"]];
    return filenames;
}

+ (NSSet *)filenamesInStoreModificationEvents:(NSArray *)events
{
    NSManagedObjectContext *context = [events.lastObject managedObjectContext];
    if (!context) return [NSSet set];
    
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"CDEDataFile"];
    fetch.predicate = [NSPredicate predicateWithFormat:@"objectChange.storeModificationEvent IN %@", events];
    
    NSError *error;
    NSArray *results = [context executeFetchRequest:fetch error:&error];
    if (!results) CDELog(CDELoggingLevelError, @"Could not fetch data files: %@", error);
    
    NSSet *filenames = [NSSet setWithArray:[results valueForKeyPath:@"filename"]];
    return filenames;
}

+ (NSSet *)unreferencedFilenamesInManagedObjectContext:(NSManagedObjectContext *)context
{
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"CDEDataFile"];
    fetch.predicate = [NSPredicate predicateWithFormat:@"objectChange = NIL"];
    
    NSError *error;
    NSArray *results = [context executeFetchRequest:fetch error:&error];
    if (!results) CDELog(CDELoggingLevelError, @"Could not fetch data files: %@", error);
    
    NSSet *filenames = [NSSet setWithArray:[results valueForKeyPath:@"filename"]];
    return filenames;
}

@end
