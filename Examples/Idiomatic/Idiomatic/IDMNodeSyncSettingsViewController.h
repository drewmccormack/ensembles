//
//  IDMNodeSyncSettingsViewController.h
//  Idiomatic
//
//  Created by Drew McCormack on 04/03/14.
//  Copyright (c) 2014 The Mental Faculty B.V. All rights reserved.
//

#import <UIKit/UIKit.h>

@class CDENodeCloudFileSystem;

extern NSString * const IDMNodeCredentialsDidChangeNotification;

@interface IDMNodeSyncSettingsViewController : UITableViewController

@property (nonatomic, readwrite, strong) CDENodeCloudFileSystem *nodeFileSystem;

- (IBAction)cancel:(id)sender;

@end
