//
//  IDMNote.m
//  Idiomatic
//
//  Created by Drew McCormack on 20/09/13.
//  Copyright (c) 2013 The Mental Faculty B.V. All rights reserved.
//

#import "IDMNote.h"
#import "IDMTag.h"


@implementation IDMNote

@dynamic text;
@dynamic creationDate;
@dynamic tags;
@dynamic uniqueIdentifier;
@dynamic imageFile;

- (void)awakeFromInsert
{
    [super awakeFromInsert];
    if (!self.uniqueIdentifier) {
        self.uniqueIdentifier = [[NSProcessInfo processInfo] globallyUniqueString];
        self.creationDate = [[NSDate alloc] init];
    }
}

+ (NSArray *)notesInManagedObjectContext:(NSManagedObjectContext *)context
{
    return [self notesWithTag:nil inManagedObjectContext:context];
}

+ (NSArray *)notesWithTag:(IDMTag*)tag inManagedObjectContext:(NSManagedObjectContext *)context
{
    NSFetchRequest * fetchRequest  = [[NSFetchRequest alloc] initWithEntityName:@"IDMNote"];
    fetchRequest.predicate = tag ? [NSPredicate predicateWithFormat:@"%@ IN tags", tag] : nil;
    fetchRequest.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];
    NSArray *notes = [context executeFetchRequest:fetchRequest error:nil];
    return notes;
}


@end
