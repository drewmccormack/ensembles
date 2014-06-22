//
//  CDELocalFileSystem.h
//  Ensembles
//
//  Created by Drew McCormack on 02/09/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <MultipeerConnectivity/MultipeerConnectivity.h>
#import <Ensembles/Ensembles.h>

extern NSString * const nMultipeerCloudFileSystemDidImportFiles;

@interface CDEMultipeerCloudFileSystem : NSObject <CDECloudFileSystem>

- (BOOL)synchronizeFilesViaMultipeerSession:(MCSession *)session withSpecificPeers:(NSArray *)specificPeers;
- (void)handleMessageData:(NSData *)data fromPeer:(MCPeerID *)peerID inSession:(MCSession *)session;
- (void)importArchiveAtURL:(NSURL *)archiveURL archiveName:(NSString *)archiveName;

@end