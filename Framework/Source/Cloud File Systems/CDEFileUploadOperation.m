//
//  CDEFileUploadOperation.m
//  Ensembles Mac
//
//  Created by Drew McCormack on 01/03/14.
//  Copyright (c) 2014 Drew McCormack. All rights reserved.
//

#import "CDEFileUploadOperation.h"

@interface CDEFileUploadOperation () <NSURLConnectionDelegate, NSURLConnectionDataDelegate>
@end

@implementation CDEFileUploadOperation {
    NSURLConnection *connection;
    NSError *responseError;
}

@synthesize url = url;
@synthesize localPath = localPath;
@synthesize request = request;
@synthesize completion = completion;

- (instancetype)initWithURL:(NSURL *)newURL localPath:(NSString *)newPath
{
    NSParameterAssert(newURL != nil);
    NSParameterAssert(newPath != nil);
    self = [super init];
    if (self) {
        url = [newURL copy];
        localPath = [newPath copy];
        responseError = nil;
        
        request = [NSMutableURLRequest requestWithURL:url
            cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData
            timeoutInterval:300.0];
        request.HTTPMethod = @"PUT";
        request.HTTPBodyStream = [NSInputStream inputStreamWithFileAtPath:localPath];
        
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:localPath error:NULL];
        unsigned long long result = attributes.fileSize;
        NSString *lengthAsString = [NSString stringWithFormat:@"%llu", result];
        [request setValue:lengthAsString forHTTPHeaderField:@"Content-Length"];
    }
    return self;
}

- (void)beginAsynchronousTask
{
    connection = [[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:YES];
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

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    if (!responseError) return;
    NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    CDELog(CDELoggingLevelError, @"Response XML: %@", string);
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
    
    NSError *error = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeCancelled userInfo:nil];
    if (completion) completion(error);
    
    [self endAsynchronousTask];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    if (completion) completion(responseError);
    [self endAsynchronousTask];
}

@end