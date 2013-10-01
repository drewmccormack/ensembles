//
//  CDEFile.h
//  Ensembles
//
//  Created by Drew McCormack on 4/12/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface CDECloudFile : NSObject <NSCoding, NSCopying>

@property (copy) NSString *path;
@property (copy) NSString *name;
@property unsigned long long size;

@end
