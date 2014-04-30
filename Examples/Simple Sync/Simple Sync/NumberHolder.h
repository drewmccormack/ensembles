//
//  NumberHolder.h
//  Magical Record
//
//  Created by Drew McCormack on 18/04/14.
//  Copyright (c) 2014 Drew McCormack. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>


@interface NumberHolder : NSManagedObject

@property (nonatomic, retain) NSString *uniqueIdentifier;
@property (nonatomic, retain) NSNumber *number;

+ (instancetype)numberHolderInManagedObjectContext:(NSManagedObjectContext *)context;

@end
