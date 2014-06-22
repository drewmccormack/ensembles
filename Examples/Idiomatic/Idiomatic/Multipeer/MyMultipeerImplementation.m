//
//  Multipeer.m
//  Idiomatic
//
//  Created by Florion on 20/06/2014.
//  Copyright (c) 2014 The Mental Faculty B.V. All rights reserved.
//

#import "MyMultipeerImplementation.h"
#import <Ensembles/Ensembles.h>
#import "CDEMultipeerCloudFileSystem.h"

NSString *const SyncPeerService = @"popina-sync";
NSString *const kDiscoveryInfoUniqueIdentifer = @"DiscoveryInfoUniqueIdentifer";

@interface MyMultipeerImplementation () <MCNearbyServiceBrowserDelegate, MCNearbyServiceAdvertiserDelegate, MCSessionDelegate>
{
    __strong NSString *uniqueIdentifier;
    __strong MCSession *peerSession;
    __strong MCNearbyServiceBrowser *peerBrowser;
    __strong MCNearbyServiceAdvertiser *peerAdvertizer;
    __strong NSMutableSet *connectedPeers;
}
@end

@implementation MyMultipeerImplementation

#pragma mark - MultiPeerManager methods

- (instancetype)init
{
	self = [super init];

    if (self) {
        connectedPeers = [NSMutableSet set];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(start) name:UIApplicationDidBecomeActiveNotification object:nil];
	}
    
	return self;
}

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

    peerAdvertizer = [[MCNearbyServiceAdvertiser alloc] initWithPeer:peerID discoveryInfo:@{kDiscoveryInfoUniqueIdentifer : uniqueIdentifier} serviceType:SyncPeerService];
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

	@synchronized(connectedPeers)
	{
		[connectedPeers removeAllObjects];
	}
}

#pragma mark - Public 

- (void)synchronizeWithAllPeers
{
    [self.multipeerCloudFileSystem synchronizeFilesViaMultipeerSession:peerSession withSpecificPeers:nil];
}

#pragma mark -  MCNearbyServiceBrowserDelegate

- (void)browser:(MCNearbyServiceBrowser *)browser foundPeer:(MCPeerID *)peerID withDiscoveryInfo:(NSDictionary *)info
{
    if (browser == peerBrowser) {
		CDELog(CDELoggingLevelVerbose, @"MPC foundPeer:%@ withDiscoveryInfo: %@", peerID, info);

        NSString *otherPeerUniqueIdentifier = info[kDiscoveryInfoUniqueIdentifer];
		BOOL shouldInvite = ([otherPeerUniqueIdentifier compare:uniqueIdentifier] != NSOrderedDescending);

        if (YES == shouldInvite && NO == [peerSession.myPeerID isEqual:peerID] && NO == [peerSession.myPeerID.displayName isEqualToString:peerID.displayName]) {
            NSData *context = [uniqueIdentifier dataUsingEncoding:NSUTF8StringEncoding];
            [browser invitePeer:peerID toSession:peerSession withContext:context timeout:30.0];
            CDELog(CDELoggingLevelVerbose, @"Inviting %@", peerID.displayName);
        }
	}
}

- (void)browser:(MCNearbyServiceBrowser *)browser lostPeer:(MCPeerID *)peerID
{
	if (browser == peerBrowser) {
        if (NO == [peerSession.myPeerID isEqual:peerID]) {
			CDELog(CDELoggingLevelVerbose, @"MPC lostPeer");
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
	@synchronized(connectedPeers)
	{
		[connectedPeers addObject:peer];
	}
}

- (void)removePeer:(MCPeerID *)peer
{
	@synchronized(connectedPeers)
	{
		[connectedPeers removeObject:peer];
	}
}

- (BOOL)hasPeer:(MCPeerID *)peer
{
	BOOL hasPeer = NO;

	@synchronized(connectedPeers)
	{
		hasPeer = [connectedPeers containsObject:peer];
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
                [self.multipeerCloudFileSystem synchronizeFilesViaMultipeerSession:session withSpecificPeers:@[peerID]];

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
			}
                break;

			case MCSessionStateNotConnected: {
				CDELog(CDELoggingLevelVerbose, @"MPC MCSessionStateNotConnected:%@", peerID);
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
        [self.multipeerCloudFileSystem handleMessageData:data fromPeer:peerID inSession:session];
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
    CDELog(CDELoggingLevelVerbose, @"MPC didFinishReceivingResourceWithName : %@", resourceName);

	if (session == peerSession) {
        if (error) {
            CDELog(CDELoggingLevelVerbose, @"ERROR didFinishReceivingResourceWithName ERROR : %@", error);
        }
        else {
            [self.multipeerCloudFileSystem importArchiveAtURL:localURL archiveName:resourceName];
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
