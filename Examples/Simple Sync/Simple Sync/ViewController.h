//
//  ViewController.h
//  Magical Record
//
//  Created by Drew McCormack on 18/04/14.
//  Copyright (c) 2014 Drew McCormack. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface ViewController : UIViewController

@property (weak, nonatomic) IBOutlet UILabel *numberLabel;
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *activityIndicator;
@property (strong, nonatomic) NSManagedObjectContext *managedObjectContext;

- (void)refresh;

@end
