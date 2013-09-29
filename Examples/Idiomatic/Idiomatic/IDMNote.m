//
//  IDMNote.m
//  Idiomatic
//
//  Created by Drew McCormack on 20/09/13.
//  Copyright (c) 2013 The Mental Faculty B.V. All rights reserved.
//

#import "IDMNote.h"
#import "IDMTag.h"


@implementation IDMNote

@dynamic attributedText;
@dynamic creationDate;
@dynamic tags;
@dynamic uniqueIdentifier;

- (void)awakeFromInsert
{
    [super awakeFromInsert];
    self.uniqueIdentifier = [[NSProcessInfo processInfo] globallyUniqueString];
    self.creationDate = [[NSDate alloc] init];
}

@end
