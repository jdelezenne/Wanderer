import CoreLocation
import MapKit
import SwiftUI

struct CodableCoordinate: Codable {
    let latitude: Double
    let longitude: Double

    init(_ coordinate: CLLocationCoordinate2D) {
        latitude = coordinate.latitude
        longitude = coordinate.longitude
    }

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    var asCLLocationCoordinate2D: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct TripRecap: Identifiable, Codable {
    let id: UUID
    let startDate: Date
    let steps: Int
    let distanceMeters: Double
    let elapsedSeconds: TimeInterval
    let averageSpeedMetersPerSecond: Double
    var name: String
    var notes: String
    private let coordinateData: [CodableCoordinate]

    var coordinates: [CLLocationCoordinate2D] {
        coordinateData.map(\.asCLLocationCoordinate2D)
    }

    enum CodingKeys: String, CodingKey {
        case id, startDate, steps, distanceMeters, elapsedSeconds,
             averageSpeedMetersPerSecond, name, notes, coordinateData
    }

    // Custom decode so existing saved trips (without name/notes) still load fine.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        startDate = try c.decode(Date.self, forKey: .startDate)
        steps = try c.decode(Int.self, forKey: .steps)
        distanceMeters = try c.decode(Double.self, forKey: .distanceMeters)
        elapsedSeconds = try c.decode(TimeInterval.self, forKey: .elapsedSeconds)
        averageSpeedMetersPerSecond = try c.decode(Double.self, forKey: .averageSpeedMetersPerSecond)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        notes = (try? c.decodeIfPresent(String.self, forKey: .notes)) ?? ""
        coordinateData = try c.decode([CodableCoordinate].self, forKey: .coordinateData)
    }

    @MainActor
    init(
        startDate: Date,
        steps: Int,
        distanceMeters: Double,
        elapsedSeconds: TimeInterval,
        averageSpeedMetersPerSecond: Double,
        coordinates: [CLLocationCoordinate2D],
        name: String = "",
        notes: String = ""
    ) {
        id = UUID()
        self.startDate = startDate
        self.steps = steps
        self.distanceMeters = distanceMeters
        self.elapsedSeconds = elapsedSeconds
        self.averageSpeedMetersPerSecond = averageSpeedMetersPerSecond
        self.name = name
        self.notes = notes
        coordinateData = coordinates.map(CodableCoordinate.init)
    }

    var pathPointCount: Int { coordinateData.count }

    var formattedDate: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(startDate) {
            return "Today, \(startDate.formatted(date: .omitted, time: .shortened))"
        } else if calendar.isDateInYesterday(startDate) {
            return "Yesterday, \(startDate.formatted(date: .omitted, time: .shortened))"
        }
        return startDate.formatted(date: .abbreviated, time: .shortened)
    }

    var formattedDistance: String     { Formatters.distance(distanceMeters) }
    var formattedDuration: String     { Formatters.duration(elapsedSeconds) }
    var formattedAverageSpeed: String { Formatters.speed(averageSpeedMetersPerSecond) }

    var mapCameraPosition: MapCameraPosition {
        guard let first = coordinates.first else { return .automatic }

        var minLat = first.latitude,  maxLat = first.latitude
        var minLng = first.longitude, maxLng = first.longitude

        for c in coordinates {
            minLat = min(minLat, c.latitude);  maxLat = max(maxLat, c.latitude)
            minLng = min(minLng, c.longitude); maxLng = max(maxLng, c.longitude)
        }

        return .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * 1.6, 0.005),
                longitudeDelta: max((maxLng - minLng) * 1.6, 0.005)
            )
        ))
    }
}
