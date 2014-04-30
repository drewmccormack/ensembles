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
    self.numberLabel.text = self.numberHolder.number.stringValue;
}

- (IBAction)changeNumber:(id)sender
{
    NSUInteger oldNumber = self.numberHolder.number.unsignedIntegerValue;
    NSUInteger newNumber = 0;
    do newNumber = rand()%100; while (oldNumber == newNumber);
    self.numberHolder.number = [NSNumber numberWithInteger:newNumber];
    self.numberLabel.text = self.numberHolder.number.stringValue;
    
    [[NSManagedObjectContext MR_defaultContext] MR_saveToPersistentStoreAndWait];
}

- (void)refresh
{
    self.numberLabel.text = self.numberHolder.number.stringValue;

}

@end
