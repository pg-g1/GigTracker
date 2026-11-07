import Foundation
import CoreLocation
import MapKit

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    
    @Published var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 49.2827, longitude: -123.1207),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @Published var currentShiftDistance: Double = 0.0
    
    // Permanently saves base odometer in UserDefaults so it survives app restarts
    @Published var baseOdometerReading: Double {
        didSet {
            UserDefaults.standard.set(baseOdometerReading, forKey: "saved_base_odometer")
        }
    }
    
    @Published var isTracking = false
    @Published var isCurrentlyDriving = false
    @Published var currentTripRoute: [CLLocationCoordinate2D] = []
    
    private var lastLocation: CLLocation?
    var startLocation: CLLocation?
    var endLocation: CLLocation?
    
    var onTripFinished: ((Double, String, String, Date, [CLLocationCoordinate2D]) -> Void)?
    
    override init() {
        self.baseOdometerReading = UserDefaults.standard.double(forKey: "saved_base_odometer")
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
    
    func saveBaseOdometer(reading: Double) {
        baseOdometerReading = reading
    }
    
    func toggleManualTracking() {
        if isCurrentlyDriving { stopShift() } else { startShift() }
    }
    
    func startShift() {
        isTracking = true
        isCurrentlyDriving = true
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
        isCurrentlyDriving = false
        endLocation = manager.location
        
        let group = DispatchGroup()
        var startAddressString = "Unknown Start"
        var endAddressString = "Unknown End"
        
        if let start = startLocation {
            group.enter()
            geocoder.reverseGeocodeLocation(start) { placemarks, _ in
                if let p = placemarks?.first {
                    startAddressString = [p.subThoroughfare, p.thoroughfare, p.locality].compactMap { $0 }.joined(separator: " ")
                }
                group.leave()
            }
        }
        
        if let end = endLocation {
            group.enter()
            // Fixed typo from reverseGeocoderLocation to reverseGeocodeLocation
            geocoder.reverseGeocodeLocation(end) { placemarks, _ in
                if let p = placemarks?.first {
                    endAddressString = [p.subThoroughfare, p.thoroughfare, p.locality].compactMap { $0 }.joined(separator: " ")
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            self.onTripFinished?(self.currentShiftDistance, startAddressString, endAddressString, Date(), self.currentTripRoute)
        }
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
            self.region = MKCoordinateRegion(center: location.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
        }
    }
}
