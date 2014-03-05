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

@interface IDMNodeSyncSettingsViewController () <UITextFieldDelegate>

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

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    self.emailTextField.text = self.nodeFileSystem.username;
    self.signInPasswordTextField.text = self.nodeFileSystem.password;
}

- (IBAction)cancel:(id)sender
{
    [self dismissViewControllerAnimated:YES completion:^{
        [[IDMSyncManager sharedSyncManager] cancelNodeCredentialsUpdate];
    }];
}

- (void)signIn
{
    self.nodeFileSystem.username = self.emailTextField.text;
    self.nodeFileSystem.password = self.signInPasswordTextField.text;
    [self dismissViewControllerAnimated:YES completion:^{
        [[IDMSyncManager sharedSyncManager] storeNodeCredentials];
    }];
}

- (void)signUp
{
    self.nodeFileSystem.username = self.emailTextField.text;
    self.nodeFileSystem.password = self.signUpPasswordTextField.text;
    [self.nodeFileSystem signUpWithCompletion:^(NSError *error) {
        if (error) {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Sign Up Failed" message:@"Make sure you enter a valid email address, and password with 6 or more characters." delegate:self cancelButtonTitle:nil otherButtonTitles:@"OK", nil];
            [alert show];
            return;
        }
        
        [self dismissViewControllerAnimated:YES completion:^{
            [[IDMSyncManager sharedSyncManager] storeNodeCredentials];
        }];
    }];
}

- (void)changePassword
{
    self.nodeFileSystem.username = self.emailTextField.text;
    self.nodeFileSystem.password = self.originalPasswordTextField.text;
    [self.nodeFileSystem changePasswordTo:self.updatedPasswordTextField.text withCompletion:^(NSError *error) {
        if (error) {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Could Not Change Password" message:@"Check that your email, and your old password are correct. The new password must have 6 or more characters." delegate:self cancelButtonTitle:nil otherButtonTitles:@"OK", nil];
            [alert show];
            return;
        }
        
        [self dismissViewControllerAnimated:YES completion:^{
            [[IDMSyncManager sharedSyncManager] storeNodeCredentials];
        }];
    }];
}

- (void)resetPassword
{
    self.nodeFileSystem.username = self.emailTextField.text;
    [self.nodeFileSystem resetPasswordWithCompletion:^(NSError *error) {
        if (error) {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Could Not Reset Password" message:@"Check your internet connection, and try again later." delegate:self cancelButtonTitle:nil otherButtonTitles:@"OK", nil];
            [alert show];
        }
        else {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"New Password Sent" message:@"Your new password has been emailed to you. When you receive it, use it to sign in, or choose a new password." delegate:self cancelButtonTitle:nil otherButtonTitles:@"OK", nil];
            [alert show];
        }
    }];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    if (cell == signInCell) {
        [self signIn];
    }
    else if (cell == signUpCell) {
        [self signUp];
    }
    else if (cell == changePasswordCell) {
        [self changePassword];
    }
    else if (cell == resetPasswordCell) {
        [self resetPassword];
    }
    
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    BOOL result = NO;
    if (self.emailTextField == textField) {
        [self.signInPasswordTextField becomeFirstResponder];
    }
    else if (self.originalPasswordTextField == textField) {
        [self.updatedPasswordTextField becomeFirstResponder];
    }
    else if (self.signInPasswordTextField == textField) {
        [self signIn];
    }
    else if (self.signUpPasswordTextField == textField) {
        [self signUp];
    }
    else if (self.updatedPasswordTextField == textField) {
        [self changePassword];
    }
    return result;
}

@end
