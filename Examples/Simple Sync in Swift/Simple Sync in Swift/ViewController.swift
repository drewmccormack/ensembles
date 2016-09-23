//
//  ViewController.swift
//  Simple Sync in Swift
//
//  Created by Drew McCormack on 31/01/16.
//  Copyright © 2016 Drew McCormack. All rights reserved.
//

import UIKit
import CoreData

class ViewController: UIViewController {
    
    var managedObjectContext: NSManagedObjectContext!
    var numberHolder: NumberHolder!
    
    @IBOutlet weak var numberLabel: UILabel!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView?
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        numberHolder = NumberHolder.numberHolderInContext(managedObjectContext)
        numberLabel.text = numberHolder.number.stringValue
    }
    
    func refresh() {
        numberLabel.text = numberHolder.number.stringValue
    }

    @IBAction func changeNumber(_ sender:AnyObject?) {
        let oldNumber = numberHolder.number.intValue
        var newNumber = 0 as Int
        repeat {
            newNumber = Int(arc4random()) % 100
        } while (oldNumber == newNumber)
        
        numberHolder.number = NSNumber(value: newNumber as Int)
        numberLabel.text = numberHolder.number.stringValue
        
        try! managedObjectContext.save()
    }
    
}

