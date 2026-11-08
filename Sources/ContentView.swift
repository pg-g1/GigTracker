        .onAppear {
            locationManager.requestPermissions()
            locationManager.onTripFinished = { distance, date, route in
                
                // Only save trips longer than 10 meters to avoid saving parking lot drift
                guard distance > 0.01 else { return }
                
                let codableRoute = route.map { CodableCoordinate($0) }
                let routeData = try? JSONEncoder().encode(codableRoute)
                
                let newTrip = Trip(
                    date: date, 
                    distanceInKm: distance, 
                    startAddress: "Pending Translation", 
                    endAddress: "Pending Translation", 
                    tripType: "Unclassified", 
                    routeData: routeData
                )
                modelContext.insert(newTrip)
            }
        }
