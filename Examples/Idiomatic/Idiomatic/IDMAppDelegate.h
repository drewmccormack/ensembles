//
//  IDMAppDelegate.h
//  Idiomatic
//
//  Created by Drew McCormack on 20/09/13.
//  Copyright (c) 2013 The Mental Faculty B.V. All rights reserved.
//

#import <UIKit/UIKit.h>

NSString * const IDMSyncActivityDidBeginNotification;
NSString * const IDMSyncActivityDidEndNotification;

@interface IDMAppDelegate : UIResponder <UIApplicationDelegate>

@property (strong, nonatomic) UIWindow *window;

- (void)synchronize;

@end
