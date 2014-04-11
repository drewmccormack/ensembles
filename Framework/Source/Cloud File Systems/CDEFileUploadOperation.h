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

@property (nonatomic, copy, readonly) NSString *localPath;
@property (nonatomic, copy, readonly) NSURLRequest *request;
@property (nonatomic, copy, readwrite) CDECompletionBlock completion;

- (instancetype)initWithURLRequest:(NSURLRequest *)urlRequest localPath:(NSString *)path;

@end
