import Foundation
import Observation
import SwiftData

@MainActor @Observable
final class TripStore {
    private(set) var trips: [TripRecap] = []

    @ObservationIgnored private let modelContext: ModelContext
    @ObservationIgnored private let persistenceStatus: PersistenceStatus

    init(modelContext: ModelContext, persistenceStatus: PersistenceStatus) {
        self.modelContext = modelContext
        self.persistenceStatus = persistenceStatus
        reload()
    }

    @discardableResult
    func save(_ recap: TripRecap) -> Bool {
        do {
            modelContext.insert(TripRecord(recap: recap))
            for activeTrip in try modelContext.fetch(FetchDescriptor<ActiveTripRecord>()) {
                modelContext.delete(activeTrip)
            }
            try modelContext.save()
            reload()
            return true
        } catch {
            modelContext.rollback()
            persistenceStatus.report(error, operation: "Saving the trip")
            return false
        }
    }

    func delete(_ recap: TripRecap) {
        guard let record = record(id: recap.id) else { return }
        modelContext.delete(record)
        guard commit(operation: "Deleting the trip") else { return }
        reload()
    }

    func deleteAll() {
        do {
            try modelContext.delete(model: TripRecord.self)
            try modelContext.save()
            reload()
        } catch {
            persistenceStatus.report(error, operation: "Deleting trip history")
        }
    }

    func updateMeta(id: UUID, name: String, notes: String) {
        guard let record = record(id: id) else { return }
        record.name = name
        record.notes = notes
        guard commit(operation: "Updating the trip") else { return }
        reload()
    }

    func savePhotoIDs(_ ids: [String], for tripID: UUID) {
        guard let record = record(id: tripID) else { return }
        record.photoIDs = ids
        _ = commit(operation: "Saving trip photos")
    }

    func savedPhotoIDs(for tripID: UUID) -> [String] {
        record(id: tripID)?.photoIDs ?? []
    }

    private func reload() {
        do {
            let descriptor = FetchDescriptor<TripRecord>(
                sortBy: [SortDescriptor(\.startDate, order: .reverse)]
            )
            trips = try modelContext.fetch(descriptor).map(\.recap)
        } catch {
            persistenceStatus.report(error, operation: "Loading trip history")
        }
    }

    private func record(id: UUID) -> TripRecord? {
        do {
            let descriptor = FetchDescriptor<TripRecord>(predicate: #Predicate { $0.id == id })
            return try modelContext.fetch(descriptor).first
        } catch {
            persistenceStatus.report(error, operation: "Loading the trip")
            return nil
        }
    }

    private func commit(operation: String) -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            modelContext.rollback()
            persistenceStatus.report(error, operation: operation)
            return false
        }
    }
}
