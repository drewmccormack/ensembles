//
//  CDEObjectChange.h
//  Test App iOS
//
//  Created by Drew McCormack on 4/14/13.
//  Copyright (c) 2013 The Mental Faculty B.V. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@class CDEStoreModificationEvent;
@class CDEGlobalIdentifier;
@class CDEPropertyChangeValue;

typedef NS_ENUM(int16_t, CDEObjectChangeType) {
    CDEObjectChangeTypeInsert = 100,
    CDEObjectChangeTypeUpdate = 200,
    CDEObjectChangeTypeDelete = 300
};

@interface CDEObjectChange : NSManagedObject

@property (nonatomic) CDEObjectChangeType type;
@property (nonatomic, retain) CDEGlobalIdentifier *globalIdentifier;
@property (nonatomic, retain) CDEStoreModificationEvent *storeModificationEvent;
@property (nonatomic, retain) NSString *nameOfEntity;
@property (nonatomic, retain) NSArray *propertyChangeValues;

- (CDEPropertyChangeValue *)propertyChangeValueForPropertyName:(NSString *)name;

@end