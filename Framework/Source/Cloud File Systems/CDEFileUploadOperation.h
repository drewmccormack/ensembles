//
//  CDEFileUploadOperation.h
//  Ensembles Mac
//
//  Created by Drew McCormack on 01/03/14.
//  Copyright (c) 2014 Drew McCormack. All rights reserved.
//

#import "CDEAsynchronousOperation.h"
#import "CDEDefines.h" 

@interface CDEFileUploadOperation : CDEAsynchronousOperation

@property (nonatomic, copy, readonly) NSURL *url;
@property (nonatomic, copy, readonly) NSString *localPath;
@property (nonatomic, strong, readonly) NSMutableURLRequest *request;
@property (nonatomic, copy, readwrite) CDECompletionBlock completion;

- (instancetype)initWithURL:(NSURL *)url localPath:(NSString *)path;

@end
