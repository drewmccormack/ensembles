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
@class IDMMediaFile;

@interface IDMNote : NSManagedObject

@property (nonatomic, strong) NSString *text;
@property (nonatomic) NSDate *creationDate;
@property (nonatomic, strong) NSSet *tags;
@property (nonatomic, strong) NSString *uniqueIdentifier;
@property (nonatomic, strong) IDMMediaFile *imageFile;

+ (NSArray *)notesWithTag:(IDMTag*)tag inManagedObjectContext:(NSManagedObjectContext *)context;
+ (NSArray *)notesInManagedObjectContext:(NSManagedObjectContext *)context;

@end
