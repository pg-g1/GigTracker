import SwiftUI
import SwiftData
import MapKit

// MARK: - Main Tab Layout
struct ContentView: View {
    @StateObject private var locationManager = LocationManager()
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        TabView {
            DashboardView(locationManager: locationManager)
                .tabItem { Label("Drive", systemImage: "car.fill") }
                .toolbarBackground(.visible, for: .tabBar) // Forces solid tab bar
            
            TripsListView()
                .tabItem { Label("Logbook", systemImage: "list.bullet.clipboard") }
                .toolbarBackground(.visible, for: .tabBar)
            
            ReportsView()
                .tabItem { Label("Reports", systemImage: "square.and.arrow.up") }
                .toolbarBackground(.visible, for: .tabBar)
        }
        .onAppear {
            locationManager.requestPermissions()
            locationManager.onTripFinished = { distance, start, end, date, route in
                let codableRoute = route.map { CodableCoordinate($0) }
                let routeData = try? JSONEncoder().encode(codableRoute)
                
                let newTrip = Trip(date: date, distanceInKm: distance, startAddress: start, endAddress: end, tripType: "Unclassified", routeData: routeData)
                modelContext.insert(newTrip)
            }
        }
    }
}

// MARK: - Tab 1: Dashboard
struct DashboardView: View {
    @ObservedObject var locationManager: LocationManager
    @State private var odometerInput: String = ""
    
    var body: some View {
        NavigationStack {
            // FIX: Removed ScrollView. A dashboard should be locked in place.
            VStack(spacing: 15) {
                // Map
                Map(coordinateRegion: $locationManager.region, showsUserLocation: true)
                    .frame(height: 220) // Slightly smaller to ensure a perfect fit
                    .clipShape(RoundedRectangle(cornerRadius: 15))
                    .padding(.horizontal)
                    .padding(.top, 10)
                
                // Odometer & Shift Stats
                VStack(spacing: 15) {
                    HStack {
                        Text("Shift Distance:")
                            .font(.headline)
                        Spacer()
                        Text(String(format: "%.2f km", locationManager.currentShiftDistance))
                            .font(.title3).bold()
                    }
                    
                    HStack {
                        TextField("Base Odometer", text: $odometerInput)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        Button("Set") {
                            if let val = Double(odometerInput) {
                                locationManager.saveBaseOdometer(reading: val)
                                odometerInput = ""
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    
                    HStack {
                        Text("Current Odometer:")
                            .font(.subheadline).foregroundColor(.gray)
                        Spacer()
                        Text(String(format: "%.2f km", locationManager.baseOdometerReading + locationManager.currentShiftDistance))
                            .font(.headline)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(15)
                .padding(.horizontal)
                
                Spacer() // Pushes the button cleanly to the bottom
                
                // Start/Stop Button
                Button(action: {
                    locationManager.toggleManualTracking()
                }) {
                    Text(locationManager.isCurrentlyDriving ? "End Shift" : "Start Shift")
                        .font(.title2).bold()
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(locationManager.isCurrentlyDriving ? Color.red : Color.green)
                        .cornerRadius(15)
                }
                .padding(.horizontal)
                .padding(.bottom, 10)
            }
            .navigationTitle("Gig Tracker")
            .navigationBarTitleDisplayMode(.inline) // FIX: Changes giant floating text to a small, neat top bar
            .toolbarBackground(.visible, for: .navigationBar) // FIX: Forces the top bar to be solid
        }
    }
}

// MARK: - Tab 2: Logbook (Trips List)
struct TripsListView: View {
    @Query(sort: \Trip.date, order: .reverse) var trips: [Trip]
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(trips) { trip in
                    NavigationLink(destination: TripDetailView(trip: trip)) {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(trip.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.subheadline).bold()
                                Spacer()
                                Text(String(format: "%.2f km", trip.distanceInKm))
                                    .font(.subheadline)
                            }
                            Text(trip.tripType)
                                .font(.caption)
                                .foregroundColor(trip.tripType == "Business" ? .green : (trip.tripType == "Personal" ? .blue : .red))
                        }
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        modelContext.delete(trips[index])
                    }
                }
            }
            .navigationTitle("Trip Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

// MARK: - Trip Detail View (Classification & Map)
struct TripDetailView: View {
    @Bindable var trip: Trip
    
    var routeCoordinates: [CLLocationCoordinate2D] {
        guard let data = trip.routeData,
              let decoded = try? JSONDecoder().decode([CodableCoordinate].self, from: data) else { return [] }
        return decoded.map { $0.coordinate }
    }
    
    var body: some View {
        Form {
            Section(header: Text("Classify Trip")) {
                Picker("Trip Type", selection: $trip.tripType) {
                    Text("Unclassified").tag("Unclassified")
                    Text("Business").tag("Business")
                    Text("Personal").tag("Personal")
                }
                .pickerStyle(.segmented)
            }
            
            Section(header: Text("Trip Details")) {
                Text("Start: \(trip.startAddress)")
                Text("End: \(trip.endAddress)")
                Text("Distance: \(String(format: "%.2f km", trip.distanceInKm))")
            }
            
            if !routeCoordinates.isEmpty {
                Section(header: Text("Route Map")) {
                    Map {
                        MapPolyline(coordinates: routeCoordinates)
                            .stroke(.blue, lineWidth: 4)
                        if let first = routeCoordinates.first {
                            Marker("Start", coordinate: first).tint(.green)
                        }
                        if let last = routeCoordinates.last {
                            Marker("End", coordinate: last).tint(.red)
                        }
                    }
                    .frame(height: 250)
                }
            }
        }
        .navigationTitle("Trip Info")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Tab 3: Reports (CRA Export)
struct ReportsView: View {
    @Query(sort: \Trip.date, order: .reverse) var trips: [Trip]
    @State private var csvURL: URL?
    
    var body: some View {
        NavigationStack {
            // FIX: Removed scroll view to lock elements in place
            VStack(spacing: 30) {
                Image(systemName: "doc.text.magnifyingglass")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .foregroundColor(.blue)
                    .padding(.top, 40)
                
                Text("CRA Logbook Export")
                    .font(.title2).bold()
                
                Text("Generate a CSV spreadsheet of all your logged trips for tax purposes.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.gray)
                    .padding(.horizontal)
                    .fixedSize(horizontal: false, vertical: true)
                
                if let url = csvURL {
                    ShareLink(item: url) {
                        Text("Export CSV File")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(15)
                    }
                    .padding(.horizontal)
                } else {
                    Button(action: generateCSV) {
                        Text("Generate Report")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .cornerRadius(15)
                    }
                    .padding(.horizontal)
                }
                
                Spacer() // Pushes everything up slightly so it looks balanced
            }
            .navigationTitle("Reports")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
    
    func generateCSV() {
        var csvString = "Date,Type,Distance (km),Start Address,End Address\n"
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        
        for trip in trips {
            let dateStr = formatter.string(from: trip.date)
            let safeStart = trip.startAddress.replacingOccurrences(of: ",", with: " ")
            let safeEnd = trip.endAddress.replacingOccurrences(of: ",", with: " ")
            csvString += "\(dateStr),\(trip.tripType),\(String(format: "%.2f", trip.distanceInKm)),\(safeStart),\(safeEnd)\n"
        }
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("CRA_Mileage_Log.csv")
        do {
            try csvString.write(to: tempURL, atomically: true, encoding: .utf8)
            csvURL = tempURL
        } catch {
            print("Failed to create CSV")
        }
    }
}
