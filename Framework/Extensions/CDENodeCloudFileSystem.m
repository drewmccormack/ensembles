//
//  CDENodeCloudFileSystem.m
//
//  Created by Drew McCormack on 2/17/14.
//  Copyright (c) 2014 The Mental Faculty B.V. All rights reserved.
//

#import "CDENodeCloudFileSystem.h"
#import "CDEDefines.h"
#import "CDEFoundationAdditions.h"
#import "CDECloudFile.h"
#import "CDECloudDirectory.h"

@implementation CDENodeCloudFileSystem

@synthesize username = username;
@synthesize password = password;
@synthesize baseURL = baseURL;
@synthesize loggedIn = loggedIn;

- (instancetype)initWithBaseURL:(NSURL *)newBaseURL
{
    self = [super init];
    if (self) {
        baseURL = newBaseURL;
        loggedIn = NO;
    }
    return self;
}

- (instancetype)init
{
    return [self initWithBaseURL:nil];
}

#pragma mark KVO

+ (NSSet *)keyPathsForValuesAffectingIdentityToken
{
    return [NSSet setWithObject:@"username"];
}

#pragma mark Connecting

- (BOOL)isConnected
{
    return self.isLoggedIn;
}

- (void)connect:(CDECompletionBlock)completion
{
    if (self.isConnected) {
        if (completion) completion(nil);
    }
    else {
        [self loginWithCompletion:^(NSError *error) {
            if (error.code == CDEErrorCodeAuthenticationFailure && self.delegate) {
                [self.delegate nodeCloudFileSystem:self updateLoginCredentialsWithCompletion:^(NSError *error) {
                    if (error) {
                        if (completion) completion(error);
                    }
                    else {
                        // Try the whole process again with new credentials
                        [self connect:completion];
                    }
                }];
            }
            else {
                if (completion) completion(error);
            }
        }];
    }
}

- (void)loginWithCompletion:(CDECompletionBlock)completion
{
    NSURL *url = [self.baseURL URLByAppendingPathComponent:@"login" isDirectory:NO];
    [self sendRequestForURL:url HTTPMethod:@"POST" completion:^(NSError *error, NSDictionary *responseDict) {
        loggedIn = !error;
        if (completion) completion(error);
    }];
}

#pragma mark - User Identity

- (id <NSObject, NSCoding, NSCopying>)identityToken
{
    return self.username;
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
    NSString *base64AuthString = [authData cde_base64String];
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
        BOOL authFailed = (statusCode == 401);
        if (authFailed) self.password = nil;
        if (!statusOK) {
            NSInteger code = authFailed ? CDEErrorCodeAuthenticationFailure : CDEErrorCodeServerError;
            NSDictionary *userInfo = @{NSLocalizedDescriptionKey : [NSString stringWithFormat:@"HTTP status code was %d", statusCode]};
            error = [NSError errorWithDomain:CDEErrorDomain code:code userInfo:userInfo];
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
    NSURL *url = [self.baseURL URLByAppendingPathComponent:@"uploadurls" isDirectory:NO];
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


