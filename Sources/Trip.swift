import Foundation
import SwiftData
import CoreLocation

@Model
class Trip {
    var id: UUID
    var date: Date
    var distanceInKm: Double
    var startAddress: String
    var endAddress: String
    var tripType: String // "Unclassified", "Business", "Personal"
    var routeData: Data? // Saves the GPS breadcrumbs for the map
    
    init(date: Date, distanceInKm: Double, startAddress: String, endAddress: String, tripType: String = "Unclassified", routeData: Data? = nil) {
        self.id = UUID()
        self.date = date
        self.distanceInKm = distanceInKm
        self.startAddress = startAddress
        self.endAddress = endAddress
        self.tripType = tripType
        self.routeData = routeData
    }
}

// Helper to convert GPS coordinates so they can be saved to the database
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
