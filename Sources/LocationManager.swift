import Foundation
import CoreLocation
import MapKit

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    
    // Variables required by ContentView
    @Published var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 49.2827, longitude: -123.1207),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @Published var currentShiftDistance: Double = 0.0
    @Published var baseOdometerReading: Double = 0.0
    @Published var businessKilometersDriven: Double = 0.0
    @Published var isTracking = false
    @Published var currentTripRoute: [CLLocationCoordinate2D] = []
    
    private var lastLocation: CLLocation?
    var startLocation: CLLocation?
    var endLocation: CLLocation?
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.distanceFilter = 10 // Updates every 10 meters for breadcrumb accuracy
    }
    
    func requestPermissions() {
        manager.requestAlwaysAuthorization()
        manager.startUpdatingLocation()
    }
    
    func startShift() {
        isTracking = true
        currentShiftDistance = 0.0
        currentTripRoute.removeAll()
        startLocation = manager.location
        lastLocation = manager.location
        
        if let startLoc = manager.location {
            currentTripRoute.append(startLoc.coordinate)
        }
    }
    
    func stopShift() {
        isTracking = false
        endLocation = manager.location
        businessKilometersDriven += currentShiftDistance
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // Accumulate distance breadcrumbs step-by-step
        if isTracking {
            if let previous = lastLocation {
                let distanceDelta = location.distance(from: previous) // distance in meters
                currentShiftDistance += (distanceDelta / 1000.0) // convert to kilometers
            }
            lastLocation = location
            currentTripRoute.append(location.coordinate)
        }
        
        // Keep map centered
        DispatchQueue.main.async {
            self.region = MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        }
    }
}
