//
//  AppDelegate.m
//  IdiomaticMac
//
//  Created by Ernesto on 10/5/13.
//  Copyright (c) 2013 The Mental Faculty B.V. All rights reserved.
//

#import <CoreData/CoreData.h>

#import "IDMAppDelegateMac.h"
#import "IDMAddNoteViewController.h"
#import "IDMNote.h"
#import "IDMTag.h"

NSString * const IDMSyncActivityDidBeginNotification = @"IDMSyncActivityDidBegin";
NSString * const IDMSyncActivityDidEndNotification = @"IDMSyncActivityDidEnd";

@interface IDMTreeItem : NSObject
@property (nonatomic,strong) NSMutableArray *children;
@property (nonatomic) BOOL header;
@property (nonatomic,strong) NSString *title;
@property (nonatomic,strong) id representedObject;
@end

@implementation IDMTreeItem
@end

@interface IDMAppDelegateMac () <CDEPersistentStoreEnsembleDelegate, NSTableViewDataSource, NSTableViewDelegate , NSOutlineViewDelegate, NSOutlineViewDataSource, NSPopoverDelegate, IDMAddNoteDelegate> {
    NSManagedObjectContext *managedObjectContext;
    CDEPersistentStoreEnsemble *ensemble;
    CDEICloudFileSystem *cloudFileSystem;
    NSUInteger activeMergeCount;
    IDMTreeItem *noteItems;
    IDMTreeItem *tagItems;
    NSMutableArray *notes;
}

@property (nonatomic, weak) IBOutlet NSOutlineView *collectionView;
@property (nonatomic, weak) IBOutlet NSTableView *tableView;
@property (nonatomic, weak) IBOutlet NSButton *addNoteButton;
@property (nonatomic, weak) IBOutlet NSButton *deleteNoteButton;
@property (nonatomic, strong) IDMAddNoteViewController *addNoteViewController;
@property (nonatomic, strong) NSPopover *popover;

@end


@implementation IDMAppDelegateMac

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
    NSDictionary *options = @{NSMigratePersistentStoresAutomaticallyOption: @YES, NSInferMappingModelAutomaticallyOption: @YES};
    [coordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:options error:&error];
    managedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    managedObjectContext.persistentStoreCoordinator = coordinator;
    managedObjectContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy;
    
    // Setup Ensemble
    cloudFileSystem = [[CDEICloudFileSystem alloc] initWithUbiquityContainerIdentifier:nil];
    ensemble = [[CDEPersistentStoreEnsemble alloc] initWithEnsembleIdentifier:@"MainStore" persistentStoreURL:storeURL managedObjectModelURL:modelURL cloudFileSystem:cloudFileSystem];
    ensemble.delegate = self;
    
    [self setupTree];
}

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    [self synchronize];
}

#pragma mark - Sync Methods

-(IBAction)sync:(id)sender
{
    [self synchronize];
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

#pragma mark - Outline

-(void)setupTree
{
    noteItems  = [[IDMTreeItem alloc] init];
    noteItems.title = @"ALL NOTES";
    noteItems.header = YES;
    
    tagItems = [[IDMTreeItem alloc] init];
    tagItems.title = @"TAGS";
    tagItems.header = YES;
    
    NSArray *allTags = [IDMTag tagsInManagedObjectContext:managedObjectContext];
    if(!tagItems.children) tagItems.children = [[NSMutableArray alloc] init];
    for(IDMTag *tag in allTags) {
        IDMTreeItem *item = [IDMTreeItem new];
        item.title = tag.text;
        item.representedObject = tag;
        item.header = NO;
        [tagItems.children addObject:item];
    }
    
    [self.collectionView reloadData];
    [self.collectionView expandItem:nil expandChildren:YES];
}

-(void)reloadTable
{
    IDMTag *tag;
    NSInteger selectedRow = [self.collectionView selectedRow];
    if( selectedRow > 0) {   // First row is "All Tags"
        IDMTreeItem * item = [self.collectionView itemAtRow:selectedRow];
        tag = item.representedObject;
    }
    
    notes = [[IDMNote notesWithTag:tag inManagedObjectContext:managedObjectContext] mutableCopy];
    
    [self.tableView reloadData];
    [self.deleteNoteButton setEnabled:NO];
}

#pragma mark - Adding and Deleting Notes

-(IBAction)newNote:(id)sender
{
    [self showAddNoteViewWithText:nil tags:nil];
}

-(IBAction)deleteNote:(id)sender
{
    NSInteger selectedNote = [self.tableView selectedRow];
    if( selectedNote < 0 ) return;
    
    IDMNote *note = notes[selectedNote];
    [managedObjectContext deleteObject:note];
    [managedObjectContext save:NULL];
    
    [notes removeObject:note];
    [self reloadTable];
}

-(void)showAddNoteViewWithText:(NSString*)text tags:(NSArray*)noteTags
{
    if( self.popover )
    {
        [self.popover performClose:self];
        self.popover = nil;
        self.addNoteViewController = nil;
    }
    self.popover = [[NSPopover alloc] init];
    
    [self.popover setBehavior: NSPopoverBehaviorTransient];
    [self.popover setDelegate: self];
    
    
    self.addNoteViewController = [[IDMAddNoteViewController alloc] initWithNibName:@"IDMAddNoteViewController" bundle:nil];
    self.addNoteViewController.note = text;
    self.addNoteViewController.tags = noteTags;
    
    self.addNoteViewController.noteDelegate = self;
    
    
    [self.popover setContentViewController:self.addNoteViewController];
    [self.popover setContentSize:self.addNoteViewController.view.frame.size];
    
    [self.popover showRelativeToRect:NSMakeRect(0, 0, 0, 0) ofView:self.addNoteButton preferredEdge:NSMinYEdge];
    [self.addNoteButton setEnabled:NO];
}

-(void)popoverCleanUp
{
    self.popover = nil;
    self.addNoteViewController = nil;
    [self.addNoteButton setEnabled:YES];
}

-(void)refreshDeleteButtonState
{
    NSInteger selection = [self.tableView selectedRow];
    BOOL enableButton = (selection >=0);
    [self.deleteNoteButton setEnabled:enableButton];
}

- (void)saveNote:(NSString *)text tags:(NSArray *)noteTags
{
    NSLog(@"Saving Note: %@. TAGS: %@", text, noteTags);
    IDMNote *note = [NSEntityDescription insertNewObjectForEntityForName:@"IDMNote" inManagedObjectContext:managedObjectContext];
    
    
    note.text = [[NSString alloc] initWithString:text];
    NSMutableSet *cdTags = [NSMutableSet setWithCapacity:noteTags.count];
    for (NSString *tagText in noteTags) {
        if (tagText.length == 0) continue;
        IDMTag *tag = [IDMTag tagWithText:tagText inManagedObjectContext:managedObjectContext];
        [cdTags addObject:tag];
    }
    note.tags = cdTags;
    
    NSError *error;
    [managedObjectContext save:&error];
    [self.popover performClose:self];
    [self setupTree];
    [self reloadTable];
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

#pragma mark - Popover Delegate

- (void)popoverDidClose:(NSNotification *)notification
{
    [self popoverCleanUp];
}

#pragma mark - Outline View Delegate

- (NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(NSTableColumn *)tableColumn item:(IDMTreeItem *)item
{
    NSString *cellId = @"DataCell";
    if (!item && item.header ==  YES) cellId = @"HeaderCell";
    
    NSTableCellView *cellView = [outlineView makeViewWithIdentifier:cellId owner:self];
    IDMTreeItem *treeItem = (id)item;
    cellView.textField.stringValue = treeItem.title;
    cellView.imageView.image = nil;
    
    return cellView;
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification;
{
    [self reloadTable];
}

#pragma mark - Outline View DataSource

-(NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
    IDMTreeItem *treeItem = (id)item;
    NSInteger numberOfItems = item ? treeItem.children.count : 2;
    return numberOfItems;
}

-(BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(IDMTreeItem*)item
{
    return (item.header && item.children.count > 0);
}

-(BOOL)outlineView:(NSOutlineView *)outlineView isGroupItem:(IDMTreeItem*)item
{
    return (item.header == YES);
}

-(id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
    IDMTreeItem *objectvalue = nil;
    IDMTreeItem *treeItem = (id)item;
    if(treeItem == nil) {
        objectvalue = index==0?noteItems:tagItems;
    }
    else if (index < treeItem.children.count && index >= 0) {
        objectvalue = treeItem.children[index];
    }
    return objectvalue;
}

#pragma mark - Table View Data Source and Delegate

-(NSView*)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    NSTableCellView *cell = [self.tableView makeViewWithIdentifier:@"NoteCell" owner:self];
    
    IDMNote *note = notes[row];
    cell.textField.stringValue = note.text;
    return cell;
}

-(void)tableViewSelectionDidChange:(NSNotification *)notification
{
    [self refreshDeleteButtonState];
}

-(NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return notes.count;
}

@end
