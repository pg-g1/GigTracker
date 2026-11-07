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
            locationManager.onTripFinished = { distance, start, end, date, route in
                let codableRoute = route.map { CodableCoordinate($0) }
                let routeData = try? JSONEncoder().encode(codableRoute)
                
                let newTrip = Trip(date: date, distanceInKm: distance, startAddress: start, endAddress: end, tripType: "Unclassified", routeData: routeData)
                modelContext.insert(newTrip)
            }
        }
    }
}

// MARK: - Tab 1: Dashboard (Native Form Layout)
struct DashboardView: View {
    @ObservedObject var locationManager: LocationManager
    @State private var odometerInput: String = ""
    
    var body: some View {
        NavigationStack {
            Form {
                // Section 1: Edge-to-edge Map
                Section {
                    Map(coordinateRegion: $locationManager.region, showsUserLocation: true)
                        .frame(height: 250)
                        .listRowInsets(EdgeInsets()) // Pushes the map flush to the edges of the card
                }
                
                // Section 2: Odometer Stats
                Section(header: Text("Shift Stats")) {
                    HStack {
                        Text("Shift Distance")
                        Spacer()
                        Text(String(format: "%.2f km", locationManager.currentShiftDistance))
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Base Odometer")
                        Spacer()
                        TextField("e.g. 45000", text: $odometerInput)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                        
                        Button("Set") {
                            if let val = Double(odometerInput) {
                                locationManager.saveBaseOdometer(reading: val)
                                odometerInput = ""
                            }
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(.blue)
                    }
                    
                    HStack {
                        Text("Current Odometer")
                        Spacer()
                        Text(String(format: "%.2f km", locationManager.baseOdometerReading + locationManager.currentShiftDistance))
                            .foregroundColor(.secondary)
                    }
                }
                
                // Section 3: Action Button
                Section {
                    Button(action: {
                        locationManager.toggleManualTracking()
                    }) {
                        Text(locationManager.isCurrentlyDriving ? "End Shift" : "Start Shift")
                            .font(.headline)
                            .foregroundColor(locationManager.isCurrentlyDriving ? .red : .green)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .navigationTitle("Gig Tracker")
            // Removed inline locks so iOS can use the native Large Title that collapses when you scroll
        }
    }
}

// MARK: - Tab 2: Logbook (Native List Layout)
struct TripsListView: View {
    @Query(sort: \Trip.date, order: .reverse) var trips: [Trip]
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        NavigationStack {
            List {
                if trips.isEmpty {
                    Text("No trips logged yet.")
                        .foregroundColor(.secondary)
                }
                
                ForEach(trips) { trip in
                    NavigationLink(destination: TripDetailView(trip: trip)) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(trip.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.headline)
                                Spacer()
                                Text(String(format: "%.2f km", trip.distanceInKm))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Text(trip.tripType)
                                .font(.caption)
                                .foregroundColor(trip.tripType == "Business" ? .green : (trip.tripType == "Personal" ? .blue : .orange))
                        }
                        .padding(.vertical, 4)
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
                VStack(alignment: .leading, spacing: 5) {
                    Text("Start").font(.caption).foregroundColor(.secondary)
                    Text(trip.startAddress)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("End").font(.caption).foregroundColor(.secondary)
                    Text(trip.endAddress)
                }
                HStack {
                    Text("Distance")
                    Spacer()
                    Text(String(format: "%.2f km", trip.distanceInKm)).foregroundColor(.secondary)
                }
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
                    .listRowInsets(EdgeInsets())
                }
            }
        }
        .navigationTitle("Trip Info")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Tab 3: Reports (Native Form Layout)
struct ReportsView: View {
    @Query(sort: \Trip.date, order: .reverse) var trips: [Trip]
    @State private var csvURL: URL?
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .center, spacing: 15) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 60, height: 60)
                            .foregroundColor(.blue)
                        
                        Text("CRA Logbook Export")
                            .font(.title2).bold()
                        
                        Text("Generate a CSV spreadsheet of all your logged trips for tax purposes.")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical)
                }
                
                Section {
                    if let url = csvURL {
                        ShareLink(item: url) {
                            Label("Export CSV File", systemImage: "square.and.arrow.up")
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 5)
                        }
                    } else {
                        Button(action: generateCSV) {
                            Text("Generate Report")
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 5)
                        }
                    }
                }
            }
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
