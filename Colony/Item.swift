//
//  Item.swift
//  Colony
//
//  Created by Yoav Peretz on 17/06/2026.
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
