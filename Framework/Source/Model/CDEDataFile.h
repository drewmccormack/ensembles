//
//  CDEDataFile.h
//  Ensembles iOS
//
//  Created by Drew McCormack on 17/02/14.
//  Copyright (c) 2014 The Mental Faculty B.V. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@class CDEObjectChange;

@interface CDEDataFile : NSManagedObject

@property (nonatomic, strong) NSString *filename;
@property (nonatomic, strong) CDEObjectChange *objectChange;

+ (NSSet *)allFilenamesInManagedObjectContext:(NSManagedObjectContext *)context;
+ (NSSet *)filenamesInStoreModificationEvents:(NSArray *)events;

+ (NSSet *)unreferencedFilenamesInManagedObjectContext:(NSManagedObjectContext *)context;

@end
