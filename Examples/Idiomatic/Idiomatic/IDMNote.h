//
//  IDMNote.h
//  Idiomatic
//
//  Created by Drew McCormack on 20/09/13.
//  Copyright (c) 2013 The Mental Faculty B.V. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@class IDMTag;

@interface IDMNote : NSManagedObject

@property (nonatomic, strong) NSAttributedString *attributedText;
@property (nonatomic) NSDate *creationDate;
@property (nonatomic, strong) NSSet *tags;
@property (nonatomic, strong) NSString *uniqueIdentifier;

@end
