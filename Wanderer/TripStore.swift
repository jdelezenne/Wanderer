import Foundation
import Observation

@Observable
final class TripStore {
    private(set) var trips: [TripRecap] = []
    // UUID string → photo local identifiers (saved after first recap view)
    private(set) var tripPhotoIDs: [String: [String]] = [:]

    private static var tripsURL: URL {
        URL.documentsDirectory.appending(path: "trip_history.json")
    }
    private static var photoIDsURL: URL {
        URL.documentsDirectory.appending(path: "trip_photo_ids.json")
    }

    init() {
        load()
        loadPhotoIDs()
    }

    func save(_ recap: TripRecap) {
        trips.insert(recap, at: 0)
        persist()
    }

    func delete(_ recap: TripRecap) {
        trips.removeAll { $0.id == recap.id }
        tripPhotoIDs.removeValue(forKey: recap.id.uuidString)
        persist()
        persistPhotoIDs()
    }

    func deleteAll() {
        trips.removeAll()
        tripPhotoIDs.removeAll()
        persist()
        persistPhotoIDs()
    }

    func updateMeta(id: UUID, name: String, notes: String) {
        guard let idx = trips.firstIndex(where: { $0.id == id }) else { return }
        trips[idx].name = name
        trips[idx].notes = notes
        persist()
    }

    func savePhotoIDs(_ ids: [String], for tripID: UUID) {
        tripPhotoIDs[tripID.uuidString] = ids
        persistPhotoIDs()
    }

    func savedPhotoIDs(for tripID: UUID) -> [String] {
        tripPhotoIDs[tripID.uuidString] ?? []
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.tripsURL) else { return }
        trips = (try? JSONDecoder().decode([TripRecap].self, from: data)) ?? []
    }

    private func persist() {
        try? JSONEncoder().encode(trips).write(to: Self.tripsURL)
    }

    private func loadPhotoIDs() {
        guard let data = try? Data(contentsOf: Self.photoIDsURL) else { return }
        tripPhotoIDs = (try? JSONDecoder().decode([String: [String]].self, from: data)) ?? [:]
    }

    private func persistPhotoIDs() {
        try? JSONEncoder().encode(tripPhotoIDs).write(to: Self.photoIDsURL)
    }
}
