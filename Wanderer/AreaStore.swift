import CoreLocation
import Foundation
import SwiftData

struct AreaVisit: Identifiable, Codable {
    let id: UUID
    let enteredAt: Date
    var lastSeenAt: Date
    var exitedAt: Date?
}

struct VisitedArea: Identifiable, Codable {
    let id: UUID
    var key: String
    var name: String
    var visits: [AreaVisit]

    var firstVisitDate: Date {
        visits.map(\.enteredAt).min() ?? .distantPast
    }

    var lastVisitDate: Date {
        visits.map(\.lastSeenAt).max() ?? .distantPast
    }

    var visitCount: Int { visits.count }
}

@MainActor @Observable final class AreaStore {
    private(set) var areas: [VisitedArea] = []
    private(set) var currentAreaName: String?
    var currentAreaID: UUID? { activeVisit?.areaID }

    @ObservationIgnored private let geocoder = CLGeocoder()
    @ObservationIgnored private let modelContext: ModelContext
    @ObservationIgnored private let persistenceStatus: PersistenceStatus
    @ObservationIgnored private var lastGeocodedLocation: CLLocation?
    @ObservationIgnored private var lastPersistDate = Date.distantPast
    @ObservationIgnored private var activeVisit: ActiveVisit?
    @ObservationIgnored private var candidateArea: CandidateArea?
    @ObservationIgnored private var isGeocoding = false

    private static let minimumGeocodeDistance: CLLocationDistance = 100
    private static let candidateConfirmationDelay: TimeInterval = 30
    private static let maximumUsefulAccuracy: CLLocationAccuracy = 200
    private static let persistenceInterval: TimeInterval = 60

    init(modelContext: ModelContext, persistenceStatus: PersistenceStatus) {
        self.modelContext = modelContext
        self.persistenceStatus = persistenceStatus
        load()
    }

    func maybeGeocode(_ location: CLLocation) {
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= Self.maximumUsefulAccuracy,
              abs(location.timestamp.timeIntervalSinceNow) < 120,
              !isGeocoding else { return }

        if let lastLocation = lastGeocodedLocation {
            let distance = location.distance(from: lastLocation)
            let candidateHasAged = candidateArea.map {
                Date().timeIntervalSince($0.firstObservedAt) >= Self.candidateConfirmationDelay
            } ?? false
            if distance < Self.minimumGeocodeDistance && !candidateHasAged { return }
        }

        lastGeocodedLocation = location
        isGeocoding = true

        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            Task { @MainActor in
                guard let self else { return }
                self.isGeocoding = false
                guard let placemark = placemarks?.first,
                      let resolution = AreaResolution(placemark: placemark) else { return }
                self.observe(resolution, at: location.timestamp)
            }
        }
    }

    private func observe(_ resolution: AreaResolution, at date: Date) {
        if let activeVisit,
           let areaIndex = areas.firstIndex(where: { $0.id == activeVisit.areaID }),
           resolution.matches(areas[areaIndex]) {
            candidateArea = nil
            currentAreaName = resolution.name
            areas[areaIndex].key = resolution.key
            areas[areaIndex].name = resolution.name
            updateLastSeen(areaIndex: areaIndex, visitID: activeVisit.visitID, at: date)
            persistIfNeeded()
            return
        }

        guard activeVisit != nil else {
            enter(resolution, at: date)
            return
        }

        if candidateArea?.resolution.key == resolution.key {
            candidateArea?.observations += 1
        } else {
            candidateArea = CandidateArea(
                resolution: resolution,
                firstObservedAt: date,
                observations: 1
            )
        }

        guard let candidateArea,
              candidateArea.observations >= 2,
              date.timeIntervalSince(candidateArea.firstObservedAt) >= Self.candidateConfirmationDelay
                || candidateArea.observations >= 3 else { return }

        enter(candidateArea.resolution, at: candidateArea.firstObservedAt)
    }

    private func enter(_ resolution: AreaResolution, at date: Date) {
        closeActiveVisit(at: date)

        let visit = AreaVisit(id: UUID(), enteredAt: date, lastSeenAt: date, exitedAt: nil)
        let areaID: UUID

        if let areaIndex = areas.firstIndex(where: { resolution.matches($0) }) {
            areas[areaIndex].key = resolution.key
            areas[areaIndex].name = resolution.name
            areas[areaIndex].visits.append(visit)
            areaID = areas[areaIndex].id
        } else {
            let area = VisitedArea(id: UUID(), key: resolution.key, name: resolution.name, visits: [visit])
            areas.insert(area, at: 0)
            areaID = area.id
        }

        activeVisit = ActiveVisit(areaID: areaID, visitID: visit.id)
        candidateArea = nil
        currentAreaName = resolution.name
        persist()
    }

    private func closeActiveVisit(at date: Date) {
        guard let activeVisit,
              let areaIndex = areas.firstIndex(where: { $0.id == activeVisit.areaID }),
              let visitIndex = areas[areaIndex].visits.firstIndex(where: { $0.id == activeVisit.visitID })
        else { return }

        areas[areaIndex].visits[visitIndex].lastSeenAt = max(
            areas[areaIndex].visits[visitIndex].lastSeenAt,
            date
        )
        areas[areaIndex].visits[visitIndex].exitedAt = date
    }

    private func updateLastSeen(areaIndex: Int, visitID: UUID, at date: Date) {
        guard let visitIndex = areas[areaIndex].visits.firstIndex(where: { $0.id == visitID }) else { return }
        areas[areaIndex].visits[visitIndex].lastSeenAt = max(
            areas[areaIndex].visits[visitIndex].lastSeenAt,
            date
        )
    }

    private func load() {
        do {
            let areaRecords = try modelContext.fetch(FetchDescriptor<AreaRecord>())
            let visitRecords = try modelContext.fetch(FetchDescriptor<AreaVisitRecord>())
            areas = areaRecords.compactMap { areaRecord in
                let visits = visitRecords
                    .filter { $0.areaID == areaRecord.id }
                    .map {
                        AreaVisit(
                            id: $0.id,
                            enteredAt: $0.enteredAt,
                            lastSeenAt: $0.lastSeenAt,
                            exitedAt: $0.exitedAt
                        )
                    }
                guard !visits.isEmpty else { return nil }
                return VisitedArea(id: areaRecord.id, key: areaRecord.key, name: areaRecord.name, visits: visits)
            }

            if let saved = try modelContext.fetch(FetchDescriptor<ActiveAreaRecord>()).first,
               areas.contains(where: { area in
                   area.id == saved.areaID && area.visits.contains(where: { $0.id == saved.visitID })
               }) {
                activeVisit = ActiveVisit(areaID: saved.areaID, visitID: saved.visitID)
                currentAreaName = areas.first(where: { $0.id == saved.areaID })?.name
            }
        } catch {
            persistenceStatus.report(error, operation: "Loading visited areas")
        }
    }

    private func persistIfNeeded() {
        guard Date().timeIntervalSince(lastPersistDate) >= Self.persistenceInterval else { return }
        persist()
    }

    private func persist() {
        do {
            let storedAreas = try modelContext.fetch(FetchDescriptor<AreaRecord>())
            let storedVisits = try modelContext.fetch(FetchDescriptor<AreaVisitRecord>())

            for area in areas {
                let areaRecord: AreaRecord
                if let existing = storedAreas.first(where: { $0.id == area.id }) {
                    areaRecord = existing
                    areaRecord.key = area.key
                    areaRecord.name = area.name
                } else {
                    areaRecord = AreaRecord(id: area.id, key: area.key, name: area.name)
                    modelContext.insert(areaRecord)
                }

                for visit in area.visits {
                    if let existing = storedVisits.first(where: { $0.id == visit.id }) {
                        existing.lastSeenAt = visit.lastSeenAt
                        existing.exitedAt = visit.exitedAt
                    } else {
                        modelContext.insert(AreaVisitRecord(
                            id: visit.id,
                            areaID: area.id,
                            enteredAt: visit.enteredAt,
                            lastSeenAt: visit.lastSeenAt,
                            exitedAt: visit.exitedAt
                        ))
                    }
                }
            }

            let storedActiveAreas = try modelContext.fetch(FetchDescriptor<ActiveAreaRecord>())
            if let activeVisit {
                if let saved = storedActiveAreas.first {
                    saved.areaID = activeVisit.areaID
                    saved.visitID = activeVisit.visitID
                } else {
                    modelContext.insert(ActiveAreaRecord(areaID: activeVisit.areaID, visitID: activeVisit.visitID))
                }
            } else {
                storedActiveAreas.forEach(modelContext.delete)
            }

            try modelContext.save()
            lastPersistDate = Date()
        } catch {
            modelContext.rollback()
            persistenceStatus.report(error, operation: "Saving visited areas")
            load()
        }
    }
}

private struct ActiveVisit: Codable {
    let areaID: UUID
    let visitID: UUID
}

private struct CandidateArea {
    let resolution: AreaResolution
    let firstObservedAt: Date
    var observations: Int
}

private struct AreaResolution {
    let key: String
    let name: String

    init?(placemark: CLPlacemark) {
        guard let name = placemark.subLocality ?? placemark.locality ?? placemark.administrativeArea,
              !name.isEmpty else { return nil }

        self.name = name
        key = [
            placemark.isoCountryCode,
            placemark.administrativeArea,
            placemark.locality,
            placemark.subLocality ?? placemark.locality ?? placemark.administrativeArea
        ]
        .compactMap { $0?.normalizedAreaComponent }
        .joined(separator: "|")
    }

    func matches(_ area: VisitedArea) -> Bool {
        area.key == key
    }
}

private extension String {
    var normalizedAreaComponent: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
