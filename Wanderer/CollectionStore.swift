import Foundation
import Observation

struct CollectedItem: Identifiable, Codable {
    let id: UUID
    let name: String
    let kind: NearbyPlaceKind
    let collectedDate: Date
}

@Observable
final class CollectionStore {
    private(set) var items: [CollectedItem] = []

    init() { load() }

    func collect(place: NearbyPlace) {
        items.removeAll { $0.name == place.name && $0.kind == place.kind }
        items.insert(CollectedItem(id: UUID(), name: place.name, kind: place.kind, collectedDate: Date()), at: 0)
        persist()
    }

    func isCollectedToday(name: String, kind: NearbyPlaceKind) -> Bool {
        guard let item = items.first(where: { $0.name == name && $0.kind == kind }) else { return false }
        return Calendar.current.isDateInToday(item.collectedDate)
    }

    private var storageURL: URL { URL.documentsDirectory.appendingPathComponent("collection.json") }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        items = (try? JSONDecoder().decode([CollectedItem].self, from: data)) ?? []
    }

    private func persist() {
        try? JSONEncoder().encode(items).write(to: storageURL)
    }
}
