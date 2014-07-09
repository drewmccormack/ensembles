//
//  CDELocalFileSystem.m
//  Ensembles
//
//  Created by Drew McCormack on 02/09/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import "CDEMultipeerCloudFileSystem.h"
#import "SSZipArchive.h"

typedef NS_ENUM (NSInteger, CDEMultipeerMessageType) {
	CDEMultipeerMessageTypeFileRetrievalRequest = 1,
    CDEMultipeerMessageTypeFileRetrievalResponse = 2
};

NSString * const CDEMultipeerCloudFileSystemDidImportFilesNotification = @"CDEMultipeerCloudFileSystemDidImportFilesNotification";

NSString * const CDEMultipeerFilesPathsKey = @"filesPaths";
NSString * const CDEMultipeerMessageTypeKey = @"messageType";


@implementation CDEMultipeerCloudFileSystem {
	NSFileManager *fileManager;
}

@synthesize rootDirectory = rootDirectory;
@synthesize multipeerConnection = multipeerConnection;

- (instancetype)initWithRootDirectory:(NSString *)rootDir multipeerConnection:(id <CDEMultipeerConnection>)newConnection
{
	self = [super init];
    if (self) {
        multipeerConnection = newConnection;
		fileManager = [[NSFileManager alloc] init];
        rootDirectory = [rootDir copy];
        [fileManager createDirectoryAtPath:rootDirectory withIntermediateDirectories:YES attributes:nil error:NULL];
	}
	return self;
}

- (BOOL)isConnected
{
    return YES;
}

- (void)connect:(CDECompletionBlock)completion
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (completion) completion(nil);
    });
}

- (id <NSObject, NSCoding, NSCopying>)identityToken
{
    return @"User";
}

- (void)fileExistsAtPath:(NSString *)path completion:(void(^)(BOOL exists, BOOL isDirectory, NSError *error))completion
{
    BOOL exists, isDir;
    exists = [fileManager fileExistsAtPath:[self fullPathForRelativePath:path] isDirectory:&isDir];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (completion) completion(exists, isDir, nil);
    });
}

- (void)contentsOfDirectoryAtPath:(NSString *)path completion:(void(^)(NSArray *contents, NSError *error))completion
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

    dispatch_async(dispatch_get_main_queue(), ^{
        if (completion) completion(contents, nil);
    });
}

- (void)createDirectoryAtPath:(NSString *)path completion:(CDECompletionBlock)completion
{
    NSError *error = nil;
    [fileManager createDirectoryAtPath:[self fullPathForRelativePath:path] withIntermediateDirectories:NO attributes:nil error:&error];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (completion) completion(error);
    });
}

- (void)removeItemAtPath:(NSString *)fromPath completion:(CDECompletionBlock)completion
{
    NSError *error = nil;
    [fileManager removeItemAtPath:[self fullPathForRelativePath:fromPath] error:&error];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (completion) completion(error);
    });
}

- (void)uploadLocalFile:(NSString *)fromPath toPath:(NSString *)toPath completion:(CDECompletionBlock)completion
{
    NSError *error = nil;
    [fileManager copyItemAtPath:fromPath toPath:[self fullPathForRelativePath:toPath] error:&error];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (completion) completion(error);
    });
}

- (void)downloadFromPath:(NSString *)fromPath toLocalFile:(NSString *)toPath completion:(CDECompletionBlock)completion
{
    NSError *error = nil;
    [fileManager copyItemAtPath:[self fullPathForRelativePath:fromPath] toPath:toPath error:&error];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (completion) completion(error);
    });
}

#pragma mark - Remove Files

- (void)removeAllFiles
{
    [fileManager removeItemAtPath:self.rootDirectory error:NULL];
}

#pragma mark - Retrieving Files

- (void)retrieveFilesFromPeersWithIDs:(NSArray *)peerIDs
{
    NSSet *localFilesPaths = [self localFilePaths];
    NSDictionary *peerMessage = @{
        CDEMultipeerMessageTypeKey : @(CDEMultipeerMessageTypeFileRetrievalRequest),
        CDEMultipeerFilesPathsKey : localFilesPaths
    };
    NSData *peerMessageData = [NSKeyedArchiver archivedDataWithRootObject:peerMessage];
    
    for (id peerID in peerIDs) {
        BOOL success = [self.multipeerConnection sendData:peerMessageData toPeerWithID:peerID];
        if (!success) CDELog(CDELoggingLevelError, @"Could not send data to peer: %@", peerID);
    }
}

- (NSString *)fullPathForRelativePath:(NSString *)path
{
	return [rootDirectory stringByAppendingPathComponent:path];
}

#pragma mark - Responses

- (void)receiveData:(NSData *)data fromPeerWithID:(id<NSObject,NSCopying,NSCoding>)peerID
{
    CDELog(CDELoggingLevelVerbose, @"Received data from peer: %@", peerID);
    
    NSDictionary *peerMessage = nil;
    @try {
        peerMessage = [NSKeyedUnarchiver unarchiveObjectWithData:data];
    }
    @catch (NSException *exception) {
        CDELog(CDELoggingLevelError, @"Could not unarchive message from peer");
        return;
    }

    NSInteger messageType = [peerMessage[CDEMultipeerMessageTypeKey] integerValue];
    if (CDEMultipeerMessageTypeFileRetrievalRequest == messageType) {
        NSSet *remoteFiles = peerMessage[CDEMultipeerFilesPathsKey];
        [self handleFileRetrievalRequestFromPeerWithID:peerID withRemotePaths:remoteFiles];
    }
}

- (void)handleFileRetrievalRequestFromPeerWithID:(id <NSObject, NSCopying, NSCoding>)peerID withRemotePaths:(NSSet *)remotePaths
{
    CDELog(CDELoggingLevelVerbose, @"Handling status message");
    
    NSSet *localFiles = [self localFilePaths];
    NSMutableSet *filesMissingRemotely = [localFiles mutableCopy];
    [filesMissingRemotely minusSet:remotePaths];
    CDELog(CDELoggingLevelVerbose, @"Sending files to peer: %@", filesMissingRemotely);
    
    if (filesMissingRemotely.count == 0) return;
    
    NSURL *tempURL = [self makeArchiveForPaths:filesMissingRemotely];
    if (!tempURL) {
        CDELog(CDELoggingLevelError, @"Could not create archive of files");
        return;
    }
    
    NSString *resourceName = [tempURL lastPathComponent];
    CDELog(CDELoggingLevelVerbose, @"PeerManager sendResourceAtURL: %@", resourceName);
    
    [multipeerConnection sendAndDiscardFileAtURL:tempURL toPeerWithID:peerID];
}

- (void)receiveResourceAtURL:(NSURL *)archiveURL fromPeerWithID:(id<NSObject,NSCopying,NSCoding>)peerID
{
    NSURL *contentURLDirectory = [[archiveURL URLByDeletingLastPathComponent] URLByAppendingPathComponent:archiveURL.pathExtension];
    CDELog(CDELoggingLevelVerbose, @"Importing zip file: %@", archiveURL.path);
    
    [SSZipArchive unzipFileAtPath:archiveURL.path toDestination:contentURLDirectory.path delegate:nil];
    
    NSDirectoryEnumerator *enumerator = [fileManager enumeratorAtURL:contentURLDirectory includingPropertiesForKeys:@[NSURLNameKey, NSURLIsDirectoryKey] options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:NULL];
    NSURL *rootURL = [[NSURL fileURLWithPath:rootDirectory] URLByResolvingSymlinksInPath];
    NSURL *contentURL = [contentURLDirectory URLByResolvingSymlinksInPath];
    BOOL success = NO;
    NSUInteger count = 0;
    for (NSURL *fileURL in enumerator) {
        NSString *filename;
        [fileURL getResourceValue:&filename forKey:NSURLNameKey error:nil];

        NSNumber *isDirectory;
        [fileURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];

        if (!isDirectory.boolValue) {
            NSString *filePath = [self pathForFileURL:fileURL relativeToURL:contentURLDirectory];
            NSURL *localFileURL = [rootURL URLByAppendingPathComponent:filePath];
            NSURL *temporaryFileURL = [contentURL URLByAppendingPathComponent:filePath];
            NSError *error = nil;
            success = [fileManager moveItemAtURL:temporaryFileURL toURL:localFileURL error:&error];
            if (!success) {
                CDELog(CDELoggingLevelError, @"Could not move file from expanded zip archive: %@", localFileURL);
            }
            else {
                count++;
            }
        }
    }
    
    [fileManager removeItemAtURL:contentURLDirectory error:NULL];
    [fileManager removeItemAtURL:archiveURL error:NULL];
    
    if (count > 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:CDEMultipeerCloudFileSystemDidImportFilesNotification object:self];
        });
    }
}

#pragma mark - Directory methods

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
    NSDirectoryEnumerator *enumerator = [fileManager enumeratorAtURL:[NSURL fileURLWithPath:rootDirectory] includingPropertiesForKeys:@[NSURLNameKey, NSURLIsDirectoryKey] options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:^BOOL (NSURL *url, NSError *error) {
        CDELog(CDELoggingLevelError, @"[Error] %@ (%@)", error, url);
        return YES;
    }];
    
    NSMutableSet *mutableFilePaths = [NSMutableSet set];
    for (NSURL *fileURL in enumerator) {
        NSString *filename;
        [fileURL getResourceValue:&filename forKey:NSURLNameKey error:nil];
        
        NSNumber *isDirectory;
        [fileURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
        
        if (![isDirectory boolValue]) {
            [mutableFilePaths addObject:[self pathForFileURL:fileURL relativeToURL:[NSURL fileURLWithPath:rootDirectory]]];
        }
    }
    
    return [mutableFilePaths copy];
}

- (NSURL *)makeArchiveForPaths:(NSSet *)filesPaths
{
    NSURL *rootTemporaryURL = [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
    NSURL *contentDirectoryTemporaryURL = [rootTemporaryURL URLByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString] isDirectory:YES];
    
    for (NSString *path in filesPaths) {
        NSString *localPath = [rootDirectory stringByAppendingPathComponent:path];
        if ([fileManager fileExistsAtPath:localPath]) {
            NSString *tempPath = [contentDirectoryTemporaryURL.path stringByAppendingPathComponent:path];
            [fileManager createDirectoryAtPath:[tempPath stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:NULL];
            NSError *error = nil;
            BOOL success = [fileManager copyItemAtPath:localPath toPath:tempPath error:&error];
            if (!success) {
                CDELog(CDELoggingLevelError, @"Failed to copy file: %@", error);
                return nil;
            }
        }
    }
    
    NSURL *zipFileURL = [contentDirectoryTemporaryURL URLByAppendingPathExtension:@"zip"];
    BOOL successArchive = [SSZipArchive createZipFileAtPath:zipFileURL.path withContentsOfDirectory:contentDirectoryTemporaryURL.path];
    if (!successArchive) CDELog(CDELoggingLevelError, @"Compression failed");
    
    return successArchive ? zipFileURL : nil;
}

@end



