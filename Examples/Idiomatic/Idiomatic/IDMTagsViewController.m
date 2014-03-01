//
//  IDMTagsViewController.m
//  Idiomatic
//
//  Created by Drew McCormack on 20/09/13.
//  Copyright (c) 2013 The Mental Faculty B.V. All rights reserved.
//

#import "IDMTagsViewController.h"
#import "IDMNotesViewController.h"
#import "IDMAppDelegate.h"
#import "IDMTag.h"

@interface IDMTagsViewController () <NSFetchedResultsControllerDelegate, UIActionSheetDelegate>

@end

@implementation IDMTagsViewController {
    NSFetchedResultsController *tagsController;
    __weak IBOutlet UIBarButtonItem *syncButtonItem;
    __weak IBOutlet UIBarButtonItem *enableSyncButtonItem;
    UIActionSheet *syncServiceActionSheet;
    id syncDidBeginNotif, syncDidEndNotif;
    BOOL merging;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    if (tagsController) return;
    
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"IDMTag"];
    request.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"text" ascending:YES]];
    tagsController = [[NSFetchedResultsController alloc] initWithFetchRequest:request managedObjectContext:self.managedObjectContext sectionNameKeyPath:nil cacheName:nil];
    tagsController.delegate = self;
    
    [tagsController performFetch:NULL];
    
    __weak typeof(self) weakSelf = self;
    syncDidBeginNotif = [[NSNotificationCenter defaultCenter] addObserverForName:IDMSyncActivityDidBeginNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        __strong typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf->merging = YES;
        [strongSelf updateButtons];
    }];
    syncDidEndNotif = [[NSNotificationCenter defaultCenter] addObserverForName:IDMSyncActivityDidEndNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        __strong typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf->merging = NO;
        [strongSelf updateButtons];
    }];
}

- (void)viewDidUnload
{
    [super viewDidUnload];
    [[NSNotificationCenter defaultCenter] removeObserver:syncDidBeginNotif];
    [[NSNotificationCenter defaultCenter] removeObserver:syncDidEndNotif];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self updateButtons];
}

#pragma mark - Views

- (void)updateButtons
{
    IDMAppDelegate *appDelegate = [[UIApplication sharedApplication] delegate];
    syncButtonItem.enabled = appDelegate.canSynchronize && !merging;
    enableSyncButtonItem.title = appDelegate.canSynchronize ? @"Disable Sync" : @"Enable Sync";
    enableSyncButtonItem.enabled = !merging;
}

#pragma mark - Sync

- (IBAction)sync:(id)sender
{
    IDMAppDelegate *appDelegate = (id)[[UIApplication sharedApplication] delegate];
    [appDelegate synchronize];
}

- (IBAction)toggleSyncEnabled:(id)sender
{
    IDMAppDelegate *appDelegate = (id)[[UIApplication sharedApplication] delegate];
    if (appDelegate.canSynchronize) {
        enableSyncButtonItem.enabled = NO;
        syncButtonItem.enabled = NO;
        [appDelegate disconnectFromSyncServiceWithCompletion:^{
            [self updateButtons];
        }];
    }
    else {
        syncServiceActionSheet = [[UIActionSheet alloc] initWithTitle:@"What service would you like?" delegate:self cancelButtonTitle:@"None" destructiveButtonTitle:nil otherButtonTitles:@"iCloud", @"Dropbox", @"IdioSync", nil];
        [syncServiceActionSheet showFromToolbar:self.navigationController.toolbar];
        [self updateButtons];
    }
}

- (void)actionSheet:(UIActionSheet *)actionSheet didDismissWithButtonIndex:(NSInteger)buttonIndex
{
    if (syncServiceActionSheet == actionSheet) {
        IDMAppDelegate *appDelegate = (id)[[UIApplication sharedApplication] delegate];
        NSString *service;
        if (buttonIndex == actionSheet.firstOtherButtonIndex)
            service = IDMICloudService;
        else if (buttonIndex == actionSheet.firstOtherButtonIndex+1)
            service = IDMDropboxService;
        else if (buttonIndex == actionSheet.firstOtherButtonIndex+2)
            service = IDMNodeS3Service;
        [appDelegate connectToSyncService:service];
        
        [self updateButtons];
        syncServiceActionSheet = nil;
    }
}

- (IDMTag *)tagAtRow:(NSUInteger)row
{
    if (row == 0) return nil;
    return tagsController.fetchedObjects[row-1];
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if ([segue.identifier isEqualToString:@"ToNotes"]) {
        IDMNotesViewController *notesController = (id)segue.destinationViewController;
        notesController.managedObjectContext = self.managedObjectContext;
        NSUInteger row = [[self.tableView indexPathForCell:sender] row];
        notesController.tag = [self tagAtRow:row];
    }
}

#pragma mark - Table View Data Source and Delegate

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return tagsController.fetchedObjects.count+1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"TagCell"];
    IDMTag *tag = [self tagAtRow:indexPath.row];
    cell.textLabel.text = tag.text ? : @"All Notes";
    return cell;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.row == 0) return UITableViewCellEditingStyleNone;
    return UITableViewCellEditingStyleDelete;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        IDMTag *tag = [self tagAtRow:indexPath.row];
        [self.managedObjectContext performBlockAndWait:^{
            [self.managedObjectContext deleteObject:tag];
            [self.managedObjectContext save:NULL];
        }];
    }
}

#pragma mark - Fetched Results Controller Delegate

- (void)controllerWillChangeContent:(NSFetchedResultsController *)controller
{
    [self.tableView beginUpdates];
}

- (void)controller:(NSFetchedResultsController *)controller didChangeObject:(id)anObject
       atIndexPath:(NSIndexPath *)indexPath forChangeType:(NSFetchedResultsChangeType)type
      newIndexPath:(NSIndexPath *)newIndexPath
{
    UITableView *tableView = self.tableView;
    
    NSIndexPath *adjustedPathInsertion = [NSIndexPath indexPathForRow:newIndexPath.row+1 inSection:0];
    NSIndexPath *adjustedPathDeletion = [NSIndexPath indexPathForRow:indexPath.row+1 inSection:0];
    switch(type) {
        case NSFetchedResultsChangeInsert:
            [tableView insertRowsAtIndexPaths:@[adjustedPathInsertion] withRowAnimation:UITableViewRowAnimationTop];
            break;
            
        case NSFetchedResultsChangeDelete:
            [tableView deleteRowsAtIndexPaths:@[adjustedPathDeletion] withRowAnimation:UITableViewRowAnimationTop];
            break;
    }
}


- (void)controllerDidChangeContent:(NSFetchedResultsController *)controller
{
    [self.tableView endUpdates];
}

@end
