//
//  IDMTag.h
//  Idiomatic
//
//  Created by Drew McCormack on 20/09/13.
//  Copyright (c) 2013 The Mental Faculty B.V. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>


@interface IDMTag : NSManagedObject

@property (nonatomic, strong) NSString *text;
@property (nonatomic, strong) NSSet *notes;
@property (nonatomic, readonly) NSString *uniqueIdentifier;

+ (NSArray *)tagsInManagedObjectContext:(NSManagedObjectContext *)context;
+ (instancetype)tagWithText:(NSString *)text inManagedObjectContext:(NSManagedObjectContext *)context;

@end
