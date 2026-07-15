import ActivityKit
import Foundation

/// Shared between the main app (starts/updates the activity) and the widget extension (renders it).
struct TripActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var stepCount: Int
        var elapsedSeconds: TimeInterval
        var distanceMeters: Double
        var isPaused: Bool
    }

    let startDate: Date
}
