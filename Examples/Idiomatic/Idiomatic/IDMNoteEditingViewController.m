//
//  IDMNoteEditingViewController.m
//  Idiomatic
//
//  Created by Drew McCormack on 20/09/13.
//  Copyright (c) 2013 The Mental Faculty B.V. All rights reserved.
//

#import "IDMNoteEditingViewController.h"
#import "IDMNote.h"
#import "IDMTag.h"

@interface IDMNoteEditingViewController ()

@end

@implementation IDMNoteEditingViewController

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    self.textView.attributedText = self.note.attributedText;
    
    if (self.note) {
        NSArray *sortDescs = @[[NSSortDescriptor sortDescriptorWithKey:@"text" ascending:YES]];
        NSArray *tags = [self.note.tags sortedArrayUsingDescriptors:sortDescs];
        self.tagsTextField.text = [[tags valueForKeyPath:@"text"] componentsJoinedByString:@" "];
    }
    else {
        self.tagsTextField.text = self.selectedTag.text;
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self.textView becomeFirstResponder];
}

- (void)updateTags
{
    NSCharacterSet *separators = [NSCharacterSet characterSetWithCharactersInString:@" ,"];
    NSArray *tagStrings = [self.tagsTextField.text componentsSeparatedByCharactersInSet:separators];
    NSMutableSet *tags = [NSMutableSet setWithCapacity:tagStrings.count];
    for (NSString *tagText in tagStrings) {
        if (tagText.length == 0) continue;
        IDMTag *tag = [IDMTag tagWithText:tagText inManagedObjectContext:self.managedObjectContext];
        [tags addObject:tag];
    }
    self.note.tags = tags;
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if (sender == self.saveBarButtonItem) {
        if (!self.note) {
            self.note = [NSEntityDescription insertNewObjectForEntityForName:@"IDMNote" inManagedObjectContext:self.managedObjectContext];
        }
        
        self.note.attributedText = self.textView.attributedText;
        [self updateTags];
        
        [self.managedObjectContext save:NULL];
    }
}

@end
