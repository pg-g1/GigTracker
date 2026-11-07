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
            
            TripsListView()
                .tabItem { Label("Logbook", systemImage: "list.bullet.clipboard") }
            
            ReportsView()
                .tabItem { Label("Reports", systemImage: "square.and.arrow.up") }
        }
        .onAppear {
            locationManager.requestPermissions()
            // Listen for finished trips and save them to the database
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
            VStack(spacing: 20) {
                // Fixed proportion map
                Map(coordinateRegion: $locationManager.region, showsUserLocation: true)
                    .frame(height: 250)
                    .clipShape(RoundedRectangle(cornerRadius: 15))
                    .padding(.horizontal)
                
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
                        TextField("Base Odometer (km)", text: $odometerInput)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        Button("Set") {
                            if let val = Double(odometerInput) {
                                locationManager.saveBaseOdometer(reading: val)
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
                
                Spacer()
                
                // Big properly sized button
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
                .padding(.bottom, 30)
            }
            .navigationTitle("Gig Tracker")
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
            VStack(spacing: 30) {
                Image(systemName: "doc.text.magnifyingglass")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .foregroundColor(.blue)
                
                Text("CRA Logbook Export")
                    .font(.title2).bold()
                
                Text("Generate a CSV spreadsheet of all your logged trips for tax purposes.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.gray)
                    .padding(.horizontal)
                
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
                
                Spacer()
            }
            .padding(.top, 50)
            .navigationTitle("Reports")
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
