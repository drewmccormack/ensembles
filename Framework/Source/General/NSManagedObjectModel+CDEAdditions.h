//
//  NSManagedObjectModel+CDEAdditions.h
//  Ensembles
//
//  Created by Drew McCormack on 08/11/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import <CoreData/CoreData.h>

@interface NSManagedObjectModel (CDEAdditions)

- (NSString *)cde_modelHash;

- (NSString *)cde_entityHashesPropertyList; // XML Dictionary
+ (NSDictionary *)cde_entityHashesByNameFromPropertyList:(NSString *)propertyList; 

@end
