//
//  CDEMockLocalFileSystem.h
//  Ensembles
//
//  Created by Drew McCormack on 15/11/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CDELocalCloudFileSystem.h"

@interface CDEMockLocalFileSystem : CDELocalCloudFileSystem

@property (nonatomic, readwrite) id <NSObject, NSCoding, NSCopying> identityToken;

@end

