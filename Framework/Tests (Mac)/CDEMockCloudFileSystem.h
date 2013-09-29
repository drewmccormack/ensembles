//
//  CDEMockCloudFileSystem.h
//  Ensembles
//
//  Created by Drew McCormack on 11/09/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CDECloudFileSystem.h"
#import "CDECloudFile.h"

@interface CDEMockItem : NSObject

@property BOOL isDirectory;
@property NSData *data;
@property NSString *path;

@end

@interface CDEMockCloudFileSystem : NSObject <CDECloudFileSystem>

@property NSMutableDictionary *itemsByRemotePath;

@end
