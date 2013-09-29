//
//  IDMNotesViewController.h
//  Idiomatic
//
//  Created by Drew McCormack on 20/09/13.
//  Copyright (c) 2013 The Mental Faculty B.V. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <CoreData/CoreData.h>

@class IDMTag;
@class IDMNote;

@interface IDMNotesViewController : UITableViewController

@property (strong, nonatomic) NSManagedObjectContext *managedObjectContext;
@property (strong, nonatomic) IDMTag *tag;

@property (weak, nonatomic) IBOutlet UIBarButtonItem *addBarButtonItem;

@end
