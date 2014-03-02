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
        
        request = [NSMutableURLRequest requestWithURL:url];
        request.HTTPMethod = @"PUT";
        request.HTTPBodyStream = [NSInputStream inputStreamWithFileAtPath:localPath];
        
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:localPath error:NULL];
        unsigned long long result = attributes.fileSize;
        NSString *lengthAsString = [NSString stringWithFormat:@"%llu", result];
        [request addValue:lengthAsString forHTTPHeaderField:@"Content-Length"];
    }
    return self;
}

- (void)beginAsynchronousTask
{
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
    
    NSError *error = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeCancelled userInfo:nil];
    if (completion) completion(error);
    
    [self endAsynchronousTask];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    if (completion) completion(nil);
    [self endAsynchronousTask];
}

@end