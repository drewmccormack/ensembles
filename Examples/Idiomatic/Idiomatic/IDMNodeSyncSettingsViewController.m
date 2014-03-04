//
//  IDMNodeSyncSettingsViewController.m
//  Idiomatic
//
//  Created by Drew McCormack on 04/03/14.
//  Copyright (c) 2014 The Mental Faculty B.V. All rights reserved.
//

#import "IDMNodeSyncSettingsViewController.h"
#import "CDENodeCloudFileSystem.h"
#import "IDMSyncManager.h"

NSString * const IDMNodeCredentialsDidChangeNotification = @"IDMNodeCredentialsDidChangeNotification";

@interface IDMNodeSyncSettingsViewController ()

@property (weak, nonatomic) IBOutlet UITextField *emailTextField;
@property (weak, nonatomic) IBOutlet UITextField *signInPasswordTextField;
@property (weak, nonatomic) IBOutlet UITextField *signUpPasswordTextField;
@property (weak, nonatomic) IBOutlet UITextField *originalPasswordTextField;
@property (weak, nonatomic) IBOutlet UITextField *updatedPasswordTextField;

@end

@implementation IDMNodeSyncSettingsViewController {
    __weak IBOutlet UITableViewCell *signInCell;
    __weak IBOutlet UITableViewCell *signUpCell;
    __weak IBOutlet UITableViewCell *changePasswordCell;
    __weak IBOutlet UITableViewCell *resetPasswordCell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    if (cell == signInCell) {
        self.nodeFileSystem.username = self.emailTextField.text;
        self.nodeFileSystem.password = self.signInPasswordTextField.text;
        [[IDMSyncManager sharedSyncManager] storeNodeCredentials];
        [self dismissViewControllerAnimated:YES completion:NULL];
    }
    else if (cell == signUpCell) {
        
    }
    else if (cell == changePasswordCell) {
        
    }
    else if (cell == resetPasswordCell) {
        
    }
    
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end
