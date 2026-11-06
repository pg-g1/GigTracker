import SwiftUI
import MapKit
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Trip.date, order: .reverse) private var savedTrips: [Trip]
    
    @StateObject private var locationManager = LocationManager()
    @State private var newOdometerInput: String = ""
    
    var computedCurrentOdometer: Double {
        return locationManager.baseOdometerReading + locationManager.businessKilometersDriven
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    
                    VStack {
                        Text("Current Virtual Odometer")
                            .font(.headline)
                            .foregroundColor(.gray)
                        Text("\(computedCurrentOdometer, specifier: "%.2f") km")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 15).fill(Color(UIColor.systemGray6)))
                    .padding(.horizontal)
                    
                    Map {
                        UserAnnotation()
                        if !locationManager.currentTripRoute.isEmpty {
                            MapPolyline(coordinates: locationManager.currentTripRoute)
                                .stroke(.blue, lineWidth: 5)
                        }
                    }
                    .mapControls {
                        MapUserLocationButton()
                    }
                    .frame(height: 250)
                    .cornerRadius(15)
                    .padding(.horizontal)
                    
                    VStack(alignment: .leading) {
                        Text("Base Dashboard Odometer")
                            .font(.subheadline)
                        HStack {
                            TextField("e.g. 45000", text: $newOdometerInput)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            
                            Button("Update") {
                                if let val = Double(newOdometerInput) {
                                    locationManager.saveBaseOdometer(reading: val)
                                    newOdometerInput = ""
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.horizontal)
                    
                    Button(action: {
                        locationManager.toggleManualTracking()
                    }) {
                        Text(locationManager.isCurrentlyDriving ? "Stop Gig Shift" : "Start Gig Shift")
                            .font(.title3)
                            .bold()
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(locationManager.isCurrentlyDriving ? Color.red : Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    
                    Divider().padding(.vertical, 10)
                    
                    VStack(alignment: .leading) {
                        Text("Recent Trips")
                            .font(.title2)
                            .bold()
                            .padding(.horizontal)
                        
                        if savedTrips.isEmpty {
                            Text("No trips logged yet.")
                                .foregroundColor(.gray)
                                .padding(.horizontal)
                        } else {
                            ForEach(savedTrips) { trip in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(trip.date.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.subheadline)
                                        .foregroundColor(.blue)
                                    Text("From: \(trip.startAddress)")
                                        .font(.caption)
                                    Text("To: \(trip.endAddress)")
                                        .font(.caption)
                                    Text("Distance: \(trip.distanceInKm, specifier: "%.2f") km")
                                        .font(.subheadline).bold()
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Color(UIColor.systemGray6)))
                                .padding(.horizontal)
                            }
                        }
                    }
                }
                .padding(.bottom, 30)
            }
            .navigationTitle("Gig Tracker")
            .onAppear {
                locationManager.requestPermissions()
                
                locationManager.onTripFinished = { distance, start, end, date in
                    if distance > 0.1 {
                        let newTrip = Trip(date: date, distanceInKm: distance, startAddress: start, endAddress: end)
                        modelContext.insert(newTrip)
                    }
                }
            }
        }
    }
}
