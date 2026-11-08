import Foundation
import CoreLocation
import MapKit

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var stopTimer: Timer?
    
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
        manager.distanceFilter = 3.0 
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
        startLocation = manager.location ?? lastLocation
        
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
        var startAddressString = "Unknown Start Location"
        var endAddressString = "Unknown End Location"
        
        if let start = capturedStart {
            group.enter()
            geocoder.reverseGeocodeLocation(start) { placemarks, error in
                if let p = placemarks?.first {
                    startAddressString = [p.subThoroughfare, p.thoroughfare, p.locality].compactMap { $0 }.joined(separator: " ")
                } else {
                    startAddressString = "Lat: \(String(format: "%.4f", start.coordinate.latitude)), Lon: \(String(format: "%.4f", start.coordinate.longitude))"
                }
                group.leave()
            }
        }
        
        if let end = capturedEnd {
            group.enter()
            geocoder.reverseGeocodeLocation(end) { placemarks, error in
                if let p = placemarks?.first {
                    endAddressString = [p.subThoroughfare, p.thoroughfare, p.locality].compactMap { $0 }.joined(separator: " ")
                } else {
                    endAddressString = "Lat: \(String(format: "%.4f", end.coordinate.latitude)), Lon: \(String(format: "%.4f", end.coordinate.longitude))"
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
        
        let currentSpeed = location.speed 
        
        if currentSpeed > 4.0 {
            stopTimer?.invalidate()
            stopTimer = nil
            
            if !isCurrentlyDriving {
                startShift()
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
                if distanceDelta > 3.0 && distanceDelta < 1000.0 { 
                    currentShiftDistance += (distanceDelta / 1000.0)
                }
            }
            currentTripRoute.append(location.coordinate)
        }
        
        lastLocation = location
        
        DispatchQueue.main.async {
            self.region = MKCoordinateRegion(center: location.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
        }
    }
    
    // MARK: - Debug Simulator
    func runSimulation() {
        print("Starting simulated drive...")
        // Starts the fake drive near Kwantlen / 72 Ave in Surrey
        var currentLat = 49.1328
        var currentLon = -122.8714
        var step = 0
        
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else { return }
            step += 1
            
            // Moves the fake GPS coordinates slightly north every second
            currentLat += 0.0002
            
            // Simulates driving at 36 km/h (10 m/s) for 15 seconds, then dropping to 0
            let simulatedSpeed: CLLocationSpeed = step <= 15 ? 10.0 : 0.0
            
            let simulatedLocation = CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: currentLat, longitude: currentLon),
                altitude: 10,
                horizontalAccuracy: 5,
                verticalAccuracy: 5,
                course: 0,
                speed: simulatedSpeed,
                timestamp: Date()
            )
            
            // Feeds the fake location directly into the app's brain
            self.locationManager(self.manager, didUpdateLocations: [simulatedLocation])
            
            // Stop the simulation after 20 seconds
            if step > 20 {
                timer.invalidate()
            }
        }
    }
}
