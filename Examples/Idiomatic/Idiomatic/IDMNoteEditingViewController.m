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

@interface IDMNoteEditingViewController () <UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIActionSheetDelegate>

@end

@implementation IDMNoteEditingViewController {
    NSData *newImageData;
    UITapGestureRecognizer *photoTapRecognizer;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    photoTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handlePhotoTap:)];
    photoTapRecognizer.numberOfTapsRequired = 1;
    self.imageView.userInteractionEnabled = YES;
    [self.imageView addGestureRecognizer:photoTapRecognizer];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    if (!self.presentedViewController) {
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
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    if (!self.imageView.image) [self.textView becomeFirstResponder];
}

#pragma mark Changing Photo

- (IBAction)changePhoto:(id)sender
{
    BOOL hasExistingImage = (self.note.imageFile && !newImageData) || (newImageData && (id)newImageData != [NSNull null]);
    if (hasExistingImage) {
        UIActionSheet *actionSheet = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:@"Cancel" destructiveButtonTitle:nil otherButtonTitles:@"Remove Photo", @"Replace Photo", nil];
        [actionSheet showInView:self.view];
    }
    else {
        [self chooseImage];
    }
}

- (void)actionSheet:(UIActionSheet *)actionSheet didDismissWithButtonIndex:(NSInteger)buttonIndex
{
    if (actionSheet.firstOtherButtonIndex == buttonIndex) {
        self.imageView.image = nil;
        newImageData = (id)[NSNull null];
    }
    else if (actionSheet.firstOtherButtonIndex + 1 == buttonIndex) {
        [self chooseImage];
    }
}

- (void)chooseImage
{
    UIImagePickerController *imagePicker = [[UIImagePickerController alloc] init];
    imagePicker.delegate = self;
    [self presentViewController:imagePicker animated:YES completion:NULL];
}

- (IBAction)handlePhotoTap:(id)sender
{
    [self.textView resignFirstResponder];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info
{
    UIImage *image = [info valueForKey:UIImagePickerControllerOriginalImage];
    newImageData = UIImageJPEGRepresentation(image, 1.0);
    self.imageView.image = image;
    if (image) [self.textView resignFirstResponder];
    [picker dismissViewControllerAnimated:YES completion:nil];
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

#pragma mark Tags

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

#pragma mark Segues

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
