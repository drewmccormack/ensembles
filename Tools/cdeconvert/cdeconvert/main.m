//
//  main.m
//  cdeconvert
//
//  Created by Drew McCormack on 28/09/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#import "model.h"

int main(int argc, const char * argv[])
{
    @autoreleasepool {
        // Usage
        if (argc != 2) {
            NSLog(@"Usage: Enter a path to a directory containing binary cdeevent files.\nThey are extracted to the Desktop.");
            return -1;
        }
        
        // Create temp directory
        NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
        [[NSFileManager defaultManager] removeItemAtPath:tempPath error:NULL];
        [[NSFileManager defaultManager] createDirectoryAtPath:tempPath withIntermediateDirectories:NO attributes:nil error:NULL];
        
        // Write model tar data to file
        NSData *eventModelData = [NSData dataWithBytes:eventModelTarredData length:eventModelTarredData_len];
        NSString *tarredDataPath = [tempPath stringByAppendingPathComponent:@"eventModel.tar"];
        [eventModelData writeToFile:tarredDataPath atomically:NO];

        // Extract tar file
        NSTask *task = [[NSTask alloc] init];
        task.currentDirectoryPath = tempPath;
        task.launchPath = @"/usr/bin/tar";
        task.arguments = @[@"-xf", tarredDataPath];
        [task launch];
        [task waitUntilExit];
        
        // Extract events and export to folder on Desktop as XML
        NSString *eventDirPath = [[NSString stringWithCString:argv[1] encoding:NSUTF8StringEncoding] stringByExpandingTildeInPath];
        NSString *modelPath = [tempPath stringByAppendingPathComponent:@"CDEEventStoreModel.momd"];
        NSURL *modelURL = [NSURL fileURLWithPath:modelPath];
        NSManagedObjectModel *model = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
        
        NSURL *desktopURL = [[NSFileManager defaultManager] URLForDirectory:NSDesktopDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:NO error:NULL];
        NSURL *eventDirURL = [NSURL fileURLWithPath:eventDirPath];
        NSURL *resultDirURL = [desktopURL URLByAppendingPathComponent:[NSString stringWithFormat:@"cdeevents_%@", [NSDate date]]];
        [[NSFileManager defaultManager] createDirectoryAtURL:resultDirURL withIntermediateDirectories:NO attributes:nil error:NULL];
        
        NSDirectoryEnumerator *dirEnum = [[NSFileManager defaultManager] enumeratorAtURL:eventDirURL includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsSubdirectoryDescendants errorHandler:NULL];
        NSURL *eventURL;
        while (eventURL = [dirEnum nextObject]) {
            @autoreleasepool {
                if ([[eventURL lastPathComponent] hasPrefix:@"."]) continue;
                
                NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
                
                NSError *error;
                NSDictionary *metadata = [NSPersistentStoreCoordinator metadataForPersistentStoreOfType:nil URL:eventURL error:&error];
                NSString *storeType = metadata[NSStoreTypeKey];
                NSDictionary *options = @{NSMigratePersistentStoresAutomaticallyOption : @YES, NSInferMappingModelAutomaticallyOption : @YES};
                NSPersistentStore *fromStore = [coordinator addPersistentStoreWithType:storeType configuration:nil URL:eventURL options:options error:&error];
                if (!fromStore) {
                    NSLog(@"Couldn't open store: %@", error);
                    continue;
                }
                
                NSURL *toURL = [resultDirURL URLByAppendingPathComponent:[eventURL.path lastPathComponent]];
                toURL = [toURL URLByAppendingPathExtension:@"xml"];
                
                [coordinator migratePersistentStore:fromStore toURL:toURL options:options withType:NSXMLStoreType error:NULL];
            }
        }
        
        // Clean up
        [[NSFileManager defaultManager] removeItemAtPath:tempPath error:NULL];
    }
    return 0;
}

