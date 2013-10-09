//
//  IDMTag.m
//  Idiomatic
//
//  Created by Drew McCormack on 20/09/13.
//  Copyright (c) 2013 The Mental Faculty B.V. All rights reserved.
//

#import "IDMTag.h"


@implementation IDMTag

@dynamic text;
@dynamic notes;

+ (instancetype)tagWithText:(NSString *)text inManagedObjectContext:(NSManagedObjectContext *)context
{
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"IDMTag"];
    fetch.predicate = [NSPredicate predicateWithFormat:@"text = %@", text];
    NSArray *tags = [context executeFetchRequest:fetch error:NULL];
    
    IDMTag *tag = tags.lastObject;
    if (!tag) {
        tag = [NSEntityDescription insertNewObjectForEntityForName:@"IDMTag" inManagedObjectContext:context];
        tag.text = text;
    }
    
    return tag;
}

+ (NSArray *)tagsInManagedObjectContext:(NSManagedObjectContext *)context
{
    NSFetchRequest * fetchRequest  = [[NSFetchRequest alloc] initWithEntityName:@"IDMTag"];
    fetchRequest.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"text" ascending:YES]];
    NSArray *tags = [context executeFetchRequest:fetchRequest error:nil];
    return tags;
}

- (NSString *)uniqueIdentifier
{
    return self.text;
}

@end
