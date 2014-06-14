//
//  CDELocalFileSystem.h
//  Ensembles
//
//  Created by Drew McCormack on 02/09/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Ensembles/Ensembles.h>

extern NSString * const nMultipeerCloudFileSystemDidImportFiles;

@interface CDEMultipeerCloudFileSystem : NSObject <CDECloudFileSystem>

@property (readonly, nonatomic) NSString *rootDirectory;
@property (nonatomic, strong, readonly) NSMutableSet *connectedPeers;

- (instancetype)initWithRootDirectory:(NSString *)rootDir;
- (void)start;
- (void)stop;
- (BOOL)sendStatusMessageToPeers:(NSArray *)peersIDs;

@end