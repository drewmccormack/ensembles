//
//  CDEFile.m
//  Ensembles
//
//  Created by Drew McCormack on 4/12/13.
//  Copyright (c) 2013 Drew McCormack. All rights reserved.
//

#import "CDECloudFile.h"

@implementation CDECloudFile

@synthesize path = path;
@synthesize name = name;
@synthesize size = size;

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];
    if (self) {
        path = [aDecoder decodeObjectForKey:@"file"];
        name = [aDecoder decodeObjectForKey:@"name"];
        size = [[aDecoder decodeObjectForKey:@"sizeNumber"] unsignedLongLongValue];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeInteger:0 forKey:@"classVersion"];
    [aCoder encodeObject:path forKey:@"path"];
    [aCoder encodeObject:name forKey:@"name"];
    [aCoder encodeObject:[NSNumber numberWithUnsignedLongLong:size] forKey:@"sizeNumber"];
}

- (id)copyWithZone:(NSZone *)zone
{
    CDECloudFile *copy = [CDECloudFile new];
    copy->path = [self->path copy];
    copy->name = [self->name copy];
    copy->size = self->size;
    return copy;
}

- (NSString *)description
{
    NSMutableString *result = [NSMutableString string];
    [result appendFormat:@"%@\r", super.description];
    NSArray *keys = @[@"path", @"name", @"size"];
    for (NSString *key in keys) {
        [result appendFormat:@"%@: %@; \r", key, [[self valueForKey:key] description]];
    }
    return result;
}

@end
