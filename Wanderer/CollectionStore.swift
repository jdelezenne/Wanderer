import CoreLocation
import Foundation
import Observation
import SwiftData

struct CollectedItem: Identifiable {
    let id: String
    let name: String
    let kind: NearbyPlaceKind
    let latitude: Double
    let longitude: Double
    let address: String?
    let areaID: UUID?
    let firstDiscoveredAt: Date
    let lastDiscoveredAt: Date
    let discoveryCount: Int
}

@MainActor @Observable
final class CollectionStore {
    private(set) var items: [CollectedItem] = []

    @ObservationIgnored private let modelContext: ModelContext
    @ObservationIgnored private let persistenceStatus: PersistenceStatus

    init(modelContext: ModelContext, persistenceStatus: PersistenceStatus) {
        self.modelContext = modelContext
        self.persistenceStatus = persistenceStatus
        reload()
    }

    func collect(place: NearbyPlace, areaID: UUID? = nil) {
        do {
            let stableID = place.id
            let now = Date()
            let descriptor = FetchDescriptor<CollectedPlaceRecord>(
                predicate: #Predicate { $0.id == stableID }
            )
            if let existing = try modelContext.fetch(descriptor).first {
                existing.name = place.name
                existing.kindRawValue = place.kind.rawValue
                existing.latitude = place.coordinate.latitude
                existing.longitude = place.coordinate.longitude
                existing.address = place.address
                existing.areaID = areaID
                existing.lastDiscoveredAt = now
                existing.discoveryCount += 1
            } else {
                modelContext.insert(CollectedPlaceRecord(item: CollectedItem(
                    id: stableID,
                    name: place.name,
                    kind: place.kind,
                    latitude: place.coordinate.latitude,
                    longitude: place.coordinate.longitude,
                    address: place.address,
                    areaID: areaID,
                    firstDiscoveredAt: now,
                    lastDiscoveredAt: now,
                    discoveryCount: 1
                )))
            }
            modelContext.insert(PlaceDiscoveryRecord(placeID: stableID, discoveredAt: now, areaID: areaID))
            try modelContext.save()
            reload()
        } catch {
            modelContext.rollback()
            persistenceStatus.report(error, operation: "Saving the collected place")
        }
    }

    func isCollectedToday(_ place: NearbyPlace) -> Bool {
        guard let item = items.first(where: { $0.id == place.id }) else { return false }
        return Calendar.current.isDateInToday(item.lastDiscoveredAt)
    }

    private func reload() {
        do {
            let descriptor = FetchDescriptor<CollectedPlaceRecord>(
                sortBy: [SortDescriptor(\.lastDiscoveredAt, order: .reverse)]
            )
            items = try modelContext.fetch(descriptor).compactMap { record in
                guard let kind = NearbyPlaceKind(rawValue: record.kindRawValue) else { return nil }
                return CollectedItem(
                    id: record.id,
                    name: record.name,
                    kind: kind,
                    latitude: record.latitude,
                    longitude: record.longitude,
                    address: record.address,
                    areaID: record.areaID,
                    firstDiscoveredAt: record.firstDiscoveredAt,
                    lastDiscoveredAt: record.lastDiscoveredAt,
                    discoveryCount: record.discoveryCount
                )
            }
        } catch {
            persistenceStatus.report(error, operation: "Loading collected places")
        }
    }
}
