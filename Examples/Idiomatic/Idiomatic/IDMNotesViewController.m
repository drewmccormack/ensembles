//
//  IDMNotesViewController.m
//  Idiomatic
//
//  Created by Drew McCormack on 20/09/13.
//  Copyright (c) 2013 The Mental Faculty B.V. All rights reserved.
//

#import "IDMNotesViewController.h"
#import "IDMNoteEditingViewController.h"
#import "IDMNote.h"
#import "IDMTag.h"

@interface IDMNotesViewController () <NSFetchedResultsControllerDelegate>

@end

@implementation IDMNotesViewController {
    NSFetchedResultsController *notesController;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"IDMNote"];
    request.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];
    request.predicate = self.tag ? [NSPredicate predicateWithFormat:@"%@ IN tags", self.tag] : nil;
    notesController = [[NSFetchedResultsController alloc] initWithFetchRequest:request managedObjectContext:self.managedObjectContext sectionNameKeyPath:nil cacheName:nil];
    notesController.delegate = self;
    [notesController performFetch:NULL];
    [self.tableView reloadData];

    self.title = self.tag.text ? : @"ALL NOTES";
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    notesController.delegate = nil;
    notesController = nil;
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    UINavigationController *navController = (id)segue.destinationViewController;
    IDMNoteEditingViewController *editingController = (id)navController.topViewController;
    editingController.managedObjectContext = self.managedObjectContext;
    editingController.note = nil;
    editingController.selectedTag = self.tag;
    
    if ([segue.identifier isEqualToString:@"ToEditNote"]) {
        NSIndexPath *path = [self.tableView indexPathForCell:sender];
        editingController.note = notesController.fetchedObjects[path.row];
    }
}

#pragma mark - Table View Data Source and Delegate

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return notesController.fetchedObjects.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"NoteCell"];
    IDMNote *note = notesController.fetchedObjects[indexPath.row];
    cell.textLabel.text = note.text;
    return cell;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        IDMNote *note = notesController.fetchedObjects[indexPath.row];
        [self.managedObjectContext deleteObject:note];
        [self.managedObjectContext save:NULL];
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
    
    switch(type) {
        case NSFetchedResultsChangeInsert:
            [tableView insertRowsAtIndexPaths:@[newIndexPath] withRowAnimation:UITableViewRowAnimationTop];
            break;
            
        case NSFetchedResultsChangeDelete:
            [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationTop];
            break;
            
        case NSFetchedResultsChangeUpdate:
            {
                UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
                IDMNote *note = notesController.fetchedObjects[indexPath.row];
                cell.textLabel.text = note.text;
            }
            break;
            
        case NSFetchedResultsChangeMove:
            [tableView deleteRowsAtIndexPaths:@[ indexPath ] withRowAnimation:UITableViewRowAnimationTop];
            [tableView insertRowsAtIndexPaths:@[ newIndexPath ] withRowAnimation:UITableViewRowAnimationTop];
            break;
    }
}


- (void)controllerDidChangeContent:(NSFetchedResultsController *)controller
{
    [self.tableView endUpdates];
}

#pragma mark - Segues

- (IBAction)cancelEditing:(UIStoryboardSegue *)sender
{
}

- (IBAction)saveEditing:(UIStoryboardSegue *)sender
{
}

@end
