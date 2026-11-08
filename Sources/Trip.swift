import Foundation
import SwiftData
import CoreLocation

@Model
class Trip {
    var id: UUID
    var date: Date
    var distanceInKm: Double
    var startAddress: String // Can be updated later
    var endAddress: String   // Can be updated later
    var tripType: String 
    var routeData: Data? 
    
    init(date: Date, distanceInKm: Double, startAddress: String = "Fetching Address...", endAddress: String = "Fetching Address...", tripType: String = "Unclassified", routeData: Data? = nil) {
        self.id = UUID()
        self.date = date
        self.distanceInKm = distanceInKm
        self.startAddress = startAddress
        self.endAddress = endAddress
        self.tripType = tripType
        self.routeData = routeData
    }
}

struct CodableCoordinate: Codable {
    let latitude: Double
    let longitude: Double
    
    init(_ coordinate: CLLocationCoordinate2D) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
