//
//  CDEGlobalIdentifier.h
//  Test App iOS
//
//  Created by Drew McCormack on 4/20/13.
//  Copyright (c) 2013 The Mental Faculty B.V. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>


@interface CDEGlobalIdentifier : NSManagedObject

@property (nonatomic, retain) NSString *globalIdentifier;
@property (nonatomic, retain) NSString *storeURI;
@property (nonatomic, retain) NSString *nameOfEntity;

+ (NSArray *)fetchGlobalIdentifiersForObjectIDs:(NSArray *)uris inManagedObjectContext:(NSManagedObjectContext *)context;
+ (NSArray *)fetchGlobalIdentifiersForIdentifierStrings:(NSArray *)strings withEntityNames:(NSArray *)entityNames inManagedObjectContext:(NSManagedObjectContext *)context;

+ (NSArray *)fetchUnreferencedGlobalIdentifiersInManagedObjectContext:(NSManagedObjectContext *)context;

@end
