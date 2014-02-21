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
#import "IDMMediaFile.h"

@interface IDMNoteEditingViewController () <UIImagePickerControllerDelegate, UINavigationControllerDelegate>

@end

@implementation IDMNoteEditingViewController {
    NSData *newImageData;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    
    self.textView.text = self.note.text;
    
    NSData *imageData = self.note.imageFile.data;
    self.imageView.image = imageData ? [UIImage imageWithData:imageData] : nil;
    newImageData = nil;

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

- (IBAction)changePhoto:(id)sender
{
    UIImagePickerController *imagePicker = [[UIImagePickerController alloc] init];
    imagePicker.delegate = self;
    [self presentViewController:imagePicker animated:YES completion:NULL];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info
{
    UIImage *image = [info valueForKey:UIImagePickerControllerOriginalImage];
    newImageData = UIImageJPEGRepresentation(image, 1.0);
    self.imageView.image = image;
    [picker dismissViewControllerAnimated:YES completion:nil];
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

- (void)updateImageData
{
    if (!newImageData) return;
    if (self.note.imageFile) [self.managedObjectContext deleteObject:self.note.imageFile];
    if ((id)newImageData != [NSNull null]) {
        self.note.imageFile = [NSEntityDescription insertNewObjectForEntityForName:@"IDMMediaFile" inManagedObjectContext:self.managedObjectContext];
        self.note.imageFile.data = newImageData;
    }
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if (sender == self.saveBarButtonItem) {
        if (!self.note) {
            self.note = [NSEntityDescription insertNewObjectForEntityForName:@"IDMNote" inManagedObjectContext:self.managedObjectContext];
        }
        
        self.note.text = self.textView.text;
        [self updateTags];
        [self updateImageData];
        
        [self.managedObjectContext save:NULL];
    }
}

@end
