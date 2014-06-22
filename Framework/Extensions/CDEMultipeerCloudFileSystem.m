//
//  CDELocalFileSystem.m
//  Ensembles
//
//  Created by Drew McCormack on 02/09/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import <MultipeerConnectivity/MultipeerConnectivity.h>
#import "CDEMultipeerCloudFileSystem.h"
#import "SSZipArchive.h"

// PEER MESSAGE
typedef NS_ENUM (NSInteger, PeerMessageType) {
	PeerMessageTypeStatus = 1,
	PeerMessageTypeRequest = 2
};

NSString *const nMultipeerCloudFileSystemDidImportFiles = @"MultipeerCloudFileSystemDidImportFiles";
NSString *const CloudFilesDirectoryName = @"cloudfiles";
NSString *const PeerMessageFilesPaths = @"filesPaths";
NSString *const PeerMessageMessageType = @"messageType";

@interface CDEMultipeerCloudFileSystem ()
{
	__strong NSFileManager *fileManager;
    __strong NSString *localRootDirectoryPath;
}
@end

@implementation CDEMultipeerCloudFileSystem

- (instancetype)init
{
	self = [super init];

    if (self) {
		fileManager = [[NSFileManager alloc] init];

        NSURL *directoryURL = [fileManager URLForDirectory:NSDocumentDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:NULL];
        directoryURL = [directoryURL URLByAppendingPathComponent:CloudFilesDirectoryName isDirectory:YES];
		localRootDirectoryPath = directoryURL.path;

        [fileManager createDirectoryAtPath:directoryURL.path withIntermediateDirectories:YES attributes:nil error:NULL];
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

#pragma mark - Public

- (BOOL)synchronizeFilesViaMultipeerSession:(MCSession *)session withSpecificPeers:(NSArray *)specificPeers
{
    BOOL success = NO;
    NSArray *peersToSendTo = nil == specificPeers ? session.connectedPeers : specificPeers;

	if (peersToSendTo.count == 0) {
		CDELog(CDELoggingLevelVerbose, @"MPC sendStatusMessageToPeers : NO peer to send data to");
	}
    else {
        NSSet *localFilesPaths = [self localFilePaths];
        NSDictionary *peerMessage = @{ PeerMessageMessageType : @(PeerMessageTypeStatus), PeerMessageFilesPaths : localFilesPaths};

        if (localFilesPaths.count > 0 && peersToSendTo) {
            NSData *peerMessageData = [NSKeyedArchiver archivedDataWithRootObject:peerMessage];
            NSError *error;
            success = [session sendData:peerMessageData toPeers:peersToSendTo withMode:MCSessionSendDataReliable error:&error];

            if (error || NO == success) {
                CDELog(CDELoggingLevelError, @"MultiPeer ERROR Sending HeaderData A : %@", error);
            }
        }
    }

	return success;
}

- (void)handleMessageData:(NSData *)data fromPeer:(MCPeerID *)peerID inSession:(MCSession *)session;
{
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
        NSURL *urlOfTempFile = [self archiveURLForFilesPaths:remoteFiles];

        if (urlOfTempFile) {
            NSString *resourceName = [urlOfTempFile lastPathComponent];
            CDELog(CDELoggingLevelVerbose, @"PeerManager sendResourceAtURL: %@", resourceName);

            [session sendResourceAtURL:urlOfTempFile withName:resourceName toPeer:peerID withCompletionHandler: ^(NSError *error) {
                if (error) {
                    CDELog(CDELoggingLevelError, @"ERROR Finish sending : %@", error);
                }
                else {
                    CDELog(CDELoggingLevelVerbose, @"Finish sending file data %@", resourceName);
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

- (void)importArchiveAtURL:(NSURL *)archiveURL archiveName:(NSString *)archiveName
{
    NSURL *contentURLDirectory = [[archiveURL URLByDeletingLastPathComponent] URLByAppendingPathComponent:archiveURL.pathExtension];
    CDELog(CDELoggingLevelVerbose, @"IMPORTING ZIP FILE AT PATH: %@", archiveURL.path);

    BOOL successUnarchive = [SSZipArchive unzipFileAtPath:archiveURL.path toDestination:contentURLDirectory.path delegate:nil];

    if (NO == successUnarchive) {
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
                CDELog(CDELoggingLevelError, @"ERROR MOVING FILES AFTER UNARCHIVING : %@", copyFileError);
            }
        }
    }

    NSError *removeDirectoryError;
    BOOL successRemoveDirectory = [fileManager removeItemAtURL:contentURLDirectory error:&removeDirectoryError];

    if (removeDirectoryError || NO == successRemoveDirectory) {
        CDELog(CDELoggingLevelError, @"ERROR Deleting temp directory B : %@", removeDirectoryError);
    }

    NSError *removeArchiveError;
    BOOL successRemoveArchiveError = [fileManager removeItemAtURL:archiveURL error:&removeArchiveError];

    if (removeArchiveError || NO == successRemoveArchiveError) {
        CDELog(CDELoggingLevelError, @"ERROR Deleting archive : %@", removeDirectoryError);
    }

    if (hasImportedData) {
        [[NSNotificationCenter defaultCenter] postNotificationName:nMultipeerCloudFileSystemDidImportFiles object:nil];
    }
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
    NSRange aRange = [localAbsolutePath rangeOfString:localBasePath options:NSAnchoredSearch];
    NSString *relativePath = [localAbsolutePath substringFromIndex:aRange.length];

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

- (NSURL *)archiveURLForFilesPaths:(NSSet *)filesPaths
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

@end
