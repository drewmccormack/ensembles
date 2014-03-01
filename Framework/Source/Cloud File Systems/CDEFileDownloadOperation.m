//
//  CDEFileDownloadOperation.m
//  Ensembles iOS
//
//  Created by Drew McCormack on 01/03/14.
//  Copyright (c) 2014 The Mental Faculty B.V. All rights reserved.
//

#import "CDEFileDownloadOperation.h"

@interface CDEFileDownloadOperation () <NSURLConnectionDelegate, NSURLConnectionDataDelegate>
@end

@implementation CDEFileDownloadOperation {
    BOOL isFinished, isExecuting;
    NSFileManager *fileManager;
    NSFileHandle *fileHandle;
    NSURLConnection *connection;
}

@synthesize url = url;
@synthesize localPath = localPath;
@synthesize completion = completion;

- (instancetype)initWithURL:(NSURL *)newURL localPath:(NSString *)newPath
{
    NSParameterAssert(newURL != nil);
    NSParameterAssert(newPath != nil);
    self = [super init];
    if (self) {
        url = [newURL copy];
        localPath = [newPath copy];
        fileManager = [[NSFileManager alloc] init];
    }
    return self;
}

- (void)beginAsynchronousTask
{
    [fileManager removeItemAtPath:localPath error:NULL];
    fileHandle = [NSFileHandle fileHandleForWritingAtPath:localPath];
    
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    connection = [[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:YES];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    if (completion) completion(error);
    [self endAsynchronousTask];
}

- (void)cancel
{
    [super cancel];
    
    [connection cancel];
    [fileHandle closeFile];
    [fileManager removeItemAtPath:localPath error:NULL];

    NSError *error = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeCancelled userInfo:nil];
    if (completion) completion(error);

    [self endAsynchronousTask];
}

- (void)connection:(NSURLConnection *)aConnection didReceiveData:(NSData *)data
{
    [fileHandle writeData:data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    [fileHandle closeFile];
    if (completion) completion(nil);
    [self endAsynchronousTask];
}

@end
