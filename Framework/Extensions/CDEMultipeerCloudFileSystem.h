//
//  CDEMultipeerCloudFileSystem.h
//  Ensembles
//
//  Created by Drew McCormack on 02/09/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Ensembles/Ensembles.h>

extern NSString * const CDEMultipeerCloudFileSystemDidImportFilesNotification;


@protocol CDEMultipeerConnection <NSObject>

@required
- (BOOL)sendData:(NSData *)data toPeerWithID:(id <NSObject, NSCopying, NSCoding>)peerID;
- (BOOL)sendAndDiscardFileAtURL:(NSURL *)url toPeerWithID:(id <NSObject, NSCopying, NSCoding>)peerID;

@end


@interface CDEMultipeerCloudFileSystem : NSObject <CDECloudFileSystem>

@property (readonly, nonatomic) NSString *rootDirectory;
@property (readonly, weak, nonatomic) id <CDEMultipeerConnection> multipeerConnection;

- (instancetype)initWithRootDirectory:(NSString *)rootDir multipeerConnection:(id <CDEMultipeerConnection>)connection;

- (void)retrieveFilesFromPeersWithIDs:(NSArray *)peerIDs;

- (void)removeAllFiles;

@end


@interface CDEMultipeerCloudFileSystem (MultipeerResponses)

- (void)receiveData:(NSData *)data fromPeerWithID:(id <NSObject, NSCopying, NSCoding>)peerID;
- (void)receiveResourceAtURL:(NSURL *)url fromPeerWithID:(id <NSObject, NSCopying, NSCoding>)peerID;

@end