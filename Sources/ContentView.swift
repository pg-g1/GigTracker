import SwiftUI
import SwiftData
import MapKit

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
                // Fixed: Allows short test blocks to save immediately without filtering out small distances
                let codableRoute = route.map { CodableCoordinate($0) }
                let routeData = try? JSONEncoder().encode(codableRoute)
                
                let newTrip = Trip(date: date, distanceInKm: distance, startAddress: start, endAddress: end, tripType: "Unclassified", routeData: routeData)
                modelContext.insert(newTrip)
            }
        }
    }
}

struct DashboardView: View {
    @ObservedObject var locationManager: LocationManager
    @State private var odometerInput: String = ""
    @FocusState private var isKeyboardFocused: Bool
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Map(coordinateRegion: $locationManager.region, showsUserLocation: true)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal)
                        .padding(.top, 8)
                    
                    VStack(spacing: 14) {
                        HStack {
                            Text("Shift Distance")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(String(format: "%.2f km", locationManager.currentShiftDistance))
                                .font(.headline)
                        }
                        
                        Divider()
                        
                        HStack {
                            Text("Base Odometer")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            TextField("e.g. 81126.23", text: $odometerInput)
                                .keyboardType(.decimalPad) // Supports decimals like .23
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 130)
                                .focused($isKeyboardFocused)
                            
                            Button("Set") {
                                if let val = Double(odometerInput) {
                                    locationManager.saveBaseOdometer(reading: val)
                                    odometerInput = ""
                                    isKeyboardFocused = false
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                        
                        Divider()
                        
                        HStack {
                            Text("Current Odometer")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(String(format: "%.2f km", locationManager.baseOdometerReading + locationManager.currentShiftDistance))
                                .font(.headline)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(16)
                    .padding(.horizontal)
                    
                    Button(action: {
                        locationManager.toggleManualTracking()
                    }) {
                        Text(locationManager.isCurrentlyDriving ? "End Shift" : "Start Shift")
                            .font(.title3.bold())
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(locationManager.isCurrentlyDriving ? Color.red : Color.green)
                            .cornerRadius(16)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Gig Tracker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isKeyboardFocused = false
                    }
                }
            }
        }
    }
}

struct TripsListView: View {
    @Query(sort: \Trip.date, order: .reverse) var trips: [Trip]
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        NavigationStack {
            List {
                if trips.isEmpty {
                    ContentUnavailableView("No Trips Logged", systemImage: "map", description: Text("Completed shifts will appear here automatically for CRA tax classification."))
                        .listRowBackground(Color.clear)
                }
                
                ForEach(trips) { trip in
                    NavigationLink(destination: TripDetailView(trip: trip)) {
                        VStack(alignment: .leading, spacing: 6) {
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
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(trip.tripType == "Business" ? Color.green.opacity(0.2) : (trip.tripType == "Personal" ? Color.blue.opacity(0.2) : Color.orange.opacity(0.2)))
                                .foregroundColor(trip.tripType == "Business" ? .green : (trip.tripType == "Personal" ? .blue : .orange))
                                .cornerRadius(6)
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
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

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
                VStack(alignment: .leading, spacing: 4) {
                    Text("Start Address").font(.caption).foregroundColor(.secondary)
                    Text(trip.startAddress).font(.subheadline)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("End Address").font(.caption).foregroundColor(.secondary)
                    Text(trip.endAddress).font(.subheadline)
                }
                HStack {
                    Text("Total Distance")
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

struct ReportsView: View {
    @Query(sort: \Trip.date, order: .reverse) var trips: [Trip]
    @State private var csvURL: URL?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 70, height: 70)
                        .foregroundColor(.blue)
                        .padding(.top, 40)
                    
                    Text("CRA Logbook Export")
                        .font(.title2).bold()
                    
                    Text("Generate a CSV spreadsheet of all your logged trips structured for Canadian tax actual expense filing.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                        .padding(.horizontal, 24)
                    
                    if let url = csvURL {
                        ShareLink(item: url) {
                            Label("Export CSV File", systemImage: "square.and.arrow.up")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .cornerRadius(16)
                        }
                        .padding(.horizontal, 24)
                    } else {
                        Button(action: generateCSV) {
                            Text("Generate Report")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .cornerRadius(16)
                        }
                        .padding(.horizontal, 24)
                    }
                }
            }
            .navigationTitle("Reports")
            .navigationBarTitleDisplayMode(.inline)
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
