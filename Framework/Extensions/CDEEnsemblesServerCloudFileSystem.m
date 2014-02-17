//
//  CDEEnsemblesServerCloudFileSystem.m
//
//  Created by Drew McCormack on 2/17/14.
//  Copyright (c) 2014 The Mental Faculty B.V. All rights reserved.
//

#import "CDEEnsemblesServerCloudFileSystem.h"
#import "CDEDefines.h"
#import "CDECloudFile.h"
#import "CDECloudDirectory.h"

static const NSUInteger kCDENumberOfRetriesForFailedAttempt = 5;


@implementation CDEEnsemblesServerCloudFileSystem

- (instancetype)init
{
    self = [super init];
    if (self) {
    }
    return self;
}

#pragma mark Connecting

- (BOOL)isConnected
{
    return NO;
}

- (void)connect:(CDECompletionBlock)completion
{
    if (self.isConnected) {
        if (completion) completion(nil);
    }
    else if ([self.delegate respondsToSelector:@selector(linkSessionForEnsemblesServerCloudFileSystem:completion:)]) {
//        [self.delegate linkSessionForEnsemblesServerCloudFileSystem:self completion:completion];
    }
    else {
        NSError *error = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeConnectionError userInfo:nil];
        if (completion) completion(error);
    }
}

#pragma mark - User Identity

- (id <NSObject, NSCoding, NSCopying>)identityToken
{
    return nil;
}

#pragma mark - Base 64

- (NSString *)base64StringFromData:(NSData *)data
{
#if (__IPHONE_OS_VERSION_MIN_REQUIRED < 70000) && (__MAC_OS_X_VERSION_MIN_REQUIRED < 1090)
    NSString *string = [data base64Encoding];
#else
    NSString *string = [data base64EncodedStringWithOptions:0];
#endif
    return string;
}

#pragma mark - Requests

- (void)sendRequestForURL:(NSURL *)url HTTPMethod:(NSString *)method completion:(void(^)(NSError *error, NSDictionary *responseDict))completion
{
    // Create request
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:20.0];
    request.HTTPMethod = method;
    
    // Basic Auth
    NSString *authString = [NSString stringWithFormat:@"%@:%@", self.username, self.password];
	NSData *authData = [authString dataUsingEncoding:NSUTF8StringEncoding];
    NSString *base64AuthString = [self base64StringFromData:authData];
	NSString *authValue = [NSString stringWithFormat:@"Basic %@", base64AuthString];
	[request setValue:authValue forHTTPHeaderField:@"Authorization"];
    
    // Send request
    [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
        // Check error
        if (error) {
            if (completion) completion(error, nil);
            return;
        }
        
        // Check HTTP status
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
		NSInteger statusCode = httpResponse.statusCode;
        BOOL statusOK = (statusCode >= 200 && statusCode < 300);
        if (!statusOK) {
            NSDictionary *userInfo = @{NSLocalizedDescriptionKey : [NSString stringWithFormat:@"HTTP status code was %d", statusCode]};
            error = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeServerError userInfo:userInfo];
            if (completion) completion(error, nil);
            return;
        }
        
        // Parse Body
        NSDictionary *responseDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        if (completion) completion(error, responseDict);

        // Check for JSON error
        if ([responseDict[@"success"] boolValue]) {
            if (completion) completion(nil, responseDict);
        }
        else {
            NSDictionary *userInfo = @{NSLocalizedDescriptionKey : responseDict[@"error"]};
            error = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeServerError userInfo:userInfo];
            if (completion) completion(error, nil);
        }
    }];
}

#pragma mark - Checking File Existence

- (void)fileExistsAtPath:(NSString *)path completion:(CDEFileExistenceCallback)completion
{
    NSURL *url = [NSURL URLWithString:@"https://ensembles.herokuapp.com/uploadurls"];
    [self sendRequestForURL:url HTTPMethod:@"POST" completion:^(NSError *error, NSDictionary *responseDict) {
        if (error) {
            if (completion) completion(NO, NO, error);
            return;
        }
        
        BOOL exists = [responseDict[@"exists"] boolValue];
        BOOL isDir = NO;
        if (completion) completion(exists, isDir, nil);
    }];
}

#pragma mark - Getting Directory Contents

- (void)contentsOfDirectoryAtPath:(NSString *)path completion:(CDEDirectoryContentsCallback)block
{
}

#pragma mark - Creating Directories

- (void)createDirectoryAtPath:(NSString *)path completion:(CDECompletionBlock)block
{
}

#pragma mark - Moving and Copying

- (void)moveItemAtPath:(NSString *)fromPath toPath:(NSString *)toPath completion:(CDECompletionBlock)block
{
}

- (void)copyItemAtPath:(NSString *)fromPath toPath:(NSString *)toPath completion:(CDECompletionBlock)block
{
}

#pragma mark - Deleting

- (void)removeItemAtPath:(NSString *)path completion:(CDECompletionBlock)block
{
}

#pragma mark - Uploading and Downloading

- (void)uploadLocalFile:(NSString *)fromPath toPath:(NSString *)toPath completion:(CDECompletionBlock)block
{
}

- (void)downloadFromPath:(NSString *)fromPath toLocalFile:(NSString *)toPath completion:(CDECompletionBlock)block
{
}

@end


