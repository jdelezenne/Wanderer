import CoreLocation
import Foundation
import Observation

@Observable
final class FogStore {
    var revealedCoordinates: [CodableCoordinate] = []

    @ObservationIgnored private var lastLat: Double = .nan
    @ObservationIgnored private var lastLng: Double = .nan

    private static var storageURL: URL {
        URL.documentsDirectory.appending(path: "fog_revealed.json")
    }

    init() { load() }

    var revealedAreaKm2: Double {
        struct Cell: Hashable { let row: Int; let col: Int }
        let cellMeters = 50.0
        let latStep = cellMeters / 111_000.0
        var cells = Set<Cell>()
        for c in revealedCoordinates {
            let lngStep = cellMeters / (111_000.0 * cos(c.latitude * .pi / 180))
            cells.insert(Cell(
                row: Int((c.latitude / latStep).rounded(.down)),
                col: Int((c.longitude / lngStep).rounded(.down))
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
        lastLat = latitude
        lastLng = longitude
        revealedCoordinates.append(CodableCoordinate(latitude: latitude, longitude: longitude))
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.storageURL) else { return }
        revealedCoordinates = (try? JSONDecoder().decode([CodableCoordinate].self, from: data)) ?? []
    }

    private func persist() {
        try? JSONEncoder().encode(revealedCoordinates).write(to: Self.storageURL)
    }
}
