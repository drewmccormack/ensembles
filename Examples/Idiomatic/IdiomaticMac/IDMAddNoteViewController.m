//
//  IDMAddNoteViewController.m
//  Idiomatic
//
//  Created by Ernesto on 10/5/13.
//  Copyright (c) 2013 The Mental Faculty B.V. All rights reserved.
//

#import "IDMAddNoteViewController.h"

@interface IDMAddNoteViewController ()
@property (nonatomic,strong) IBOutlet NSTextView *textView;
@property (nonatomic,strong) IBOutlet NSTokenField *tokenField;

@end

@implementation IDMAddNoteViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Initialization code here.
    }
    return self;
}


-(void)loadView
{
    [super loadView];
    
    [self.textView setString:self.note?:@""];
    [self.tokenField setObjectValue:self.tags];
    
}

-(void)dealloc
{
    
}

- (void)viewWillMoveToWindow:(NSWindow *)newWindow {

    NSLog(@"View will move to window");
}

-(IBAction)saveNote:(id)sender
{
    NSString *noteText = [self.textView string];
    NSArray *noteTags = [self.tokenField objectValue];
    if( [self.noteDelegate respondsToSelector:@selector(saveNote:tags:) ] )
    {
        [self.noteDelegate saveNote:noteText tags:noteTags];
    }
}

@end
