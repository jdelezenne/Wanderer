import CoreLocation
import Foundation
import Observation
import SwiftData

@MainActor @Observable
final class FogStore {
    private(set) var revealedCoordinates: [CodableCoordinate] = []

    @ObservationIgnored private let modelContext: ModelContext
    @ObservationIgnored private let persistenceStatus: PersistenceStatus
    @ObservationIgnored private var lastLat: Double = .nan
    @ObservationIgnored private var lastLng: Double = .nan

    init(modelContext: ModelContext, persistenceStatus: PersistenceStatus) {
        self.modelContext = modelContext
        self.persistenceStatus = persistenceStatus
        reload()
        if let last = revealedCoordinates.last {
            lastLat = last.latitude
            lastLng = last.longitude
        }
    }

    var revealedAreaKm2: Double {
        struct Cell: Hashable { let row: Int; let col: Int }
        let cellMeters = 50.0
        let latStep = cellMeters / 111_000.0
        var cells = Set<Cell>()
        for coordinate in revealedCoordinates {
            let lngStep = cellMeters / (111_000.0 * cos(coordinate.latitude * .pi / 180))
            cells.insert(Cell(
                row: Int((coordinate.latitude / latStep).rounded(.down)),
                col: Int((coordinate.longitude / lngStep).rounded(.down))
            ))
        }
        return Double(cells.count) * cellMeters * cellMeters / 1_000_000
    }

    func reveal(latitude: Double, longitude: Double) {
        if !lastLat.isNaN {
            let dlat = (latitude - lastLat) * 111_000
            let dlng = (longitude - lastLng) * 111_000 * cos(lastLat * .pi / 180)
            guard dlat * dlat + dlng * dlng > 40 * 40 else { return }
        }

        let record = FogPointRecord(latitude: latitude, longitude: longitude)
        modelContext.insert(record)
        do {
            try modelContext.save()
            lastLat = latitude
            lastLng = longitude
            revealedCoordinates.append(CodableCoordinate(latitude: latitude, longitude: longitude))
        } catch {
            modelContext.rollback()
            persistenceStatus.report(error, operation: "Saving explored map progress")
        }
    }

    private func reload() {
        do {
            revealedCoordinates = try modelContext.fetch(FetchDescriptor<FogPointRecord>()).map {
                CodableCoordinate(latitude: $0.latitude, longitude: $0.longitude)
            }
        } catch {
            persistenceStatus.report(error, operation: "Loading explored map progress")
        }
    }
}
