//
//  Multipeer.m
//  Idiomatic
//
//  Created by Florion on 20/06/2014.
//  Copyright (c) 2014 The Mental Faculty B.V. All rights reserved.
//

#import "IDMMultipeerManager.h"
#import <Ensembles/Ensembles.h>

NSString *const IDMSyncPeerService = @"idiomatic";
NSString *const kDiscoveryInfoUniqueIdentifer = @"DiscoveryInfoUniqueIdentifer";

@interface IDMMultipeerManager () <MCNearbyServiceBrowserDelegate, MCNearbyServiceAdvertiserDelegate, MCSessionDelegate>
{
    NSString *uniqueIdentifier;
    MCSession *peerSession;
    MCNearbyServiceBrowser *peerBrowser;
    MCNearbyServiceAdvertiser *peerAdvertizer;
}
@end

@implementation IDMMultipeerManager

- (instancetype)init
{
	self = [super init];

    if (self) {
        uniqueIdentifier = [[NSProcessInfo processInfo] globallyUniqueString];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(stopAndStart) name:UIApplicationDidBecomeActiveNotification object:nil];
	}
    
	return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Start and Stop Connecting

- (void)start
{
    if (peerSession && peerAdvertizer && peerBrowser) return;
    
    [self stop];
    
	MCPeerID *peerID = [[MCPeerID alloc] initWithDisplayName:[[UIDevice currentDevice] name]];
	peerSession = [[MCSession alloc] initWithPeer:peerID securityIdentity:nil encryptionPreference:MCEncryptionRequired];
	peerSession.delegate = self;

    peerAdvertizer = [[MCNearbyServiceAdvertiser alloc] initWithPeer:peerID discoveryInfo:@{kDiscoveryInfoUniqueIdentifer : uniqueIdentifier} serviceType:IDMSyncPeerService];
    peerAdvertizer.delegate = self;
    [peerAdvertizer startAdvertisingPeer];

    peerBrowser = [[MCNearbyServiceBrowser alloc] initWithPeer:peerID serviceType:IDMSyncPeerService];
    peerBrowser.delegate = self;
    [peerBrowser startBrowsingForPeers];
}

- (void)stop
{
    peerSession.delegate = nil;
    [peerSession disconnect];
	peerSession = nil;

    peerBrowser.delegate = nil;
	[peerBrowser stopBrowsingForPeers];
	peerBrowser = nil;

    peerAdvertizer.delegate = nil;
	[peerAdvertizer stopAdvertisingPeer];
	peerAdvertizer = nil;
}

- (void)stopAndStart
{
    [self stop];
    [self start];
}

#pragma mark - Syncing Files

- (void)syncFilesWithAllPeers
{
    if (peerSession.connectedPeers.count == 0 && (!peerBrowser || !peerAdvertizer) ) {
        [self start];
        return;
    }
    
    NSMutableArray *peers = [peerSession.connectedPeers mutableCopy];
    [peers removeObject:peerSession.myPeerID];
    [self.multipeerCloudFileSystem retrieveFilesFromPeersWithIDs:peers];
}

- (BOOL)sendAndDiscardFileAtURL:(NSURL *)url toPeerWithID:(id<NSObject,NSCopying,NSCoding>)peerID
{
    NSProgress *progress = [peerSession sendResourceAtURL:url withName:[url lastPathComponent] toPeer:(id)peerID withCompletionHandler:^(NSError *error) {
        if (error) CDELog(CDELoggingLevelError, @"Failed to send resource to peerID: %@", peerID);
        [[NSFileManager defaultManager] removeItemAtURL:url error:NULL];
    }];
    return progress != nil;
}

- (BOOL)sendData:(NSData *)data toPeerWithID:(id<NSObject,NSCopying,NSCoding>)peerID
{
    NSError *error = nil;
    BOOL success = [peerSession sendData:data toPeers:@[peerID] withMode:MCSessionSendDataReliable error:&error];
    if (!success) CDELog(CDELoggingLevelError, @"Failed to send data to peer: %@", error);
    return success;
}

- (void)session:(MCSession *)session didReceiveData:(NSData *)data fromPeer:(MCPeerID *)peerID
{
    [self.multipeerCloudFileSystem receiveData:data fromPeerWithID:peerID];
}

- (void)session:(MCSession *)session didFinishReceivingResourceWithName:(NSString *)resourceName fromPeer:(MCPeerID *)peerID atURL:(NSURL *)localURL withError:(NSError *)error
{
    if (localURL == nil) return;
    [self.multipeerCloudFileSystem receiveResourceAtURL:localURL fromPeerWithID:peerID];
}

- (void)session:(MCSession *)session didStartReceivingResourceWithName:(NSString *)resourceName fromPeer:(MCPeerID *)peerID withProgress:(NSProgress *)progress
{
}

- (void)session:(MCSession *)session didReceiveStream:(NSInputStream *)stream withName:(NSString *)streamName fromPeer:(MCPeerID *)peerID
{
}

- (void)session:(MCSession *)session peer:(MCPeerID *)peerID didChangeState:(MCSessionState)state
{
    if (state == MCSessionStateNotConnected) {
        [peerBrowser startBrowsingForPeers];
        [peerAdvertizer startAdvertisingPeer];
    }
    else if (state == MCSessionStateConnected) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self syncFilesWithAllPeers];
        });
    }
}

#pragma mark -  MCNearbyServiceBrowserDelegate

- (void)browser:(MCNearbyServiceBrowser *)browser foundPeer:(MCPeerID *)peerID withDiscoveryInfo:(NSDictionary *)info
{
    if ([peerID isEqual:peerSession.myPeerID]) return;
    if ([peerSession.connectedPeers containsObject:peerID]) return;
    
    NSString *otherPeerUniqueIdentifier = info[kDiscoveryInfoUniqueIdentifer];
    BOOL shouldAccept = ([otherPeerUniqueIdentifier compare:uniqueIdentifier] != NSOrderedDescending);
    if (!shouldAccept) return;
    
    NSData *context = [uniqueIdentifier dataUsingEncoding:NSUTF8StringEncoding];
    [browser invitePeer:peerID toSession:peerSession withContext:context timeout:30.0];
    CDELog(CDELoggingLevelVerbose, @"Inviting %@", peerID.displayName);
}

- (void)browser:(MCNearbyServiceBrowser *)browser lostPeer:(MCPeerID *)peerID
{
}

- (void)browser:(MCNearbyServiceBrowser *)browser didNotStartBrowsingForPeers:(NSError *)error
{
    peerBrowser = nil;
}

#pragma mark - MCNearbyServiceAdvertiserDelegate

- (void)advertiser:(MCNearbyServiceAdvertiser *)advertiser didReceiveInvitationFromPeer:(MCPeerID *)peerID withContext:(NSData *)context invitationHandler:(void (^)(BOOL accept, MCSession *session))invitationHandler
{
    NSString *otherPeerUniqueIdentifier = [NSString stringWithUTF8String:context.bytes];
    BOOL shouldInvite = ([otherPeerUniqueIdentifier compare:uniqueIdentifier] == NSOrderedDescending);
    if (![peerSession.connectedPeers containsObject:peerID] && shouldInvite) {
        CDELog(CDELoggingLevelVerbose, @"Accepting invite from peer %@", peerID.displayName);
        invitationHandler(YES, peerSession);
    }
    else {
        CDELog(CDELoggingLevelVerbose, @"Rejecting invite from %@, because it is already in session", peerID.displayName);
        invitationHandler(NO, peerSession);
    }
}

- (void)advertiser:(MCNearbyServiceAdvertiser *)advertiser didNotStartAdvertisingPeer:(NSError *)error
{
    peerAdvertizer = nil;
}

@end
