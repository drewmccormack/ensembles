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
    NSFileManager *fileManager;
    NSFileHandle *fileHandle;
    NSURLConnection *connection;
    NSMutableURLRequest *mutableRequest;
    NSError *responseError;
}

@synthesize localPath = localPath;
@synthesize completion = completion;

- (instancetype)initWithURLRequest:(NSURLRequest *)newURLRequest localPath:(NSString *)newPath
{
    NSParameterAssert(newURLRequest != nil);
    NSParameterAssert(newPath != nil);
    self = [super init];
    if (self) {
        mutableRequest = [newURLRequest mutableCopy];
        localPath = [newPath copy];
        fileManager = [[NSFileManager alloc] init];
        responseError = nil;
    }
    return self;
}

- (NSURLRequest *)request
{
    return [mutableRequest copy];
}

- (void)beginAsynchronousTask
{
    [fileManager removeItemAtPath:localPath error:NULL];
    [fileManager createFileAtPath:localPath contents:nil attributes:nil];
    fileHandle = [NSFileHandle fileHandleForWritingAtPath:localPath];
    
    if (!fileHandle) {
        NSDictionary *info = @{NSLocalizedDescriptionKey : @"Could not create local file for downloading"};
        NSError *error = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeFileAccessFailed userInfo:info];
        if (completion) completion(error);
        [self endAsynchronousTask];
        return;
    }
    
    connection = [[NSURLConnection alloc] initWithRequest:mutableRequest delegate:self startImmediately:YES];
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

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    NSHTTPURLResponse *httpResponse = (id)response;
    BOOL success = (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300);
    if (!success) {
        CDELog(CDELoggingLevelError, @"Error uploading file. Response: %@", response);
        NSDictionary *info = @{NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Status code: %ld", (long)httpResponse.statusCode]};
        responseError = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeServerError userInfo:info];
    }
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    [fileHandle closeFile];
    if (completion) completion(responseError);
    [self endAsynchronousTask];
}

@end
