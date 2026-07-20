import CoreLocation
import MapKit
import SwiftUI

struct CodableCoordinate: Codable, Hashable {
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

struct CodableLocationSample: Codable, Hashable {
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    let horizontalAccuracy: Double
    let speed: Double

    init(_ location: CLLocation) {
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        timestamp = location.timestamp
        horizontalAccuracy = location.horizontalAccuracy
        speed = location.speed
    }

    var location: CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: 0,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: -1,
            course: -1,
            speed: speed,
            timestamp: timestamp
        )
    }

    var coordinate: CLLocationCoordinate2D { location.coordinate }
}

struct TripRecap: Identifiable {
    let id: UUID
    let startDate: Date
    let steps: Int
    let distanceMeters: Double
    let elapsedSeconds: TimeInterval
    let averageSpeedMetersPerSecond: Double
    let gpsDistanceMeters: Double
    let pedometerDistanceMeters: Double?
    var name: String
    var notes: String
    private let coordinateData: [CodableCoordinate]
    private let locationSamples: [CodableLocationSample]

    var codableCoordinates: [CodableCoordinate] { coordinateData }
    var codableLocationSamples: [CodableLocationSample] { locationSamples }

    var coordinates: [CLLocationCoordinate2D] {
        coordinateData.map(\.asCLLocationCoordinate2D)
    }

    @MainActor
    init(
        startDate: Date,
        steps: Int,
        distanceMeters: Double,
        elapsedSeconds: TimeInterval,
        averageSpeedMetersPerSecond: Double,
        coordinates: [CLLocationCoordinate2D],
        locationSamples: [CodableLocationSample] = [],
        gpsDistanceMeters: Double = 0,
        pedometerDistanceMeters: Double? = nil,
        name: String = "",
        notes: String = ""
    ) {
        id = UUID()
        self.startDate = startDate
        self.steps = steps
        self.distanceMeters = distanceMeters
        self.elapsedSeconds = elapsedSeconds
        self.averageSpeedMetersPerSecond = averageSpeedMetersPerSecond
        self.gpsDistanceMeters = gpsDistanceMeters
        self.pedometerDistanceMeters = pedometerDistanceMeters
        self.name = name
        self.notes = notes
        coordinateData = coordinates.map(CodableCoordinate.init)
        self.locationSamples = locationSamples
    }

    init(
        id: UUID,
        startDate: Date,
        steps: Int,
        distanceMeters: Double,
        elapsedSeconds: TimeInterval,
        averageSpeedMetersPerSecond: Double,
        coordinates: [CodableCoordinate],
        locationSamples: [CodableLocationSample],
        gpsDistanceMeters: Double,
        pedometerDistanceMeters: Double?,
        name: String,
        notes: String
    ) {
        self.id = id
        self.startDate = startDate
        self.steps = steps
        self.distanceMeters = distanceMeters
        self.elapsedSeconds = elapsedSeconds
        self.averageSpeedMetersPerSecond = averageSpeedMetersPerSecond
        self.gpsDistanceMeters = gpsDistanceMeters
        self.pedometerDistanceMeters = pedometerDistanceMeters
        self.name = name
        self.notes = notes
        coordinateData = coordinates
        self.locationSamples = locationSamples
    }

    var pathPointCount: Int { coordinateData.count }

    var accuracySummary: String {
        guard !locationSamples.isEmpty else { return "Limited GPS data" }
        let averageAccuracy = locationSamples.map(\.horizontalAccuracy).reduce(0, +) / Double(locationSamples.count)
        if averageAccuracy <= 10, pedometerDistanceMeters != nil { return "High confidence · GPS + motion" }
        if averageAccuracy <= 25 { return "Good confidence · GPS" }
        return "Low confidence · weak GPS"
    }

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
