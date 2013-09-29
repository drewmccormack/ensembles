//
//  NSMapTable+CDEAdditions.h
//  Test App iOS
//
//  Created by Drew McCormack on 5/26/13.
//  Copyright (c) 2013 The Mental Faculty B.V. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSMapTable (CDEAdditions)

@property (readonly) NSArray *cde_allValues;

- (void)cde_addEntriesFromMapTable:(NSMapTable *)otherTable;

@end
