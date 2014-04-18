//
//  ViewController.m
//  Magical Record
//
//  Created by Drew McCormack on 18/04/14.
//  Copyright (c) 2014 Drew McCormack. All rights reserved.
//

#import "ViewController.h"
#import "CoreData+MagicalRecord.h"
#import "NumberHolder.h"

@interface ViewController ()

@property (strong, nonatomic) NumberHolder *numberHolder;

@end

@implementation ViewController

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    self.numberHolder = [NumberHolder MR_findFirst];
    if (!self.numberHolder) self.numberHolder = [NumberHolder MR_createEntity];
    
    self.numberLabel.text = self.numberHolder.number.stringValue;
}

- (IBAction)changeNumber:(id)sender
{
    self.numberHolder.number = [NSNumber numberWithInteger:rand()%100+1];
    self.numberLabel.text = self.numberHolder.number.stringValue;
    
    [[NSManagedObjectContext MR_defaultContext] MR_saveToPersistentStoreAndWait];
}

@end
