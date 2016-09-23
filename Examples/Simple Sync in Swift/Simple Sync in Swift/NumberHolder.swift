//
//  NumberHolder.swift
//  Simple Sync in Swift
//
//  Created by Drew McCormack on 31/01/16.
//  Copyright © 2016 Drew McCormack. All rights reserved.
//

import UIKit
import CoreData

class NumberHolder: NSManagedObject {
    
    @NSManaged var uniqueIdentifier: NSString
    @NSManaged var number: NSNumber
    
    class func numberHolderInContext(_ context:NSManagedObjectContext) -> NumberHolder {
        var holder:NumberHolder?
        context.performAndWait {
            let fetch = NSFetchRequest<NumberHolder>(entityName: "NumberHolder")
            holder = try! fetch.execute().last
            if holder == nil {
                holder = NumberHolder(context:context)
            }
        }
        return holder!
    }

}
