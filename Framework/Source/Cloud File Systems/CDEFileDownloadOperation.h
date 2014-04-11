//
//  CDEFileDownloadOperation.h
//  Ensembles iOS
//
//  Created by Drew McCormack on 01/03/14.
//  Copyright (c) 2014 The Mental Faculty B.V. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CDEAsynchronousOperation.h"
#import "CDEDefines.h"

@interface CDEFileDownloadOperation : CDEAsynchronousOperation

@property (nonatomic, copy, readonly) NSURLRequest *request;
@property (nonatomic, copy, readonly) NSString *localPath;
@property (nonatomic, copy, readwrite) CDECompletionBlock completion;

- (instancetype)initWithURLRequest:(NSURLRequest *)newRequest localPath:(NSString *)path;

@end
