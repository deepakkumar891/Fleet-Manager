//
//  Item.swift
//  Fleet Manager
//
//  Created by Deepak Kumar on 30/03/2025.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
