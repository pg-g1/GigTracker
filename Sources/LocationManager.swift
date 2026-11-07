import Foundation
import CoreLocation
import MapKit

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    
    @Published var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 49.2827, longitude: -123.1207),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    
    @Published var currentShiftDistance: Double = 0.0
    @Published var isTracking = false
    
    private var lastLocation: CLLocation?
    var startLocation: CLLocation?
    var endLocation: CLLocation?
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.distanceFilter = 10 // Updates every 10 meters to save battery while preserving accuracy
        manager.requestAlwaysAuthorization()
        manager.startUpdatingLocation()
    }
    
    func startShift() {
        isTracking = true
        currentShiftDistance = 0.0
        startLocation = manager.location
        lastLocation = manager.location
    }
    
    func stopShift() {
        isTracking = false
        endLocation = manager.location
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // Accumulate distance breadcrumbs if a shift is active
        if isTracking {
            if let previous = lastLocation {
                let distanceDelta = location.distance(from: previous)
                currentShiftDistance += distanceDelta
            }
            lastLocation = location
        }
        
        // Keep the map centered on the user
        DispatchQueue.main.async {
            self.region = MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        }
    }
}
