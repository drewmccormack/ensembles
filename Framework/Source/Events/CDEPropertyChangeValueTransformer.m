//
//  CDEPropertyChangeValueTransformer.m
//  Ensembles iOS
//
//  Created by Drew McCormack on 07/07/2020.
//  Copyright © 2020 The Mental Faculty B.V. All rights reserved.
//

#import "CDEPropertyChangeValueTransformer.h"
#import "CDEDefines.h"

@implementation CDEPropertyChangeValueTransformer

+ (NSArray *)allowedTopLevelClasses
{
    return @[[NSArray class]];
}

+ (Class)transformedValueClass
{
    return [NSArray class];
}

+ (BOOL)allowsReverseTransformation
{
    return YES;
}

- (NSArray *)transformedValue:(NSData *)data
{
    if (!data) { return nil; }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated"
    id result = [NSKeyedUnarchiver unarchiveObjectWithData:data];
#pragma clang diagnostic pop
    if (!result) {
        CDELog(CDELoggingLevelError, @"Failed to unarchive");
    }
    return result;
}

- (NSData *)reverseTransformedValue:(NSArray *)changeValues
{
    if (!changeValues) { return nil; }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated"
    id result = [NSKeyedArchiver archivedDataWithRootObject:changeValues];
#pragma clang diagnostic pop
    if (!result) {
        CDELog(CDELoggingLevelError, @"Failed to archive");
    }
    return result;
}

@end

