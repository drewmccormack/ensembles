//
//  IDMTagsViewController.h
//  Idiomatic
//
//  Created by Drew McCormack on 20/09/13.
//  Copyright (c) 2013 The Mental Faculty B.V. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <CoreData/CoreData.h>

@class IDMTag;

@interface IDMTagsViewController : UITableViewController

@property NSManagedObjectContext *managedObjectContext;

- (IBAction)sync:(id)sender;
- (IBAction)toggleSyncEnabled:(id)sender;

- (IBAction)showNodeServerSettings:(id)sender;

@end
