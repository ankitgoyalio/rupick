//
//  Item.swift
//  rupick
//
//  Created by Ankit Goyal J on 02/10/26.
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
