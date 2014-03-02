//
//  IDMAppDelegate.h
//  Idiomatic
//
//  Created by Drew McCormack on 20/09/13.
//  Copyright (c) 2013 The Mental Faculty B.V. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "CoreDataEnsembles.h"

extern NSString * const IDMSyncActivityDidBeginNotification;
extern NSString * const IDMSyncActivityDidEndNotification;

extern NSString * const IDMCloudServiceUserDefaultKey;
extern NSString * const IDMICloudService;
extern NSString * const IDMDropboxService;
extern NSString * const IDMNodeS3Service;

@interface IDMAppDelegate : UIResponder <UIApplicationDelegate>

@property (strong, nonatomic) UIWindow *window;

- (void)connectToSyncService:(NSString *)serviceId withCompletion:(CDECompletionBlock)completion;
- (void)disconnectFromSyncServiceWithCompletion:(CDECodeBlock)completion;

- (void)synchronizeWithCompletion:(CDECompletionBlock)completion;
- (BOOL)canSynchronize;

@end
