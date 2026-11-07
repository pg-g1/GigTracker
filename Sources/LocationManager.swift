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
    @Published var baseOdometerReading: Double = 0.0
    @Published var businessKilometersDriven: Double = 0.0
    @Published var isTracking = false
    @Published var currentTripRoute: [CLLocationCoordinate2D] = []
    
    private var lastLocation: CLLocation?
    var startLocation: CLLocation?
    var endLocation: CLLocation?
    
    // The missing closure your dashboard uses to log the trip
    var onTripFinished: ((Double, CLLocation?, CLLocation?, Date) -> Void)?
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.distanceFilter = 10 
    }
    
    func requestPermissions() {
        manager.requestAlwaysAuthorization()
        manager.startUpdatingLocation()
    }
    
    // The missing function your dashboard uses to update the odometer
    func saveBaseOdometer(reading: Double) {
        baseOdometerReading = reading
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
        
        // Trigger the dashboard update when the shift ends
        onTripFinished?(currentShiftDistance, startLocation, endLocation, Date())
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        if isTracking {
            if let previous = lastLocation {
                let distanceDelta = location.distance(from: previous) 
                currentShiftDistance += (distanceDelta / 1000.0) 
            }
            lastLocation = location
            currentTripRoute.append(location.coordinate)
        }
        
        DispatchQueue.main.async {
            self.region = MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        }
    }
}
