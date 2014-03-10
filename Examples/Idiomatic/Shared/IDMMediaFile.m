//
//  IDMMediaFile.m
//  Idiomatic
//
//  Created by Drew McCormack on 21/02/14.
//  Copyright (c) 2014 The Mental Faculty B.V. All rights reserved.
//

#import "IDMMediaFile.h"


@implementation IDMMediaFile

@dynamic data;
@dynamic uniqueIdentifier;

- (void)awakeFromInsert
{
    [super awakeFromInsert];
    if (!self.uniqueIdentifier) self.uniqueIdentifier = [[NSProcessInfo processInfo] globallyUniqueString];
}

@end
