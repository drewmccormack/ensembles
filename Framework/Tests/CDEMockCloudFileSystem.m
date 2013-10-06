//
//  CDEMockCloudFileSystem.m
//  Ensembles
//
//  Created by Drew McCormack on 11/09/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import "CDEMockCloudFileSystem.h"
#import "CDECloudFile.h"

@implementation CDEMockItem
@end

@implementation CDEMockCloudFileSystem

- (id)init
{
    if ((self = [super init])) {
        self.itemsByRemotePath = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)dispatchCompletion:(CDECompletionBlock)completion
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (completion) completion(nil);
    });
}

- (BOOL)isConnected
{
    return YES;
}

- (void)connect:(CDECompletionBlock)completion
{
    [self dispatchCompletion:completion];
}

- (id <NSObject, NSCoding, NSCopying>)identityToken
{
    return @"identity";
}

- (void)fileExistsAtPath:(NSString *)path completion:(void(^)(BOOL exists, BOOL isDirectory, NSError *error))block
{
    CDEMockItem *item = self.itemsByRemotePath[path];
    BOOL result = item != nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        block(result, item.isDirectory, nil);
    });
}

- (void)createDirectoryAtPath:(NSString *)path completion:(CDECompletionBlock)block
{
    CDEMockItem *item = [[CDEMockItem alloc] init];
    item.isDirectory = YES;
    item.data = nil;
    item.path = path;
    self.itemsByRemotePath[path] = item;
    [self dispatchCompletion:block];
}

- (void)contentsOfDirectoryAtPath:(NSString *)path completion:(void(^)(NSArray *contents, NSError *error))block
{
    NSMutableArray *files = [NSMutableArray new];
    for (CDEMockItem *item in self.itemsByRemotePath.objectEnumerator) {
        if ([item.path hasPrefix:path] && path.pathComponents.count < item.path.pathComponents.count) {
            CDECloudFile *file = [CDECloudFile new];
            file.name = item.path.lastPathComponent;
            file.path = item.path;
            [files addObject:file];
        }
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        block(files, nil);
    });
}

- (void)removeItemAtPath:(NSString *)fromPath completion:(CDECompletionBlock)block
{
    self.itemsByRemotePath[fromPath] = nil;
    [self dispatchCompletion:block];
}

- (void)uploadLocalFile:(NSString *)fromPath toPath:(NSString *)toPath completion:(CDECompletionBlock)block
{
    CDEMockItem *item = [CDEMockItem new];
    item.path = toPath;
    item.data = [NSData dataWithContentsOfFile:fromPath];
    item.isDirectory = NO;
    self.itemsByRemotePath[toPath] = item;
    [self dispatchCompletion:block];
}

- (void)downloadFromPath:(NSString *)fromPath toLocalFile:(NSString *)toPath completion:(CDECompletionBlock)block
{
    CDEMockItem *item = self.itemsByRemotePath[fromPath];
    [item.data writeToFile:toPath atomically:YES];
    [self dispatchCompletion:block];
}

@end
