//
//  CDENodeCloudFileSystem.m
//
//  Created by Drew McCormack on 2/17/14.
//  Copyright (c) 2014 The Mental Faculty B.V. All rights reserved.
//

#import "CDENodeCloudFileSystem.h"

@interface CDENodeCloudFileSystem ()

@property (nonatomic, readwrite, assign, getter = isLoggedIn) BOOL loggedIn;

@end


@implementation CDENodeCloudFileSystem {
    NSOperationQueue *operationQueue;
}

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
        operationQueue = [[NSOperationQueue alloc] init];
        operationQueue.maxConcurrentOperationCount = 1;
    }
    return self;
}

- (instancetype)init
{
    return [self initWithBaseURL:nil];
}

- (void)dealloc
{
    [operationQueue cancelAllOperations];
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
    [self postJSONObject:nil toURL:url completion:^(NSError *error, NSDictionary *responseDict) {
        self.loggedIn = (nil == error);
        if (completion) completion(error);
    }];
}

#pragma mark - User Identity

- (id <NSObject, NSCoding, NSCopying>)identityToken
{
    return self.username;
}

#pragma mark - Checking File Existence

- (void)fileExistsAtPath:(NSString *)path completion:(CDEFileExistenceCallback)completion
{
    NSURL *url = [self.baseURL URLByAppendingPathComponent:@"fileexists" isDirectory:NO];
    [self postJSONObject:@{@"path":path} toURL:url completion:^(NSError *error, NSDictionary *responseDict) {
        if (error) {
            if (completion) completion(NO, NO, error);
            return;
        }
        
        BOOL exists = [responseDict[@"exists"] boolValue];
        BOOL isDir = [responseDict[@"isdir"] boolValue];
        if (completion) completion(exists, isDir, nil);
    }];
}

#pragma mark - Getting Directory Contents

- (void)contentsOfDirectoryAtPath:(NSString *)path completion:(CDEDirectoryContentsCallback)completion
{
    NSURL *url = [self.baseURL URLByAppendingPathComponent:@"listdir" isDirectory:NO];
    [self postJSONObject:@{@"path":path} toURL:url completion:^(NSError *error, NSDictionary *responseDict) {
        NSArray *filenames = responseDict[@"files"];
        NSArray *files = [filenames cde_arrayByTransformingObjectsWithBlock:^CDECloudFile* (NSString *filename) {
            CDECloudFile *file = [[CDECloudFile alloc] init];
            file.name = filename;
            file.path = [path stringByAppendingPathComponent:filename];
            return file;
        }];
        if (completion) completion(files, error);
    }];
}

#pragma mark - Creating Directories

- (void)createDirectoryAtPath:(NSString *)path completion:(CDECompletionBlock)completion
{
    // S3 doesn't have directories, so just indicate success
    dispatch_async(dispatch_get_main_queue(), ^{
        if (completion) completion(nil);
    });
}

#pragma mark - Deleting

- (void)removeItemAtPath:(NSString *)path completion:(CDECompletionBlock)completion
{
    NSURL *url = [self.baseURL URLByAppendingPathComponent:@"deleteurls" isDirectory:NO];
    [self postJSONObject:@{@"paths" : @[path]} toURL:url completion:^(NSError *error, NSDictionary *responseDict) {
        if (error) {
            if (completion) completion(error);
            return;
        }
        
        NSArray *urls = responseDict[@"urls"];
        NSURL *url = [NSURL URLWithString:urls.lastObject];
        [self sendRequestForURL:url HTTPMethod:@"DELETE" authenticate:NO contentType:nil body:nil completion:^(NSError *error, NSDictionary *responseDict) {
            if (completion) completion(error);
        }];
    }];
}

#pragma mark - Uploading and Downloading

- (void)uploadLocalFile:(NSString *)fromPath toPath:(NSString *)toPath completion:(CDECompletionBlock)completion
{
    NSURL *url = [self.baseURL URLByAppendingPathComponent:@"uploadurls" isDirectory:NO];
    [self postJSONObject:@{@"paths" : @[toPath]} toURL:url completion:^(NSError *error, NSDictionary *responseDict) {
        if (error) {
            if (completion) completion(error);
            return;
        }
        
        NSArray *urls = responseDict[@"urls"];
        NSURL *url = [NSURL URLWithString:urls.lastObject];
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData timeoutInterval:300.0];
        request.HTTPMethod = @"PUT";
        
        CDEFileUploadOperation *operation = [[CDEFileUploadOperation alloc] initWithURLRequest:request localPath:fromPath];
        operation.completion = completion;
        [operationQueue addOperation:operation];
    }];
}

- (void)downloadFromPath:(NSString *)fromPath toLocalFile:(NSString *)toPath completion:(CDECompletionBlock)completion
{
    NSURL *url = [self.baseURL URLByAppendingPathComponent:@"downloadurls" isDirectory:NO];
    [self postJSONObject:@{@"paths" : @[fromPath]} toURL:url completion:^(NSError *error, NSDictionary *responseDict) {
        if (error) {
            if (completion) completion(error);
            return;
        }
        
        NSArray *urls = responseDict[@"urls"];
        NSURL *url = [NSURL URLWithString:urls.lastObject];
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
        request.cachePolicy = NSURLRequestReloadIgnoringLocalAndRemoteCacheData;
        CDEFileDownloadOperation *operation = [[CDEFileDownloadOperation alloc] initWithURLRequest:request localPath:toPath];
        operation.completion = completion;
        [operationQueue addOperation:operation];
    }];
}

#pragma mark - Signing Up New User

- (void)signUpWithCompletion:(CDECompletionBlock)completion
{
    NSURL *url = [self.baseURL URLByAppendingPathComponent:@"createuser" isDirectory:NO];
    [self postJSONObject:@{@"email" : (self.username ? : @""), @"password" : (self.password ? : @"")} toURL:url completion:^(NSError *error, NSDictionary *responseDict) {
        if (completion) completion(error);
    }];
}

#pragma mark - Passwords

- (void)resetPasswordWithCompletion:(CDECompletionBlock)completion
{
    NSURL *url = [self.baseURL URLByAppendingPathComponent:@"resetpassword" isDirectory:NO];
    [self postJSONObject:@{@"email" : (self.username ? : @"")} toURL:url completion:^(NSError *error, NSDictionary *responseDict) {
        if (completion) completion(error);
    }];
}

- (void)changePasswordTo:(NSString *)newPassword withCompletion:(CDECompletionBlock)completion
{
    NSURL *url = [self.baseURL URLByAppendingPathComponent:@"changepassword" isDirectory:NO];
    [self postJSONObject:@{@"newpassword" : (newPassword ? : @"")} toURL:url completion:^(NSError *error, NSDictionary *responseDict) {
        if (!error) self.password = newPassword;
        if (completion) completion(error);
    }];
}

#pragma mark - Requests

- (void)postJSONObject:(id)JSONObject toURL:(NSURL *)url completion:(void(^)(NSError *error, NSDictionary *responseDict))completion
{
    NSError *error;
    NSData *data = nil;
    if (JSONObject) data = [NSJSONSerialization dataWithJSONObject:JSONObject options:0 error:&error];
    if (JSONObject && !data) {
        if (completion) completion(error, nil);
        return;
    }
    [self sendRequestForURL:url HTTPMethod:@"POST" authenticate:YES contentType:@"application/json" body:data completion:completion];
}

- (void)sendRequestForURL:(NSURL *)url HTTPMethod:(NSString *)method authenticate:(BOOL)authenticate contentType:(NSString *)contentType body:(NSData *)bodyObject completion:(void(^)(NSError *error, NSDictionary *responseDict))completion
{
    // Create request
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:20.0];
    request.HTTPMethod = method;
    if (bodyObject) request.HTTPBody = bodyObject;
    if (contentType) [request setValue:contentType forHTTPHeaderField:@"Content-Type"];
    
    // Basic Auth
    if (authenticate && self.username.length > 0 && self.password.length > 0) {
        NSString *authString = [NSString stringWithFormat:@"%@:%@", self.username, self.password];
        NSData *authData = [authString dataUsingEncoding:NSUTF8StringEncoding];
        NSString *base64AuthString = [authData cde_base64String];
        NSString *authValue = [NSString stringWithFormat:@"Basic %@", base64AuthString];
        [request setValue:authValue forHTTPHeaderField:@"Authorization"];
    }
    
    // Send request
    [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
        // Check error
        BOOL isAuthError = NO;
        if (error) isAuthError = ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorUserCancelledAuthentication);
        if (error && !isAuthError) {
            if (completion) completion(error, nil);
            return;
        }
        
        // Check HTTP status
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
		NSInteger statusCode = httpResponse.statusCode;
        BOOL statusOK = (statusCode >= 200 && statusCode < 300);
        BOOL authFailed = (statusCode == 401 || isAuthError);
        if (authFailed) self.password = nil;
        if (!statusOK) {
            NSInteger code = authFailed ? CDEErrorCodeAuthenticationFailure : CDEErrorCodeServerError;
            NSDictionary *userInfo = @{NSLocalizedDescriptionKey : [NSString stringWithFormat:@"HTTP status code was %ld", (long)statusCode]};
            error = [NSError errorWithDomain:CDEErrorDomain code:code userInfo:userInfo];
            if (completion) completion(error, nil);
            return;
        }
        
        // Parse Body
        NSDictionary *responseDict = nil;
        if (data) responseDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        
        // Check for JSON error
        if (data.length == 0 || (responseDict && [responseDict[@"success"] boolValue])) {
            if (completion) completion(nil, responseDict);
        }
        else {
            NSString *message = responseDict ? responseDict[@"error"] : @"No response";
            NSDictionary *userInfo = @{NSLocalizedDescriptionKey : message};
            error = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeServerError userInfo:userInfo];
            if (completion) completion(error, nil);
        }
    }];
}

@end


