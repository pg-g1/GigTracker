import SwiftUI
import SwiftData

@main
struct GigTrackerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(for: Trip.self)
    }
}
