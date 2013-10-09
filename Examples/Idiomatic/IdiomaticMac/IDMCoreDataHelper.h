//
//  IDMCoreDataHelper.h
//  Idiomatic
//
//  Created by Ernesto on 10/5/13.
//  Copyright (c) 2013 The Mental Faculty B.V. All rights reserved.
//

#import <Foundation/Foundation.h>

@class IDMTag;

@interface IDMCoreDataHelper : NSObject


-(id)initWithMangedObjectContext:(NSManagedObjectContext*)moc;

-(NSArray*)allNotes;
-(NSArray*)allTags;
-(NSArray*)notesWithTag:(IDMTag*)tag;

@end
