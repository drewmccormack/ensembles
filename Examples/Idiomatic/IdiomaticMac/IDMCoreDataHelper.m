//
//  IDMCoreDataHelper.m
//  Idiomatic
//
//  Created by Ernesto on 10/5/13.
//  Copyright (c) 2013 The Mental Faculty B.V. All rights reserved.
//

#import "IDMCoreDataHelper.h"
#import "IDMTag.h"
#import "IDMNote.h"

@interface IDMCoreDataHelper ()
@property (nonatomic,strong) NSManagedObjectContext *managedObjectContext;
@end
@implementation IDMCoreDataHelper

-(id)initWithMangedObjectContext:(NSManagedObjectContext*)moc;
{
    self = [super init];
    if( self )
    {
        _managedObjectContext = moc;
    }
    return self;
}

-(NSArray*)allNotes
{
    return [self notesWithTag:nil];
}

-(NSArray*)allTags
{
    
    NSFetchRequest * fetchRequest  = [[NSFetchRequest alloc] initWithEntityName:@"IDMTag"];
    fetchRequest.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"text" ascending:YES]];
    NSArray *tags = [self.managedObjectContext executeFetchRequest:fetchRequest error:nil];
    return tags;
}

-(NSArray*)notesWithTag:(IDMTag*)tag
{
    NSArray *notes;
    
    NSFetchRequest * fetchRequest  = [[NSFetchRequest alloc] initWithEntityName:@"IDMNote"];
    fetchRequest.predicate = tag ? [NSPredicate predicateWithFormat:@"%@ IN tags", tag] : nil;
    fetchRequest.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];
    notes = [self.managedObjectContext executeFetchRequest:fetchRequest error:nil];
    return notes;
}

@end
