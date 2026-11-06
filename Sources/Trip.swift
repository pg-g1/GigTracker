import Foundation
import SwiftData

@Model
class Trip {
    var date: Date
    var distanceInKm: Double
    var startAddress: String
    var endAddress: String
    
    init(date: Date, distanceInKm: Double, startAddress: String, endAddress: String) {
        self.date = date
        self.distanceInKm = distanceInKm
        self.startAddress = startAddress
        self.endAddress = endAddress
    }
}
