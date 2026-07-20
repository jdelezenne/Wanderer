import Foundation
import Observation
import SwiftData

@Model
final class TripRecord {
    @Attribute(.unique) var id: UUID
    var startDate: Date
    var steps: Int
    var distanceMeters: Double
    var elapsedSeconds: TimeInterval
    var averageSpeedMetersPerSecond: Double
    var gpsDistanceMeters: Double
    var pedometerDistanceMeters: Double?
    var name: String
    var notes: String
    var coordinates: [CodableCoordinate]
    var locationSamples: [CodableLocationSample]
    var photoIDs: [String]

    init(recap: TripRecap) {
        id = recap.id
        startDate = recap.startDate
        steps = recap.steps
        distanceMeters = recap.distanceMeters
        elapsedSeconds = recap.elapsedSeconds
        averageSpeedMetersPerSecond = recap.averageSpeedMetersPerSecond
        gpsDistanceMeters = recap.gpsDistanceMeters
        pedometerDistanceMeters = recap.pedometerDistanceMeters
        name = recap.name
        notes = recap.notes
        coordinates = recap.codableCoordinates
        locationSamples = recap.codableLocationSamples
        photoIDs = []
    }

    var recap: TripRecap {
        TripRecap(
            id: id,
            startDate: startDate,
            steps: steps,
            distanceMeters: distanceMeters,
            elapsedSeconds: elapsedSeconds,
            averageSpeedMetersPerSecond: averageSpeedMetersPerSecond,
            coordinates: coordinates,
            locationSamples: locationSamples,
            gpsDistanceMeters: gpsDistanceMeters,
            pedometerDistanceMeters: pedometerDistanceMeters,
            name: name,
            notes: notes
        )
    }
}

@Model
final class ActiveTripRecord {
    @Attribute(.unique) var id: String
    var startDate: Date
    var stepCount: Int
    var distanceMeters: Double
    var gpsDistanceMeters: Double
    var pedometerDistanceMeters: Double?
    var elapsedSeconds: TimeInterval
    var isManuallyPaused: Bool
    var isSpeedPaused: Bool
    var manualPauseStartDate: Date?
    var totalPausedSeconds: TimeInterval
    var coordinates: [CodableCoordinate]
    var locationSamples: [CodableLocationSample]
    var updatedAt: Date

    init(startDate: Date) {
        id = "active-trip"
        self.startDate = startDate
        stepCount = 0
        distanceMeters = 0
        gpsDistanceMeters = 0
        pedometerDistanceMeters = nil
        elapsedSeconds = 0
        isManuallyPaused = false
        isSpeedPaused = false
        totalPausedSeconds = 0
        coordinates = []
        locationSamples = []
        updatedAt = Date()
    }
}

@Model
final class CollectedPlaceRecord {
    @Attribute(.unique) var id: String
    var name: String
    var kindRawValue: String
    var latitude: Double
    var longitude: Double
    var address: String?
    var areaID: UUID?
    var firstDiscoveredAt: Date
    var lastDiscoveredAt: Date
    var discoveryCount: Int

    init(item: CollectedItem) {
        id = item.id
        name = item.name
        kindRawValue = item.kind.rawValue
        latitude = item.latitude
        longitude = item.longitude
        address = item.address
        areaID = item.areaID
        firstDiscoveredAt = item.firstDiscoveredAt
        lastDiscoveredAt = item.lastDiscoveredAt
        discoveryCount = item.discoveryCount
    }
}

@Model
final class PlaceDiscoveryRecord {
    @Attribute(.unique) var id: UUID
    var placeID: String
    var discoveredAt: Date
    var areaID: UUID?

    init(placeID: String, discoveredAt: Date, areaID: UUID?) {
        id = UUID()
        self.placeID = placeID
        self.discoveredAt = discoveredAt
        self.areaID = areaID
    }
}

@Model
final class FogPointRecord {
    @Attribute(.unique) var id: UUID
    var latitude: Double
    var longitude: Double

    init(latitude: Double, longitude: Double) {
        id = UUID()
        self.latitude = latitude
        self.longitude = longitude
    }
}

@Model
final class AreaRecord {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var key: String
    var name: String

    init(id: UUID = UUID(), key: String, name: String) {
        self.id = id
        self.key = key
        self.name = name
    }
}

@Model
final class AreaVisitRecord {
    @Attribute(.unique) var id: UUID
    var areaID: UUID
    var enteredAt: Date
    var lastSeenAt: Date
    var exitedAt: Date?

    init(id: UUID = UUID(), areaID: UUID, enteredAt: Date, lastSeenAt: Date, exitedAt: Date? = nil) {
        self.id = id
        self.areaID = areaID
        self.enteredAt = enteredAt
        self.lastSeenAt = lastSeenAt
        self.exitedAt = exitedAt
    }
}

@Model
final class ActiveAreaRecord {
    @Attribute(.unique) var id: String
    var areaID: UUID
    var visitID: UUID

    init(areaID: UUID, visitID: UUID) {
        id = "active-area"
        self.areaID = areaID
        self.visitID = visitID
    }
}

struct PersistenceProblem: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

@MainActor @Observable
final class PersistenceStatus {
    var problem: PersistenceProblem?

    func report(_ error: Error, operation: String) {
        problem = PersistenceProblem(
            title: "Couldn’t Save Data",
            message: "\(operation) failed. Your latest change may not have been saved.\n\n\(error.localizedDescription)"
        )
    }
}

enum WandererPersistence {
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([
            TripRecord.self,
            ActiveTripRecord.self,
            CollectedPlaceRecord.self,
            PlaceDiscoveryRecord.self,
            FogPointRecord.self,
            AreaRecord.self,
            AreaVisitRecord.self,
            ActiveAreaRecord.self
        ])
        return try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        )
    }
}
