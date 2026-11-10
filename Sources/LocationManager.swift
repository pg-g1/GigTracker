import Foundation
import CoreLocation
import MapKit

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    let manager = CLLocationManager()
    private var stopTimer: Timer?
    
    private var recentBreadcrumbs: [CLLocation] = []
    
    @Published var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 49.2827, longitude: -123.1207),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @Published var currentShiftDistance: Double = 0.0
    
    @Published var baseOdometerReading: Double {
        didSet { UserDefaults.standard.set(baseOdometerReading, forKey: "saved_base_odometer") }
    }
    
    @Published var isTracking = false
    @Published var isCurrentlyDriving = false
    @Published var currentTripRoute: [CLLocationCoordinate2D] = []
    
    private var lastLocation: CLLocation?
    
    var onTripFinished: ((Double, Date, [CLLocationCoordinate2D]) -> Void)?
    
    override init() {
        self.baseOdometerReading = UserDefaults.standard.double(forKey: "saved_base_odometer")
        super.init()
        
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.activityType = .automotiveNavigation
        manager.showsBackgroundLocationIndicator = true 
        manager.distanceFilter = kCLDistanceFilterNone
    }
    
    func requestPermissions() {
        manager.requestAlwaysAuthorization()
        manager.startUpdatingLocation()
        manager.startMonitoringSignificantLocationChanges()
    }
    
    func saveBaseOdometer(reading: Double) {
        baseOdometerReading = reading
    }
    
    func toggleManualTracking() {
        if isCurrentlyDriving { 
            stopTimer?.invalidate()
            stopTimer = nil
            stopShift() 
        } else { 
            startShift() 
        }
    }
    
    func startShift() {
        guard !isCurrentlyDriving else { return }
        isTracking = true
        isCurrentlyDriving = true
        currentShiftDistance = 0.0
        currentTripRoute.removeAll()
        lastLocation = manager.location
        
        if let startLoc = manager.location {
            currentTripRoute.append(startLoc.coordinate)
        }
    }
    
    func stopShift() {
        guard isCurrentlyDriving else { return }
        isTracking = false
        isCurrentlyDriving = false
        
        baseOdometerReading += currentShiftDistance
        
        let capturedDistance = currentShiftDistance
        let capturedRoute = currentTripRoute
        
        DispatchQueue.main.async {
            self.onTripFinished?(capturedDistance, Date(), capturedRoute)
        }
        
        currentShiftDistance = 0.0
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // --- THE ANTI-DRIFT SHIELD ---
        // Ignore any GPS ping with an accuracy worse than 25 meters. 
        // This makes the app totally blind to indoor bouncing.
        guard location.horizontalAccuracy >= 0 && location.horizontalAccuracy < 25 else { 
            return 
        }
        
        recentBreadcrumbs.append(location)
        recentBreadcrumbs.removeAll { $0.timestamp.timeIntervalSinceNow < -30 }
        
        let currentSpeed = location.speed 
        
        if currentSpeed > 2.5 {
            stopTimer?.invalidate()
            stopTimer = nil
            
            if !isCurrentlyDriving {
                isTracking = true
                isCurrentlyDriving = true
                currentShiftDistance = 0.0
                currentTripRoute.removeAll()
                
                let validBreadcrumbs = recentBreadcrumbs
                for crumb in validBreadcrumbs {
                    currentTripRoute.append(crumb.coordinate)
                }
                
                if validBreadcrumbs.count > 1 {
                    for i in 1..<validBreadcrumbs.count {
                        currentShiftDistance += (validBreadcrumbs[i].distance(from: validBreadcrumbs[i-1]) / 1000.0)
                    }
                }
                lastLocation = location
            }
        } 
        else if currentSpeed >= 0 && currentSpeed < 1.0 {
            if isCurrentlyDriving && stopTimer == nil {
                stopTimer = Timer.scheduledTimer(withTimeInterval: 180.0, repeats: false) { [weak self] _ in
                    self?.stopShift()
                    self?.stopTimer = nil
                }
            }
        }
        
        if isTracking {
            if let previous = lastLocation {
                let distanceDelta = location.distance(from: previous)
                if distanceDelta > 2.0 && distanceDelta < 1000.0 { 
                    currentShiftDistance += (distanceDelta / 1000.0)
                    currentTripRoute.append(location.coordinate)
                    lastLocation = location
                }
            } else {
                lastLocation = location
            }
        }
        
        DispatchQueue.main.async {
            self.region = MKCoordinateRegion(center: location.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
        }
    }
    
    func runSimulation() {
        print("Starting simulated drive...")
        var currentLat = 49.1328
        var currentLon = -122.8714
        var step = 0
        
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else { return }
            step += 1
            currentLat += 0.0002
            let simulatedSpeed: CLLocationSpeed = step <= 15 ? 10.0 : 0.0
            
            let simulatedLocation = CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: currentLat, longitude: currentLon),
                // Notice the simulated accuracy is a perfect 5 meters
                altitude: 10, horizontalAccuracy: 5, verticalAccuracy: 5, course: 0,
                speed: simulatedSpeed, timestamp: Date()
            )
            
            self.locationManager(self.manager, didUpdateLocations: [simulatedLocation])
            if step > 20 { timer.invalidate() }
        }
    }
}
