//
//  AppDelegate.m
//  IdiomaticMac
//
//  Created by Ernesto on 10/5/13.
//  Copyright (c) 2013 The Mental Faculty B.V. All rights reserved.
//

#import "AppDelegate.h"
#import <CoreData/CoreData.h>

#import "CoreDataEnsembles.h"
#import "CDEICloudFileSystem.h"
#import "IDMAddNoteViewController.h"
#import "IDMNote.h"
#import "IDMTag.h"
#import "IDMCoreDataHelper.h"

@interface TreeItem : NSObject
@property (nonatomic,strong) NSMutableArray *childs;
@property (nonatomic) BOOL header;
@property (nonatomic,strong) NSString *title;
@property (nonatomic,strong) id representedObject;
@end

@implementation TreeItem



@end

NSString * const IDMSyncActivityDidBeginNotification = @"IDMSyncActivityDidBegin";
NSString * const IDMSyncActivityDidEndNotification = @"IDMSyncActivityDidEnd";

@interface AppDelegate () <CDEPersistentStoreEnsembleDelegate, NSTableViewDataSource, NSTableViewDelegate , NSOutlineViewDelegate, NSOutlineViewDataSource, NSPopoverDelegate, IDMAddNoteDelegate>
{
    NSManagedObjectContext *managedObjectContext;
    CDEPersistentStoreEnsemble *ensemble;
    CDEICloudFileSystem *cloudFileSystem;
    NSUInteger activeMergeCount;
    TreeItem *allNotes;
    TreeItem *tags;
    IDMCoreDataHelper *cdHelper;
    NSMutableArray *notes;
}

@property (nonatomic,weak) IBOutlet NSOutlineView *collectionView;
@property (nonatomic,weak) IBOutlet NSTableView *tableView;
@property (nonatomic,weak) IBOutlet NSButton *addNoteButton;
@property (nonatomic,weak) IBOutlet NSButton *deleteNoteButton;
@property (nonatomic,strong) IDMAddNoteViewController *addNoteViewController;
@property (nonatomic,strong) NSPopover *popOver;

@end


@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Ensembles logging
    CDESetCurrentLoggingLevel(CDELoggingLevelVerbose);
    
    // Store directory and URL
    NSURL *directoryURL = [[NSFileManager defaultManager] URLForDirectory:NSApplicationSupportDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:NULL];
    directoryURL = [directoryURL URLByAppendingPathComponent:NSBundle.mainBundle.bundleIdentifier isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:directoryURL withIntermediateDirectories:YES attributes:nil error:NULL];
    NSURL *storeURL = [directoryURL URLByAppendingPathComponent:@"store.sqlite"];
    
    // Setup Core Data Stack
    NSError *error;
    NSURL *modelURL = [[NSBundle mainBundle] URLForResource:@"Model" withExtension:@"momd"];
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
    NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
    [coordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:nil error:&error];
    managedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    managedObjectContext.persistentStoreCoordinator = coordinator;
    managedObjectContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy;
    
    // Setup Ensemble
    cloudFileSystem = [[CDEICloudFileSystem alloc] initWithUbiquityContainerIdentifier:nil];
    ensemble = [[CDEPersistentStoreEnsemble alloc] initWithEnsembleIdentifier:@"MainStore" persistentStorePath:storeURL.path managedObjectModel:model cloudFileSystem:cloudFileSystem];
    ensemble.delegate = self;
    
    cdHelper = [[IDMCoreDataHelper alloc] initWithMangedObjectContext:managedObjectContext];
    
    [self setupTree];
}

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    [self synchronize];
}

#pragma mark - Sync Methods

- (void)decrementMergeCount
{
    activeMergeCount--;
    if (activeMergeCount == 0) {
        [[NSNotificationCenter defaultCenter] postNotificationName:IDMSyncActivityDidEndNotification object:nil];
        [self setupTree];
        [self reloadTable];
    }
}

- (void)incrementMergeCount
{
    activeMergeCount++;
    if (activeMergeCount == 1) {
        [[NSNotificationCenter defaultCenter] postNotificationName:IDMSyncActivityDidBeginNotification object:nil];
    }
}

- (void)synchronize
{
    [self incrementMergeCount];
    if (!ensemble.isLeeched) {
        [ensemble leechPersistentStoreWithCompletion:^(NSError *error) {
            [self decrementMergeCount];
            if (error) NSLog(@"Could not leech to ensemble: %@", error);
        }];
    }
    else {
        [ensemble mergeWithCompletion:^(NSError *error) {
            [self decrementMergeCount];
            if (error) NSLog(@"Error merging: %@", error);
        }];
    }
}


-(void)setupTree
{
    allNotes  = [[TreeItem alloc] init];
    allNotes.title = @"All Notes";
    allNotes.header = YES;
    
    tags = [[TreeItem alloc] init];
    tags.title = @"TAGS";
    tags.header = YES;
    
    NSArray *allTags = [cdHelper allTags];
    
    if( tags.childs == nil )
        tags.childs = [[NSMutableArray alloc] init];
    
    for( IDMTag *tag in allTags )
    {
        TreeItem *item = [TreeItem new];
        item.title = tag.text;
        item.representedObject = tag;
        item.header = NO;
        [tags.childs addObject:item];
    }
    
    [self.collectionView reloadData];
    [self.collectionView expandItem:nil expandChildren:YES];
}

-(void)reloadTable
{
    IDMTag *tag;
    NSInteger selectedRow = [self.collectionView selectedRow];
    if( selectedRow > 0)    // First row is "All Tags"
    {
        TreeItem * item = [self.collectionView itemAtRow:selectedRow];
        tag = item.representedObject;
    }
    
    notes = [[NSMutableArray alloc] initWithArray:[cdHelper notesWithTag:tag ]];
    
    [self.tableView reloadData];
    [self.deleteNoteButton setEnabled:NO];
}

#pragma mark - Persistent Store Ensemble Delegate

- (void)persistentStoreEnsemble:(CDEPersistentStoreEnsemble *)ensemble didSaveMergeChangesWithNotification:(NSNotification *)notification
{
    [managedObjectContext performBlock:^{
        [managedObjectContext mergeChangesFromContextDidSaveNotification:notification];
    }];
}

- (NSArray *)persistentStoreEnsemble:(CDEPersistentStoreEnsemble *)ensemble globalIdentifiersForManagedObjects:(NSArray *)objects
{
    return [objects valueForKeyPath:@"uniqueIdentifier"];
}


-(void)showAddNoteViewWithText:(NSString*)text tags:(NSArray*)noteTags
{
    if( self.popOver )
    {
        [self.popOver performClose:self];
        self.popOver = nil;
        self.addNoteViewController = nil;
    }
    self.popOver = [[NSPopover alloc] init];
    
    [self.popOver setBehavior: NSPopoverBehaviorTransient];
    [self.popOver setDelegate: self];
    
    
    self.addNoteViewController = [[IDMAddNoteViewController alloc] initWithNibName:@"IDMAddNoteViewController" bundle:nil];
    self.addNoteViewController.note = text;
    self.addNoteViewController.tags = noteTags;
    
    self.addNoteViewController.noteDelegate = self;
    
    
    [self.popOver setContentViewController: self.addNoteViewController];
    [self.popOver setContentSize: self.addNoteViewController.view.frame.size];
    
    [self.popOver showRelativeToRect: NSMakeRect(0, 0, 0,0)
                         ofView: self.addNoteButton
                  preferredEdge: NSMinYEdge];
    [self.addNoteButton setEnabled:NO];
}

-(void)popoverCleanUp
{
    
    self.popOver = nil;
    self.addNoteViewController = nil;
    [self.addNoteButton setEnabled:YES];
}

-(void)refreshDeleteButtonState
{
    NSInteger selection = [self.tableView selectedRow];
    BOOL enableButton = (selection >=0);
    [self.deleteNoteButton setEnabled:enableButton];
}

#pragma mark - Button Actions

-(IBAction)newNote:(id)sender
{
 
    [self showAddNoteViewWithText:nil tags:nil];
}

-(IBAction)deleteNote:(id)sender
{
    NSInteger selectedNote = [self.tableView selectedRow];
    if( selectedNote < 0 )
        return;
    IDMNote *note = notes[selectedNote];
    [managedObjectContext deleteObject:note];
    [managedObjectContext save:NULL];
    
    [notes removeObject:note];
    [self reloadTable];
    
}

-(IBAction)sync:(id)sender
{
    [self synchronize];
}


#pragma mark - Add Note View Controller Deleagte
-(void)saveNote:(NSString *)text tags:(NSArray *)noteTags
{
    NSLog(@"Saving Note: %@. TAGS: %@", text, noteTags);
        IDMNote *note = [NSEntityDescription insertNewObjectForEntityForName:@"IDMNote" inManagedObjectContext:managedObjectContext];
    
    
    note.attributedText = [[NSAttributedString alloc] initWithString:text];
    NSMutableSet *cdTags = [NSMutableSet setWithCapacity:noteTags.count];
    for (NSString *tagText in noteTags) {
        if (tagText.length == 0) continue;
        IDMTag *tag = [IDMTag tagWithText:tagText inManagedObjectContext:managedObjectContext];
        [cdTags addObject:tag];
    }
    note.tags = cdTags;

    NSError *error;
    [managedObjectContext save:&error];
    [self.popOver performClose:self];
    [self setupTree];
    [self reloadTable];
}

#pragma mark - Popover Delegate
-(void)popoverDidClose:(NSNotification *)notification
{

    [self popoverCleanUp];
}


#pragma mark - Outline View Delegate
-(NSView*)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(NSTableColumn *)tableColumn item:(TreeItem*)item
{
    
    NSString *cellId = @"DataCell";
    if( item != nil && item.header ==  YES)
        cellId = @"HeaderCell";
    NSTableCellView *cellView = [outlineView makeViewWithIdentifier:cellId owner:self];
    TreeItem *treeItem = (TreeItem*)item;
    [cellView.textField setStringValue:treeItem.title];
    [cellView.imageView setImage:nil];
    return cellView;
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification;
{
    [self reloadTable];
}


#pragma mark - Outline View DataSource
-(NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
    TreeItem *treeItem = (TreeItem*)item;
    NSInteger items=4;
    if( item == nil )
        items = 2;
    else
        items = treeItem.childs.count;
    return items;
}

-(BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(TreeItem*)item
{
    return (item!=nil && item.header  && item.childs.count >0);
}

-(BOOL)outlineView:(NSOutlineView *)outlineView isGroupItem:(TreeItem*)item
{
    return ( item.header == YES);
}

-(id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
    TreeItem *objectvalue = nil;
    TreeItem *treeItem = (TreeItem*)item;
    if( treeItem == nil )
    {
        objectvalue = index==0?allNotes:tags;
    }
    else
    {
        if( index  < treeItem.childs.count && index >=0 )
            objectvalue = treeItem.childs[index];
    }
    return objectvalue;
}

#pragma mark - Table View Delegate
-(NSView*)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    NSTableCellView *cell = [self.tableView makeViewWithIdentifier:@"NoteCell" owner:self];
    
    IDMNote *note = notes[row];
    [cell.textField setAttributedStringValue:note.attributedText];
    return cell;
}

-(void)tableViewSelectionDidChange:(NSNotification *)notification
{
    
    [self refreshDeleteButtonState];
    
}

#pragma mark - Table View DataSource
-(NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return notes.count;
}




@end
