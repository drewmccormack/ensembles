//
//  IDMMediaFile.h
//  Idiomatic
//
//  Created by Drew McCormack on 21/02/14.
//  Copyright (c) 2014 The Mental Faculty B.V. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>


@interface IDMMediaFile : NSManagedObject

@property (nonatomic, strong) NSData *data;
@property (nonatomic, strong) NSString *uniqueIdentifier;

@end
