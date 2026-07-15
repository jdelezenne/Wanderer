import CoreLocation
import Foundation

struct VisitedArea: Identifiable, Codable {
    let id: UUID
    let name: String
    let firstVisitDate: Date
    var lastVisitDate: Date
    var visitCount: Int
}

@Observable final class AreaStore {
    private(set) var areas: [VisitedArea] = []
    private(set) var currentAreaName: String?

    @ObservationIgnored private let geocoder = CLGeocoder()
    @ObservationIgnored private var lastGeocodedLocation: CLLocation?
    @ObservationIgnored private var isGeocoding = false

    private static var storageURL: URL {
        URL.documentsDirectory.appending(path: "visited_areas.json")
    }

    init() { load() }

    func maybeGeocode(_ location: CLLocation) {
        if let last = lastGeocodedLocation, location.distance(from: last) < 300 { return }
        guard !isGeocoding else { return }
        lastGeocodedLocation = location
        isGeocoding = true
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            guard let self else { return }
            self.isGeocoding = false
            guard let p = placemarks?.first,
                  let name = p.subLocality ?? p.locality, !name.isEmpty else { return }
            Task { @MainActor in self.recordVisit(to: name) }
        }
    }

    private func recordVisit(to name: String) {
        currentAreaName = name
        if let idx = areas.firstIndex(where: { $0.name == name }) {
            areas[idx].lastVisitDate = Date()
            areas[idx].visitCount += 1
        } else {
            areas.insert(VisitedArea(id: UUID(), name: name, firstVisitDate: Date(), lastVisitDate: Date(), visitCount: 1), at: 0)
        }
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.storageURL) else { return }
        areas = (try? JSONDecoder().decode([VisitedArea].self, from: data)) ?? []
    }

    private func persist() {
        try? JSONEncoder().encode(areas).write(to: Self.storageURL)
    }
}
