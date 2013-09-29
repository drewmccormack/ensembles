//
//  CDELocalFileSystem.h
//  Ensembles
//
//  Created by Drew McCormack on 02/09/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CDECloudFileSystem.h" 

@interface CDELocalCloudFileSystem : NSObject <CDECloudFileSystem>

@property (readonly, nonatomic) NSString *rootDirectory;

- (instancetype)initWithRootDirectory:(NSString *)rootDir;

@end
