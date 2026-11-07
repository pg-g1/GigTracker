import Foundation
import CoreLocation
import CoreMotion
import MapKit

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let motionActivityManager = CMMotionActivityManager()
    private let geocoder = CLGeocoder()
    
    @Published var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 49.2827, longitude: -123.1207),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @Published var currentShiftDistance: Double = 0.0
    
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
        manager.distanceFilter = 5 
    }
    
    func requestPermissions() {
        manager.requestAlwaysAuthorization()
        manager.startUpdatingLocation()
        manager.startMonitoringSignificantLocationChanges()
        startAutomatedMotionDetection()
    }
    
    private func startAutomatedMotionDetection() {
        if CMMotionActivityManager.isActivityAvailable() {
            motionActivityManager.startActivityUpdates(to: .main) { [weak self] activity in
                guard let self = self, let activity = activity else { return }
                
                if activity.automotive && !self.isCurrentlyDriving {
                    print("🚗 Motion detected driving: Auto-starting shift...")
                    self.startShift()
                } 
                else if (activity.stationary || activity.walking) && self.isCurrentlyDriving {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
                        if activity.stationary && self.isCurrentlyDriving {
                            print("🛑 Stationary detected: Auto-stopping shift...")
                            self.stopShift()
                        }
                    }
                }
            }
        }
    }
    
    func saveBaseOdometer(reading: Double) {
        baseOdometerReading = reading
    }
    
    func toggleManualTracking() {
        if isCurrentlyDriving { stopShift() } else { startShift() }
    }
    
    func startShift() {
        guard !isCurrentlyDriving else { return }
        isTracking = true
        isCurrentlyDriving = true
        currentShiftDistance = 0.0
        currentTripRoute.removeAll()
        startLocation = manager.location ?? lastLocation
        lastLocation = startLocation
        
        if let startLoc = startLocation {
            currentTripRoute.append(startLoc.coordinate)
        }
    }
    
    func stopShift() {
        guard isCurrentlyDriving else { return }
        isTracking = false
        isCurrentlyDriving = false
        endLocation = manager.location ?? lastLocation
        
        baseOdometerReading += currentShiftDistance
        
        let capturedDistance = currentShiftDistance
        let capturedRoute = currentTripRoute
        let capturedStart = startLocation
        let capturedEnd = endLocation
        
        let group = DispatchGroup()
        var startAddressString = "Start Location"
        var endAddressString = "End Location"
        
        if let start = capturedStart {
            group.enter()
            geocoder.reverseGeocodeLocation(start) { placemarks, _ in
                if let p = placemarks?.first {
                    startAddressString = [p.subThoroughfare, p.thoroughfare, p.locality].compactMap { $0 }.joined(separator: " ")
                }
                group.leave()
            }
        }
        
        if let end = capturedEnd {
            group.enter()
            geocoder.reverseGeocodeLocation(end) { placemarks, _ in
                if let p = placemarks?.first {
                    endAddressString = [p.subThoroughfare, p.thoroughfare, p.locality].compactMap { $0 }.joined(separator: " ")
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            self.onTripFinished?(capturedDistance, startAddressString, endAddressString, Date(), capturedRoute)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        if isTracking {
            if let previous = lastLocation {
                // Check if timestamp is reasonable (avoids massive jumps from old cached GPS data)
                if location.timestamp.timeIntervalSince(previous.timestamp) < 60 {
                    let distanceDelta = location.distance(from: previous)
                    if distanceDelta > 2.0 { // Filter minor GPS jitter
                        currentShiftDistance += (distanceDelta / 1000.0)
                    }
                }
            }
            currentTripRoute.append(location.coordinate)
        }
        
        // FIX: This MUST happen AFTER calculating the distance!
        lastLocation = location
        
        DispatchQueue.main.async {
            self.region = MKCoordinateRegion(center: location.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
        }
    }
}
