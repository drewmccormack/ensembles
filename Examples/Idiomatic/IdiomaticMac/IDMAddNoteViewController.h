//
//  IDMAddNoteViewController.h
//  Idiomatic
//
//  Created by Ernesto on 10/5/13.
//  Copyright (c) 2013 The Mental Faculty B.V. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@protocol IDMAddNoteDelegate <NSObject>

-(void)saveNote:(NSString*)text tags:(NSArray*)tags;

@end


@interface IDMAddNoteViewController : NSViewController
@property (nonatomic,weak) id<IDMAddNoteDelegate> noteDelegate;
@property (nonatomic,strong) NSString *note;
@property (nonatomic,strong) NSArray *tags;

@end
