//
//  CDELocalFileSystem.m
//  Ensembles
//
//  Created by Drew McCormack on 02/09/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import "CDELocalCloudFileSystem.h"
#import "CDECloudDirectory.h"
#import "CDECloudFile.h"

@implementation CDELocalCloudFileSystem {
    NSFileManager *fileManager;
}

@synthesize rootDirectory = rootDirectory;

- (instancetype)initWithRootDirectory:(NSString *)rootDir
{
    self = [super init];
    if (self) {
        rootDirectory = [rootDir copy];
        fileManager = [[NSFileManager alloc] init];
    }
    return self;
}

- (NSString *)fullPathForPath:(NSString *)path
{
    return [rootDirectory stringByAppendingPathComponent:path];
}

- (BOOL)isConnected
{
    return YES;
}

- (void)connect:(CDECompletionBlock)completion
{
    if (completion) dispatch_async(dispatch_get_main_queue(), ^{
        completion(nil);
    });
}

- (id <NSObject, NSCoding, NSCopying>)identityToken
{
    return NSUserName();
}

- (void)fileExistsAtPath:(NSString *)path completion:(void(^)(BOOL exists, BOOL isDirectory, NSError *error))block
{
    BOOL exists, isDir;
    exists = [fileManager fileExistsAtPath:[self fullPathForPath:path] isDirectory:&isDir];
    if (block) dispatch_async(dispatch_get_main_queue(), ^{
        block(exists, isDir, nil);
    });
}

- (void)contentsOfDirectoryAtPath:(NSString *)path completion:(void(^)(NSArray *contents, NSError *error))block
{
    NSMutableArray *contents = [[NSMutableArray alloc] init];
    NSDirectoryEnumerator *dirEnum = [fileManager enumeratorAtPath:[self fullPathForPath:path]];
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
    
    if (block) dispatch_async(dispatch_get_main_queue(), ^{
        block(contents, nil);
    });
}

- (void)createDirectoryAtPath:(NSString *)path completion:(CDECompletionBlock)block
{
    NSError *error = nil;
    [fileManager createDirectoryAtPath:[self fullPathForPath:path] withIntermediateDirectories:NO attributes:nil error:&error];
    if (block) dispatch_async(dispatch_get_main_queue(), ^{
       block(error);
    });
}

- (void)removeItemAtPath:(NSString *)fromPath completion:(CDECompletionBlock)block
{
    NSError *error = nil;
    [fileManager removeItemAtPath:[self fullPathForPath:fromPath] error:&error];
    if (block) dispatch_async(dispatch_get_main_queue(), ^{
        block(error);
    });
}

- (void)uploadLocalFile:(NSString *)fromPath toPath:(NSString *)toPath completion:(CDECompletionBlock)block
{
    NSError *error = nil;
    [fileManager copyItemAtPath:fromPath toPath:[self fullPathForPath:toPath] error:&error];
    if (block) dispatch_async(dispatch_get_main_queue(), ^{
        block(error);
    });
}

- (void)downloadFromPath:(NSString *)fromPath toLocalFile:(NSString *)toPath completion:(CDECompletionBlock)block
{
    NSError *error = nil;
    [fileManager copyItemAtPath:[self fullPathForPath:fromPath] toPath:toPath error:&error];
    if (block) dispatch_async(dispatch_get_main_queue(), ^{
        block(error);
    });
}

@end
