//
//  NSManagedObjectModel+CDEAdditions.h
//  Ensembles Mac
//
//  Created by Drew McCormack on 08/11/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import <CoreData/CoreData.h>

@interface NSManagedObjectModel (CDEAdditions)

- (NSString *)cde_modelHash;

@end
