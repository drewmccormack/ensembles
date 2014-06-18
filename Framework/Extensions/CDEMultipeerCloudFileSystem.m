//
//  CDELocalFileSystem.m
//  Ensembles
//
//  Created by Drew McCormack on 02/09/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import <MultipeerConnectivity/MultipeerConnectivity.h>

#import "CDEMultipeerCloudFileSystem.h"
#import <CommonCrypto/CommonDigest.h>
#import "SSZipArchive.h"

#ifdef DEBUG
@implementation NSData (Md5)
- (NSString *)md5 {
	const char *cStr = [self bytes];
	unsigned char digest[CC_MD5_DIGEST_LENGTH];
	CC_MD5( cStr, (CC_LONG)[self length], digest );
	NSString* s = [NSString stringWithFormat: @"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
				   digest[0], digest[1],
				   digest[2], digest[3],
				   digest[4], digest[5],
				   digest[6], digest[7],
				   digest[8], digest[9],
				   digest[10], digest[11],
				   digest[12], digest[13],
				   digest[14], digest[15]];
	return s;
}
@end
#endif

@implementation NSString (Multipeer)
- (NSString *)stringByRemovingPrefix:(NSString *)prefix
{
	NSRange aRange = [self rangeOfString:prefix options:NSAnchoredSearch];

	if ((aRange.length == 0) || (aRange.location != 0)) {
		return self;
	}

	return [self substringFromIndex:aRange.length];
}
@end

// PEER MESSAGE
typedef NS_ENUM (NSInteger, PeerMessageType) {
	PeerMessageTypeStatus = 1,
	PeerMessageTypeRequest = 2
};

NSString *const SyncPeerService = @"popina-sync";
NSString *const nMultipeerCloudFileSystemDidImportFiles = @"MultipeerCloudFileSystemDidImportFiles";
NSString *const PeerMessageFilesPaths = @"filesPaths";
NSString *const PeerMessageMessageType = @"messageType";

@interface CDEMultipeerCloudFileSystem () <MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate>
{
	NSFileManager *fileManager;
    NSString *localRootDirectoryPath;
    NSString *uniqueIdentifier;
    MCSession *peerSession;
    MCNearbyServiceBrowser *peerBrowser;
    MCNearbyServiceAdvertiser *peerAdvertizer;
}
@end


@implementation CDEMultipeerCloudFileSystem

- (instancetype)init
{
	self = [super init];

    if (self) {
        _connectedPeers = [NSMutableSet set];
		fileManager = [[NSFileManager alloc] init];

        NSURL *directoryURL = [fileManager URLForDirectory:NSDocumentDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:NULL];
        directoryURL = [directoryURL URLByAppendingPathComponent:@"cloudfiles" isDirectory:YES];
		localRootDirectoryPath = directoryURL.path;

        [fileManager createDirectoryAtPath:directoryURL.path withIntermediateDirectories:YES attributes:nil error:NULL];

		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(start) name:UIApplicationDidBecomeActiveNotification object:nil];
        //		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(shouldDisconnect) name:UIApplicationWillResignActiveNotification object:nil];
	}

	return self;
}

- (BOOL)isConnected
{
    return YES;
}

- (void)connect:(CDECompletionBlock)completion
{
    if (completion) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil);
        });
    }
}

- (id <NSObject, NSCoding, NSCopying>)identityToken
{
    return NSUserName();
}

- (void)fileExistsAtPath:(NSString *)path completion:(void(^)(BOOL exists, BOOL isDirectory, NSError *error))block
{
    BOOL exists, isDir;
    exists = [fileManager fileExistsAtPath:[self fullPathForRelativePath:path] isDirectory:&isDir];

    if (block) {
        dispatch_async(dispatch_get_main_queue(), ^{
            block(exists, isDir, nil);
        });
    }
}

- (void)contentsOfDirectoryAtPath:(NSString *)path completion:(void(^)(NSArray *contents, NSError *error))block
{
    NSMutableArray *contents = [[NSMutableArray alloc] init];
    NSDirectoryEnumerator *dirEnum = [fileManager enumeratorAtPath:[self fullPathForRelativePath:path]];
    NSString *filename;

    while ((filename = [dirEnum nextObject])) {
        if ([filename hasPrefix:@"."]) continue; // Skip .DS_Store and other system files
        NSString *filePath = [path stringByAppendingPathComponent:filename];

        if ([dirEnum.fileAttributes.fileType isEqualToString:NSFileTypeDirectory]) {
            [dirEnum skipDescendants];
            CDECloudDirectory *dir = [[CDECloudDirectory alloc] init];
            dir.name = filename;
            dir.path = filePath;
            [contents addObject:dir];
        }
        else {
            CDECloudFile *file = [CDECloudFile new];
            file.name = filename;
            file.path = filePath;
            file.size = dirEnum.fileAttributes.fileSize;
            [contents addObject:file];
        }
    }

    if (block) {
        dispatch_async(dispatch_get_main_queue(), ^{
            block(contents, nil);
        });
    }
}

- (void)createDirectoryAtPath:(NSString *)path completion:(CDECompletionBlock)block
{
    NSError *error = nil;
    [fileManager createDirectoryAtPath:[self fullPathForRelativePath:path] withIntermediateDirectories:NO attributes:nil error:&error];

    if (block) {
        dispatch_async(dispatch_get_main_queue(), ^{
            block(error);
        });
    }
}

- (void)removeItemAtPath:(NSString *)fromPath completion:(CDECompletionBlock)block
{
    NSError *error = nil;
    [fileManager removeItemAtPath:[self fullPathForRelativePath:fromPath] error:&error];

    if (block) {
        dispatch_async(dispatch_get_main_queue(), ^{
            block(error);
        });
    }
}

- (void)uploadLocalFile:(NSString *)fromPath toPath:(NSString *)toPath completion:(CDECompletionBlock)block
{
    NSError *error = nil;
    [fileManager copyItemAtPath:fromPath toPath:[self fullPathForRelativePath:toPath] error:&error];

    if (block) {
        dispatch_async(dispatch_get_main_queue(), ^{
            block(error);
        });
    }
}

- (void)downloadFromPath:(NSString *)fromPath toLocalFile:(NSString *)toPath completion:(CDECompletionBlock)block
{
    NSError *error = nil;
    [fileManager copyItemAtPath:[self fullPathForRelativePath:fromPath] toPath:toPath error:&error];

    if (block) {
        dispatch_async(dispatch_get_main_queue(), ^{
            block(error);
        });
    }
}

#pragma mark - MultiPeerManager methods

- (void)start
{
	[self stop];

    if (nil == uniqueIdentifier) {
        CFUUIDRef uuidObject = CFUUIDCreate(kCFAllocatorDefault);
        uniqueIdentifier = (__bridge_transfer NSString *)CFUUIDCreateString(kCFAllocatorDefault, uuidObject);
        CFRelease(uuidObject);
    }

	MCPeerID *peerID = [[MCPeerID alloc] initWithDisplayName:[[UIDevice currentDevice] name]];
	peerSession = [[MCSession alloc] initWithPeer:peerID securityIdentity:nil encryptionPreference:MCEncryptionRequired];
	peerSession.delegate = self;

    peerAdvertizer = [[MCNearbyServiceAdvertiser alloc] initWithPeer:peerID discoveryInfo:@{@"uniqueIdentifier": uniqueIdentifier} serviceType:SyncPeerService];
    peerAdvertizer.delegate = self;
    [peerAdvertizer startAdvertisingPeer];

    peerBrowser = [[MCNearbyServiceBrowser alloc] initWithPeer:peerID serviceType:SyncPeerService];
    peerBrowser.delegate = self;
    [peerBrowser startBrowsingForPeers];
}

- (void)stop
{
    [peerSession disconnect];
	peerSession = nil;

	[peerBrowser stopBrowsingForPeers];
	peerBrowser = nil;

	[peerAdvertizer stopAdvertisingPeer];
	peerAdvertizer = nil;

	@synchronized(self.connectedPeers)
	{
		[self.connectedPeers removeAllObjects];
	}
}

- (BOOL)sendStatusMessageToAllPeers
{
    return [self sendStatusMessageToPeers:peerSession.connectedPeers];
}

- (BOOL)sendStatusMessageToPeers:(NSArray *)peersIDs
{
    BOOL success = NO;

	if (peerSession.connectedPeers.count == 0) {
		CDELog(CDELoggingLevelVerbose, @"MPC sendStatusMessageToPeers : NO peer to send data to");
		return NO;
	}

    NSSet *localFilesPaths = [self localFilePaths];
    NSDictionary *peerMessage = @{ PeerMessageMessageType : @(PeerMessageTypeStatus), PeerMessageFilesPaths : localFilesPaths};

	if (localFilesPaths.count > 0 && peerSession.connectedPeers.count > 0 && peersIDs.count > 0) {
		NSData *peerMessageData = [NSKeyedArchiver archivedDataWithRootObject:peerMessage];
		NSError *error;
		success = [peerSession sendData:peerMessageData toPeers:peersIDs withMode:MCSessionSendDataReliable error:&error];

		if (error || NO == success) {
			CDELog(CDELoggingLevelError, @"MultiPeer ERROR Sending HeaderData A : %@", error);
		}
	}
    
	return success;
}

#pragma mark - Directory methods

- (NSString *)fullPathForRelativePath:(NSString *)path
{
	return [localRootDirectoryPath stringByAppendingPathComponent:path];
}

- (NSString *)pathForFileURL:(NSURL *)fileURL relativeToURL:(NSURL *)baseURL
{
	NSString *localAbsolutePath = fileURL.URLByResolvingSymlinksInPath.absoluteURL.path;
    NSString *localBasePath = baseURL.URLByResolvingSymlinksInPath.absoluteURL.path;
	NSString *relativePath = [localAbsolutePath stringByRemovingPrefix:localBasePath];

	if ([relativePath hasPrefix:@"/"]) {
		relativePath = [relativePath stringByReplacingCharactersInRange:NSMakeRange(0, 1) withString:@""];
	}

	return relativePath;
}

- (NSSet *)localFilePaths
{
	NSDirectoryEnumerator *enumerator = [fileManager enumeratorAtURL:[NSURL fileURLWithPath:localRootDirectoryPath]
                                          includingPropertiesForKeys:@[NSURLNameKey, NSURLIsDirectoryKey]
                                                             options:NSDirectoryEnumerationSkipsHiddenFiles
                                                        errorHandler: ^BOOL (NSURL *url, NSError *error) {
                                                            CDELog(CDELoggingLevelError, @"[Error] %@ (%@)", error, url);
                                                            return YES;
                                                        }];

	NSMutableSet *mutableFilePaths = [NSMutableSet set];

	for (NSURL *fileURL in enumerator) {
		NSString *filename;
		[fileURL getResourceValue:&filename forKey:NSURLNameKey error:nil];

		NSNumber *isDirectory;
		[fileURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];

		if (NO == [isDirectory boolValue]) {
			[mutableFilePaths addObject:[self pathForFileURL:fileURL relativeToURL:[NSURL fileURLWithPath:localRootDirectoryPath]]];
		}
	}

	return [mutableFilePaths copy];
}

- (BOOL)missingLocalFilesForFilesPaths:(NSSet *)filesPaths
{
	for (NSString *path in filesPaths) {
		NSURL *localFileURL = [[[NSURL fileURLWithPath:localRootDirectoryPath] URLByResolvingSymlinksInPath] URLByAppendingPathComponent:path];

		if (NO == [fileManager fileExistsAtPath:localFileURL.path]) {
			return YES;
		}
	}

	return NO;
}

- (NSURL *)contentDataURLForFilesPaths:(NSSet *)filesPaths
{
	if (filesPaths.count == 0) {
		return nil;
	}

	NSURL *rootTemporaryURL = [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
	NSURL *contentDirectoryTemporaryURL = [rootTemporaryURL URLByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString] isDirectory:YES];

	for (NSString *path in filesPaths) {
		NSString *localPath = [localRootDirectoryPath stringByAppendingPathComponent:path];

		if (YES == [fileManager fileExistsAtPath:localPath]) {
            NSString *tempPath = [contentDirectoryTemporaryURL.path stringByAppendingPathComponent:path];
            NSError *error;
            [fileManager createDirectoryAtPath:[tempPath stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:&error];
            [fileManager copyItemAtPath:localPath toPath:tempPath error:&error];
		}
	}

	NSURL *zipFileURL = [contentDirectoryTemporaryURL URLByAppendingPathExtension:@"zip"];
    BOOL successArchive = [SSZipArchive createZipFileAtPath:zipFileURL.path withContentsOfDirectory:contentDirectoryTemporaryURL.path];

	if (NO == successArchive) {
		CDELog(CDELoggingLevelError, @"Compression failed");
	}

	return zipFileURL;
}

#pragma mark -  MCNearbyServiceBrowserDelegate

- (void)browser:(MCNearbyServiceBrowser *)browser foundPeer:(MCPeerID *)peerID withDiscoveryInfo:(NSDictionary *)info
{
    if (browser == peerBrowser) {
		CDELog(CDELoggingLevelVerbose, @"MPC foundPeer:%@ withDiscoveryInfo: %@", peerID, info);

        NSString *otherPeerUniqueIdentifier = info[@"uniqueIdentifier"];
		BOOL shouldInvite = ([otherPeerUniqueIdentifier compare:uniqueIdentifier] != NSOrderedDescending);

        if (shouldInvite) {
            if (NO == [peerSession.myPeerID isEqual:peerID] && NO == [peerSession.myPeerID.displayName isEqualToString:peerID.displayName]) {
                NSData *context = [uniqueIdentifier dataUsingEncoding:NSUTF8StringEncoding];
                [browser invitePeer:peerID toSession:peerSession withContext:context timeout:30.0];
                CDELog(CDELoggingLevelVerbose, @"Inviting %@", peerID.displayName);
            }
        }
	}
}

- (void)browser:(MCNearbyServiceBrowser *)browser lostPeer:(MCPeerID *)peerID
{
	if (browser == peerBrowser) {
        if (NO == [peerSession.myPeerID isEqual:peerID]) {
			CDELog(CDELoggingLevelVerbose, @"MPC lostPeer");
			[[NSNotificationCenter defaultCenter] postNotificationName:@"disconnected" object:nil];
			[self removePeer:peerID];
			[peerBrowser startBrowsingForPeers];
		}
	}
}

- (void)browser:(MCNearbyServiceBrowser *)browser didNotStartBrowsingForPeers:(NSError *)error
{
	if (browser == peerBrowser) {
		CDELog(CDELoggingLevelVerbose, @"MPC didNotStartBrowsingForPeers ERROR %@", error);
		[peerBrowser startBrowsingForPeers];
	}
}

- (void)addPeer:(MCPeerID *)peer
{
	@synchronized(self.connectedPeers)
	{
		[self.connectedPeers addObject:peer];
	}
}

- (void)removePeer:(MCPeerID *)peer
{
	@synchronized(self.connectedPeers)
	{
		[self.connectedPeers removeObject:peer];
	}
}

- (BOOL)hasPeer:(MCPeerID *)peer
{
	BOOL hasPeer = NO;

	@synchronized(self.connectedPeers)
	{
		hasPeer = [self.connectedPeers containsObject:peer];
	}

	return hasPeer;
}

#pragma mark - MCNearbyServiceAdvertiserDelegate

- (void)advertiser:(MCNearbyServiceAdvertiser *)advertiser didReceiveInvitationFromPeer:(MCPeerID *)peerID withContext:(NSData *)context invitationHandler:(void (^)(BOOL accept, MCSession *session))invitationHandler
{
	CDELog(CDELoggingLevelVerbose, @"MPC didReceiveInvitationFromPeer:%@", peerID);

	if (advertiser == peerAdvertizer) {
		NSString *otherPeerUniqueIdentifier = [NSString stringWithUTF8String:context.bytes];
		BOOL shouldInvite = ([otherPeerUniqueIdentifier compare:uniqueIdentifier] == NSOrderedDescending);

		if (NO == [self hasPeer:peerID] && YES == shouldInvite) {
			CDELog(CDELoggingLevelVerbose, @"------------------------------------- %@ ACCEPT %@", peerSession.myPeerID.displayName, peerID.displayName);
			invitationHandler(YES, peerSession);
		}
		else {
			CDELog(CDELoggingLevelVerbose, @"NOT ACCEPTING PEER INVITE");
			invitationHandler(NO, peerSession);
		}
	}
}

- (void)advertiser:(MCNearbyServiceAdvertiser *)advertiser didNotStartAdvertisingPeer:(NSError *)error
{
	if (advertiser == peerAdvertizer) {
		CDELog(CDELoggingLevelVerbose, @"MPC didNotStartAdvertisingPeer");
	}
}

#pragma mark - MCSessionDelegate

- (void)session:(MCSession *)session peer:(MCPeerID *)peerID didChangeState:(MCSessionState)state
{
	if (session == peerSession) {
		switch (state) {
			case MCSessionStateConnected : {
                CDELog(CDELoggingLevelVerbose, @"MPC MCSessionStateConnected:%@", peerID);
                [self sendStatusMessageToPeers:@[peerID]];
                [[NSNotificationCenter defaultCenter] postNotificationName:@"connected" object:nil];

                if (NO == [self hasPeer:peerID] &&
                    NO == [peerSession.myPeerID isEqual:peerID] &&
                    NO == [peerSession.myPeerID.displayName isEqualToString:peerID.displayName]) {
                    [self addPeer:peerID];
                }
			}
				break;

			case MCSessionStateConnecting: {
				CDELog(CDELoggingLevelVerbose, @"MPC MCSessionStateConnecting:%@", peerID);
				[self removePeer:peerID];
				[[NSNotificationCenter defaultCenter] postNotificationName:@"connecting" object:nil];
			}
                break;

			case MCSessionStateNotConnected: {
				CDELog(CDELoggingLevelVerbose, @"MPC MCSessionStateNotConnected:%@", peerID);
				[[NSNotificationCenter defaultCenter] postNotificationName:@"disconnected" object:nil];
				[self removePeer:peerID];
				[peerBrowser startBrowsingForPeers];
			}
                break;

			default:
				[self removePeer:peerID];
				break;
		}
	}
}

- (void)session:(MCSession *)session didReceiveData:(NSData *)data fromPeer:(MCPeerID *)peerID
{
    if (session == peerSession) {
		CDELog(CDELoggingLevelVerbose, @"MPC didReceiveData");

		if (data.length == 0) {
			CDELog(CDELoggingLevelVerbose, @"MPC didReceiveData DATA IS EMPTY");
			return;
		}

		NSDictionary *peerMessage = [NSKeyedUnarchiver unarchiveObjectWithData:data];
        NSSet *remoteFiles = peerMessage[PeerMessageFilesPaths];

		if (PeerMessageTypeStatus == [peerMessage[PeerMessageMessageType] integerValue]) {
			CDELog(CDELoggingLevelVerbose, @"PeerManager didReceiveData: PeerMessageTypeStatus");
            NSSet *localFiles = [self localFilePaths];

            NSMutableSet *unionObjects = [localFiles mutableCopy];
            [unionObjects addObjectsFromArray:remoteFiles.allObjects];

            NSMutableSet *missingLocalFiles = [unionObjects mutableCopy];
            [missingLocalFiles minusSet:localFiles];

            NSMutableSet *missingRemoteFiles = [unionObjects mutableCopy];
            [missingRemoteFiles minusSet:remoteFiles];

			if (missingLocalFiles.count > 0) {
				CDELog(CDELoggingLevelVerbose, @"Missing files LOCALLY");
                NSDictionary *peerMessageRequest = @{ PeerMessageMessageType : @(PeerMessageTypeRequest), PeerMessageFilesPaths : missingLocalFiles};

				if (remoteFiles.count > 0) {
					NSData *peerMessageData = [NSKeyedArchiver archivedDataWithRootObject:peerMessageRequest];
					NSError *error;
					BOOL success = [session sendData:peerMessageData toPeers:@[peerID] withMode:MCSessionSendDataReliable error:&error];

					if (error || NO == success) {
						CDELog(CDELoggingLevelError, @"MultiPeer ERROR Sending HeaderData : %@", error);
					}
				}
			}

            if (missingRemoteFiles.count > 0) {
				CDELog(CDELoggingLevelVerbose, @"Missing files REMOTELY");
                NSDictionary *peerMessageRequest = @{ PeerMessageMessageType : @(PeerMessageTypeStatus), PeerMessageFilesPaths : remoteFiles};
				BOOL success = NO;

				if (remoteFiles.count > 0) {
					NSData *peerMessageData = [NSKeyedArchiver archivedDataWithRootObject:peerMessageRequest];
					NSError *error;
					success = [session sendData:peerMessageData toPeers:@[peerID] withMode:MCSessionSendDataReliable error:&error];

					if (error || NO == success) {
						CDELog(CDELoggingLevelError, @"MultiPeer ERROR Sending HeaderData : %@", error);
					}
				}
			}

            if (missingRemoteFiles == 0 && missingRemoteFiles == 0) {
				CDELog(CDELoggingLevelVerbose, @"NOT Missing files");
			}
		}
		else if (PeerMessageTypeRequest == [peerMessage[PeerMessageMessageType] integerValue]) {
			CDELog(CDELoggingLevelVerbose, @"PeerManager didReceiveData: PeerMessageTypeRequest");
			NSURL *urlOfTempFile = [self contentDataURLForFilesPaths:remoteFiles];

			if (urlOfTempFile) {
				NSString *resourceName = [urlOfTempFile lastPathComponent];
				CDELog(CDELoggingLevelVerbose, @"PeerManager sendResourceAtURL: %@", resourceName);

                NSData *ressource = [NSData dataWithContentsOfURL:urlOfTempFile];
#ifdef DEBUG
                CDELog(CDELoggingLevelVerbose, @"%@", [ressource md5]);
#endif
				[peerSession sendResourceAtURL:urlOfTempFile withName:resourceName toPeer:peerID withCompletionHandler: ^(NSError *error) {
				    CDELog(CDELoggingLevelVerbose, @"Finish sending file data %@", resourceName);

				    if (error) {
				        CDELog(CDELoggingLevelError, @"ERROR Finish sending : %@", error);
					}

                    NSError *removeFileError;
                    BOOL success = [[NSFileManager defaultManager] removeItemAtURL:urlOfTempFile error:&removeFileError];
                    
                    if (removeFileError || NO == success) {
                        CDELog(CDELoggingLevelError, @"PeerManager ERROR Deleting temp zip : %@", removeFileError);
                    }

                    success = [[NSFileManager defaultManager] removeItemAtURL:[urlOfTempFile URLByDeletingPathExtension] error:&removeFileError];

                    if (removeFileError || NO == success) {
                        CDELog(CDELoggingLevelError, @"PeerManager ERROR Deleting temp directory : %@", removeFileError);
                    }
				}];
			}
		}
	}
}

- (void)session:(MCSession *)session didReceiveStream:(NSInputStream *)stream withName:(NSString *)streamName fromPeer:(MCPeerID *)peerID
{
	if (session == peerSession) {
		CDELog(CDELoggingLevelVerbose, @"MPC didReceiveStream");
	}
}

- (void)session:(MCSession *)session didStartReceivingResourceWithName:(NSString *)resourceName fromPeer:(MCPeerID *)peerID withProgress:(NSProgress *)progress
{
	if (session == peerSession) {
		CDELog(CDELoggingLevelVerbose, @"MPC didStartReceivingResourceWithName : %@", resourceName);
	}
}

- (void)session:(MCSession *)session didFinishReceivingResourceWithName:(NSString *)resourceName fromPeer:(MCPeerID *)peerID atURL:(NSURL *)localURL withError:(NSError *)error
{
	if (session == peerSession) {
		CDELog(CDELoggingLevelVerbose, @"MPC didFinishReceivingResourceWithName : %@", resourceName);

		if (error) {
			CDELog(CDELoggingLevelVerbose, @"ERROR didFinishReceivingResourceWithName ERROR : %@", error);
		}
		else {
#ifdef DEBUG
            NSData *ressource = [NSData dataWithContentsOfURL:localURL];
            CDELog(CDELoggingLevelVerbose, @"%@", [ressource md5]);
#endif
            if (nil == localURL || 0 == localURL.path.length) {
                CDELog(CDELoggingLevelError, @"NO URL TO IMPORT FILES");
                return;
            }

            NSError *renamingError;
            NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
            NSString *basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
            basePath = [basePath stringByAppendingPathComponent:@"zips"];
            [[NSFileManager defaultManager] createDirectoryAtPath:basePath
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:&renamingError];
            if (renamingError) {
                CDELog(CDELoggingLevelError, @"ERROR RENAMING RESOURCE : %@", renamingError);
                return;
            }

            NSURL *newContentURL = [NSURL fileURLWithPath:basePath];
            newContentURL = [newContentURL URLByAppendingPathComponent:resourceName];
            [fileManager moveItemAtURL:localURL toURL:newContentURL error:&renamingError];
            CDELog(CDELoggingLevelVerbose, @"RENAMING RESOURCE TO ZIP EXTENSION");

            if (renamingError) {
                CDELog(CDELoggingLevelError, @"ERROR RENAMING RESOURCE : %@", renamingError);
                return;
            }

            NSURL *contentURLDirectory = [newContentURL URLByDeletingPathExtension];
            CDELog(CDELoggingLevelVerbose, @"IMPORTING ZIP FILE AT PATH: %@", newContentURL.path);

            BOOL sucessUnarchive = [SSZipArchive unzipFileAtPath:newContentURL.path toDestination:contentURLDirectory.path delegate:nil];

            if (NO == sucessUnarchive) {
                CDELog(CDELoggingLevelError, @"Decompression failed");
            }

            NSDirectoryEnumerator *enumerator = [fileManager enumeratorAtURL:contentURLDirectory
                                                  includingPropertiesForKeys:@[NSURLNameKey, NSURLIsDirectoryKey]
                                                                     options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                errorHandler: ^BOOL (NSURL *url, NSError *error) {
                                                                    CDELog(CDELoggingLevelError, @"[Error] %@ (%@)", error, url);

                                                                    return YES;
                                                                }];

            NSMutableSet *mutableFilePaths = [NSMutableSet set];

            BOOL hasImportedData = NO;

            for (NSURL *fileURL in enumerator) {
                NSString *filename;
                [fileURL getResourceValue:&filename forKey:NSURLNameKey error:nil];

                NSNumber *isDirectory;
                [fileURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];

                if (NO == [isDirectory boolValue]) {
                    [mutableFilePaths addObject:[self pathForFileURL:fileURL relativeToURL:contentURLDirectory]];
                }
            }

            for (NSString *filePath in mutableFilePaths) {
                NSURL *localFileURL = [[[NSURL fileURLWithPath:localRootDirectoryPath] URLByResolvingSymlinksInPath] URLByAppendingPathComponent:filePath];
                NSURL *temporaryFileURL = [[contentURLDirectory URLByResolvingSymlinksInPath] URLByAppendingPathComponent:filePath];

                if (NO == [fileManager fileExistsAtPath:localFileURL.path]) {
                    NSError *copyFileError;
                    BOOL success = [fileManager moveItemAtURL:temporaryFileURL toURL:localFileURL error:&copyFileError];
                    hasImportedData = YES;
                    
                    if (copyFileError || NO == success) {
                        CDELog(CDELoggingLevelError, @"DirectoryManager ERROR B : %@", copyFileError);
                    }
                }
            }
            
            NSError *removeDirectoryError;
            BOOL successRemoveDirectory = [fileManager removeItemAtURL:contentURLDirectory error:&removeDirectoryError];
            
            if (removeDirectoryError || NO == successRemoveDirectory) {
                CDELog(CDELoggingLevelError, @"DirectoryManager ERROR Deleting temp directory B : %@", removeDirectoryError);
            }
            
            if (hasImportedData) {
                [[NSNotificationCenter defaultCenter] postNotificationName:nMultipeerCloudFileSystemDidImportFiles object:nil];
            }
		}
	}
}

- (void)session:(MCSession *)session didReceiveCertificate:(NSArray *)certificate fromPeer:(MCPeerID *)peerID certificateHandler:(void (^)(BOOL accept))certificateHandler
{
	if (session == peerSession) {
		CDELog(CDELoggingLevelVerbose, @"MPC didReceiveCertificate");
		certificateHandler(YES);
	}
}

@end
