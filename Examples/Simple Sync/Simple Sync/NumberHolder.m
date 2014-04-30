//
//  NumberHolder.m
//  Magical Record
//
//  Created by Drew McCormack on 18/04/14.
//  Copyright (c) 2014 Drew McCormack. All rights reserved.
//

#import "NumberHolder.h"


@implementation NumberHolder

@dynamic uniqueIdentifier;
@dynamic number;

+ (instancetype)numberHolderInManagedObjectContext:(NSManagedObjectContext *)context
{
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"NumberHolder"];
    NumberHolder *holder = [[context executeFetchRequest:fetch error:NULL] lastObject];
    if (!holder) {
        holder = [NSEntityDescription insertNewObjectForEntityForName:@"NumberHolder" inManagedObjectContext:context];
    }
    return holder;
}

@end
