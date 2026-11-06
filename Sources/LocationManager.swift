import Foundation
import CoreLocation
import CoreMotion
import Combine

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private let motionManager = CMMotionActivityManager()
    
    @Published var isCurrentlyDriving = false
    @Published var businessKilometersDriven: Double = 0.0
    @Published var baseOdometerReading: Double = 0.0
    @Published var currentTripRoute: [CLLocationCoordinate2D] = []
    
    private var currentTripDistance: Double = 0.0
    private var tripStartAddress: String = "Unknown Location"
    private var tripStartDate: Date = Date()
    private var lastLocation: CLLocation?
    
    var onTripFinished: ((Double, String, String, Date) -> Void)?
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        
        self.businessKilometersDriven = UserDefaults.standard.double(forKey: "businessKms")
        self.baseOdometerReading = UserDefaults.standard.double(forKey: "baseOdometer")
    }
    
    func requestPermissions() {
        locationManager.requestAlwaysAuthorization()
        startMonitoringMotion()
    }
    
    private func startMonitoringMotion() {
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        
        motionManager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let self = self, let activity = activity else { return }
            
            DispatchQueue.main.async {
                if activity.automotive && !self.isCurrentlyDriving {
                    self.startTrip()
                } else if (activity.walking || activity.stationary) && self.isCurrentlyDriving {
                    self.stopTrip()
                }
            }
        }
    }
    
    func startTrip() {
        isCurrentlyDriving = true
        currentTripRoute.removeAll()
        currentTripDistance = 0.0
        tripStartDate = Date()
        
        locationManager.startUpdatingLocation()
        
        if let startLoc = locationManager.location {
            fetchAddress(for: startLoc) { address in
                self.tripStartAddress = address
            }
        }
    }
    
    func stopTrip() {
        isCurrentlyDriving = false
        locationManager.stopUpdatingLocation()
        
        if let endLoc = lastLocation {
            fetchAddress(for: endLoc) { address in
                self.onTripFinished?(self.currentTripDistance, self.tripStartAddress, address, self.tripStartDate)
            }
        }
        lastLocation = nil
    }
    
    func toggleManualTracking() {
        if isCurrentlyDriving {
            stopTrip()
        } else {
            startTrip()
        }
    }
    
    func saveBaseOdometer(reading: Double) {
        baseOdometerReading = reading
        UserDefaults.standard.set(reading, forKey: "baseOdometer")
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newLocation = locations.last, isCurrentlyDriving else { return }
        
        DispatchQueue.main.async {
            self.currentTripRoute.append(newLocation.coordinate)
        }
        
        if let last = lastLocation {
            let distanceInKm = (newLocation.distance(from: last)) / 1000.0
            DispatchQueue.main.async {
                self.currentTripDistance += distanceInKm
                self.businessKilometersDriven += distanceInKm
                UserDefaults.standard.set(self.businessKilometersDriven, forKey: "businessKms")
            }
        }
        lastLocation = newLocation
    }
    
    private func fetchAddress(for location: CLLocation, completion: @escaping (String) -> Void) {
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            guard let place = placemarks?.first, error == nil else {
                completion("Unknown Location")
                return
            }
            let streetNumber = place.subThoroughfare ?? ""
            let streetName = place.thoroughfare ?? ""
            let city = place.locality ?? ""
            let fullAddress = "\(streetNumber) \(streetName), \(city)".trimmingCharacters(in: .whitespacesAndNewlines)
            completion(fullAddress.isEmpty ? "Unknown Location" : fullAddress)
        }
    }
}
