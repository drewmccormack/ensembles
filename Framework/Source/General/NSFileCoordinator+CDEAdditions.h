//
//  NSFileCoordinator+CDEAdditions.h
//  Ensembles Mac
//
//  Created by Drew McCormack on 23/01/15.
//  Copyright (c) 2015 Drew McCormack. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSFileCoordinator (CDEAdditions)

- (void)cde_coordinateReadingItemAtURL:(NSURL *)url options:(NSFileCoordinatorReadingOptions)options timeout:(NSTimeInterval)timeout error:(NSError *__autoreleasing *)outError byAccessor:(void (^)(NSURL *))reader;
- (void)cde_coordinateReadingItemAtURL:(NSURL *)readingURL options:(NSFileCoordinatorReadingOptions)readingOptions writingItemAtURL:(NSURL *)writingURL options:(NSFileCoordinatorWritingOptions)writingOptions timeout:(NSTimeInterval)timeout error:(NSError *__autoreleasing *)outError byAccessor:(void (^)(NSURL *, NSURL *))readerWriter;

- (void)cde_coordinateWritingItemAtURL:(NSURL *)url options:(NSFileCoordinatorWritingOptions)options timeout:(NSTimeInterval)timeout error:(NSError *__autoreleasing *)outError byAccessor:(void (^)(NSURL *))writer;

@end
