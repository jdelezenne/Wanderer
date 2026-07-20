import ActivityKit
import CoreLocation
import CoreMotion
import Foundation
import Observation
import SwiftData

@Observable
final class ExplorationSession: NSObject, CLLocationManagerDelegate {
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var currentLocation: CLLocation?
    var routeCoordinates: [CLLocationCoordinate2D] = []
    var isTrackingTrip = false
    var isSpeedPaused = false
    var isManuallyPaused = false
    var stepCount = 0
    var distanceMeters = 0.0
    var gpsDistanceMeters = 0.0
    var pedometerDistanceMeters: Double?
    var elapsedSeconds: TimeInterval = 0
    var nearbyPlaces: [NearbyPlace] = []
    var statusText = "Finding your location"

    @ObservationIgnored private let locationManager = CLLocationManager()
    @ObservationIgnored private let pedometer = CMPedometer()
    @ObservationIgnored private let modelContext: ModelContext
    @ObservationIgnored private let persistenceStatus: PersistenceStatus
    @ObservationIgnored private var backgroundActivitySession: CLBackgroundActivitySession?
    @ObservationIgnored private var locationServiceSession: CLServiceSession?
    @ObservationIgnored private var trackingStartDate: Date?
    @ObservationIgnored private var nearbyPlaceSearchLocation: CLLocation?
    @ObservationIgnored private var isSearchingNearbyPlaces = false
    @ObservationIgnored private var manualPauseStartDate: Date?
    @ObservationIgnored private var totalPausedSeconds: TimeInterval = 0
    @ObservationIgnored private var liveActivity: Activity<TripActivityAttributes>?
    @ObservationIgnored private var activeTripRecord: ActiveTripRecord?
    @ObservationIgnored private var lastCheckpointDate = Date.distantPast
    @ObservationIgnored private var trackingResourcesStarted = false
    @ObservationIgnored private var locationSamples: [CodableLocationSample] = []
    @ObservationIgnored private var fastSampleCount = 0
    @ObservationIgnored private var walkingSampleCount = 0

    var formattedDistance: String        { Formatters.distance(distanceMeters) }
    var formattedAverageSpeed: String    { Formatters.speed(averageSpeedMetersPerSecond) }
    var formattedElapsedTime: String     { Formatters.duration(elapsedSeconds) }

    var averageSpeedMetersPerSecond: Double {
        guard elapsedSeconds > 0 else { return 0 }
        return distanceMeters / elapsedSeconds
    }

    init(modelContext: ModelContext, persistenceStatus: PersistenceStatus) {
        self.modelContext = modelContext
        self.persistenceStatus = persistenceStatus
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 8
        locationManager.activityType = .fitness
        locationManager.pausesLocationUpdatesAutomatically = true
        locationManager.showsBackgroundLocationIndicator = false
        authorizationStatus = locationManager.authorizationStatus
        restoreActiveTrip()
    }

    func prepareLocation() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            statusText = "Location permission needed"
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            statusText = isTrackingTrip ? "Tracking your trip" : "Map centered on you"
            applyLocationPolicyForCurrentState()
            locationManager.startUpdatingLocation()
            if isTrackingTrip { startTrackingResourcesIfNeeded() }
        case .denied, .restricted:
            statusText = "Location unavailable"
        @unknown default:
            statusText = "Location status unknown"
        }
    }

    @discardableResult
    @MainActor
    func toggleTripTracking() -> TripRecap? {
        if isTrackingTrip { return stopTripTracking() }
        startTripTracking()
        return nil
    }

    func toggleManualPause() {
        if isManuallyPaused {
            if let pauseStart = manualPauseStartDate {
                totalPausedSeconds += Date().timeIntervalSince(pauseStart)
                manualPauseStartDate = nil
            }
            isManuallyPaused = false
            statusText = "Tracking your trip"
        } else {
            manualPauseStartDate = Date()
            isManuallyPaused = true
            statusText = "Paused"
        }
        checkpointActiveTrip(force: true)
    }

    func refreshElapsedTime() {
        guard isTrackingTrip, let trackingStartDate else { return }
        let raw = Date().timeIntervalSince(trackingStartDate)
        let currentPause = isManuallyPaused
            ? (manualPauseStartDate.map { Date().timeIntervalSince($0) } ?? 0)
            : 0
        elapsedSeconds = max(0, raw - totalPausedSeconds - currentPause)
        checkpointActiveTrip()
        Task { await updateLiveActivity() }
    }

    func refreshNearbyPlaces() {
        guard let currentLocation, !isSearchingNearbyPlaces else { return }
        let coordinate = currentLocation.coordinate
        let searchLocation = currentLocation
        isSearchingNearbyPlaces = true

        Task {
            let places = await NearbyPlaceSearch.search(near: coordinate)
            await MainActor.run {
                nearbyPlaceSearchLocation = searchLocation
                isSearchingNearbyPlaces = false
                nearbyPlaces = places
                if let latest = self.currentLocation, latest.distance(from: searchLocation) > 150 {
                    self.refreshNearbyPlaces()
                }
            }
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        prepareLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newestLocation = locations.last(where: isUsableLocation) else { return }

        currentLocation = newestLocation
        refreshNearbyPlacesIfNeeded(from: newestLocation)

        guard isTrackingTrip else {
            statusText = "Map centered on you"
            return
        }

        updateAutomaticPause(using: newestLocation)

        if newestLocation.speed > 6 {
            statusText = "Moving too fast — checking"
            checkpointActiveTrip()
            return
        }

        if isSpeedPaused {
            statusText = "Moving too fast — paused"
            return
        }

        if isManuallyPaused { return }

        statusText = "Tracking your trip"
        for location in locations where isUsableLocation(location) {
            appendRoutePointIfNeeded(location)
        }
        checkpointActiveTrip()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        statusText = "Location update failed"
    }

    // MARK: - Private

    private func startTripTracking() {
        isTrackingTrip = true
        isManuallyPaused = false
        manualPauseStartDate = nil
        totalPausedSeconds = 0
        stepCount = 0
        distanceMeters = 0
        gpsDistanceMeters = 0
        pedometerDistanceMeters = nil
        elapsedSeconds = 0
        routeCoordinates = currentLocation.map { [$0.coordinate] } ?? []
        locationSamples = currentLocation.map { [CodableLocationSample($0)] } ?? []
        trackingStartDate = Date()
        statusText = "Tracking your trip"
        createActiveTripRecord()
        prepareLocation()
    }

    @MainActor
    private func stopTripTracking() -> TripRecap {
        // Finalize any in-progress manual pause so its duration is counted.
        if isManuallyPaused, let pauseStart = manualPauseStartDate {
            totalPausedSeconds += Date().timeIntervalSince(pauseStart)
            manualPauseStartDate = nil
            isManuallyPaused = false
        }
        refreshElapsedTime()
        let startDate = trackingStartDate ?? Date()
        isTrackingTrip = false
        isSpeedPaused = false
        trackingStartDate = nil
        pedometer.stopUpdates()
        trackingResourcesStarted = false
        endBackgroundLocationSession()
        Task { await endLiveActivity() }
        statusText = authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse
            ? "Trip saved on map"
            : "Location unavailable"
        let simplifiedSamples = Self.simplify(locationSamples, toleranceMeters: 8)
        return TripRecap(
            startDate: startDate,
            steps: stepCount,
            distanceMeters: distanceMeters,
            elapsedSeconds: elapsedSeconds,
            averageSpeedMetersPerSecond: averageSpeedMetersPerSecond,
            coordinates: simplifiedSamples.map(\.coordinate),
            locationSamples: simplifiedSamples,
            gpsDistanceMeters: gpsDistanceMeters,
            pedometerDistanceMeters: pedometerDistanceMeters
        )
    }

    func clearPersistedTrip() {
        guard let activeTripRecord else { return }
        modelContext.delete(activeTripRecord)
        do {
            try modelContext.save()
            self.activeTripRecord = nil
        } catch {
            modelContext.rollback()
            persistenceStatus.report(error, operation: "Finishing the active trip")
        }
    }

    func completedTripWasPersisted() {
        activeTripRecord = nil
    }

    private func startPedometerUpdates() {
        guard CMPedometer.isStepCountingAvailable(), let trackingStartDate else {
            statusText = "Steps unavailable on this device"
            return
        }
        pedometer.startUpdates(from: trackingStartDate) { [weak self] data, error in
            guard let self else { return }
            DispatchQueue.main.async {
                if error != nil { self.statusText = "Steps unavailable"; return }
                guard let data else { return }
                self.stepCount = data.numberOfSteps.intValue
                if let distance = data.distance?.doubleValue {
                    self.pedometerDistanceMeters = distance
                    self.distanceMeters = distance
                } else {
                    self.distanceMeters = self.gpsDistanceMeters
                }
            }
        }
    }

    private func beginBackgroundLocationSession() {
        locationServiceSession = CLServiceSession(authorization: .whenInUse)
        backgroundActivitySession = CLBackgroundActivitySession()
        applyLocationPolicyForCurrentState()
    }

    private func endBackgroundLocationSession() {
        backgroundActivitySession?.invalidate()
        backgroundActivitySession = nil
        locationServiceSession = nil
        applyLocationPolicyForCurrentState()
    }

    private func applyLocationPolicyForCurrentState() {
        locationManager.desiredAccuracy = isTrackingTrip ? kCLLocationAccuracyBest : kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = isTrackingTrip ? 8 : 50
        locationManager.activityType = .fitness
        locationManager.pausesLocationUpdatesAutomatically = !isTrackingTrip
        locationManager.allowsBackgroundLocationUpdates = isTrackingTrip
        locationManager.showsBackgroundLocationIndicator = isTrackingTrip
    }

    private func isUsableLocation(_ location: CLLocation) -> Bool {
        location.horizontalAccuracy >= 0
            && location.horizontalAccuracy <= 35
            && abs(location.timestamp.timeIntervalSinceNow) <= 15
    }

    private func appendRoutePointIfNeeded(_ location: CLLocation) {
        guard location.speed < 0 || location.speed <= 6 else { return }
        guard let previousSample = locationSamples.last else {
            locationSamples.append(CodableLocationSample(location))
            routeCoordinates.append(location.coordinate)
            return
        }

        let previousLocation = previousSample.location
        let elapsed = location.timestamp.timeIntervalSince(previousSample.timestamp)
        guard elapsed > 0 else { return }
        let segmentDistance = location.distance(from: previousLocation)
        let uncertainty = max(previousLocation.horizontalAccuracy, location.horizontalAccuracy)
        let plausibleDistance = elapsed * 8 + uncertainty
        guard segmentDistance <= max(50, plausibleDistance), segmentDistance >= 5 else { return }

        locationSamples.append(CodableLocationSample(location))
        routeCoordinates.append(location.coordinate)
        gpsDistanceMeters += segmentDistance
        if pedometerDistanceMeters == nil { distanceMeters = gpsDistanceMeters }
    }

    private func updateAutomaticPause(using location: CLLocation) {
        guard location.speed >= 0 else { return }
        if location.speed > 6 {
            fastSampleCount += 1
            walkingSampleCount = 0
            if fastSampleCount >= 3 { isSpeedPaused = true }
        } else if location.speed < 4 {
            walkingSampleCount += 1
            fastSampleCount = 0
            if walkingSampleCount >= 3 { isSpeedPaused = false }
        }
    }

    private func startTrackingResourcesIfNeeded() {
        guard !trackingResourcesStarted else { return }
        trackingResourcesStarted = true
        beginBackgroundLocationSession()
        startPedometerUpdates()
        startLiveActivity()
    }

    private func createActiveTripRecord() {
        guard let trackingStartDate else { return }
        let record = ActiveTripRecord(startDate: trackingStartDate)
        record.coordinates = routeCoordinates.map(CodableCoordinate.init)
        modelContext.insert(record)
        activeTripRecord = record
        checkpointActiveTrip(force: true)
    }

    private func restoreActiveTrip() {
        do {
            guard let record = try modelContext.fetch(FetchDescriptor<ActiveTripRecord>()).first else { return }
            activeTripRecord = record
            trackingStartDate = record.startDate
            stepCount = record.stepCount
            distanceMeters = record.distanceMeters
            gpsDistanceMeters = record.gpsDistanceMeters
            pedometerDistanceMeters = record.pedometerDistanceMeters
            elapsedSeconds = record.elapsedSeconds
            isManuallyPaused = record.isManuallyPaused
            isSpeedPaused = record.isSpeedPaused
            manualPauseStartDate = record.manualPauseStartDate
            totalPausedSeconds = record.totalPausedSeconds
            routeCoordinates = record.coordinates.map(\.asCLLocationCoordinate2D)
            locationSamples = record.locationSamples
            isTrackingTrip = true
            statusText = isManuallyPaused ? "Paused" : "Resuming your trip"
        } catch {
            persistenceStatus.report(error, operation: "Recovering the active trip")
        }
    }

    private func checkpointActiveTrip(force: Bool = false) {
        guard isTrackingTrip, let record = activeTripRecord else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastCheckpointDate) >= 15 else { return }

        record.stepCount = stepCount
        record.distanceMeters = distanceMeters
        record.gpsDistanceMeters = gpsDistanceMeters
        record.pedometerDistanceMeters = pedometerDistanceMeters
        record.elapsedSeconds = elapsedSeconds
        record.isManuallyPaused = isManuallyPaused
        record.isSpeedPaused = isSpeedPaused
        record.manualPauseStartDate = manualPauseStartDate
        record.totalPausedSeconds = totalPausedSeconds
        record.coordinates = routeCoordinates.map(CodableCoordinate.init)
        record.locationSamples = locationSamples
        record.updatedAt = now

        do {
            try modelContext.save()
            lastCheckpointDate = now
        } catch {
            modelContext.rollback()
            persistenceStatus.report(error, operation: "Saving the active trip")
        }
    }

    private static func simplify(
        _ samples: [CodableLocationSample],
        toleranceMeters: Double
    ) -> [CodableLocationSample] {
        guard samples.count > 2 else { return samples }

        func perpendicularDistance(_ point: CLLocation, from start: CLLocation, to end: CLLocation) -> Double {
            let referenceLatitude = start.coordinate.latitude * .pi / 180
            func projected(_ location: CLLocation) -> (x: Double, y: Double) {
                (
                    location.coordinate.longitude * 111_000 * cos(referenceLatitude),
                    location.coordinate.latitude * 111_000
                )
            }
            let p = projected(point), a = projected(start), b = projected(end)
            let dx = b.x - a.x, dy = b.y - a.y
            guard dx != 0 || dy != 0 else { return hypot(p.x - a.x, p.y - a.y) }
            let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / (dx * dx + dy * dy)))
            return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
        }

        func reduce(_ slice: ArraySlice<CodableLocationSample>) -> [CodableLocationSample] {
            guard let first = slice.first, let last = slice.last, slice.count > 2 else { return Array(slice) }
            var maximumDistance = 0.0
            var splitIndex: Array.Index?
            for index in slice.indices.dropFirst().dropLast() {
                let distance = perpendicularDistance(slice[index].location, from: first.location, to: last.location)
                if distance > maximumDistance {
                    maximumDistance = distance
                    splitIndex = index
                }
            }
            guard maximumDistance > toleranceMeters, let splitIndex else { return [first, last] }
            let left = reduce(slice[slice.startIndex...splitIndex])
            let right = reduce(slice[splitIndex..<slice.endIndex])
            return left.dropLast() + right
        }

        return reduce(samples[...])
    }

    private func refreshNearbyPlacesIfNeeded(from location: CLLocation) {
        guard let nearbyPlaceSearchLocation else { refreshNearbyPlaces(); return }
        if location.distance(from: nearbyPlaceSearchLocation) > 150 { refreshNearbyPlaces() }
    }

    // MARK: - Live Activity

    private func startLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if let existing = Activity<TripActivityAttributes>.activities.first {
            liveActivity = existing
            return
        }
        let attrs = TripActivityAttributes(startDate: trackingStartDate ?? Date())
        let state = TripActivityAttributes.ContentState(
            stepCount: 0,
            elapsedSeconds: 0,
            distanceMeters: 0,
            isPaused: false
        )
        liveActivity = try? Activity.request(
            attributes: attrs,
            content: ActivityContent(state: state, staleDate: nil)
        )
    }

    private func updateLiveActivity() async {
        let state = TripActivityAttributes.ContentState(
            stepCount: stepCount,
            elapsedSeconds: elapsedSeconds,
            distanceMeters: distanceMeters,
            isPaused: isManuallyPaused || isSpeedPaused
        )
        await liveActivity?.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(70)))
    }

    private func endLiveActivity() async {
        await liveActivity?.end(nil, dismissalPolicy: .immediate)
        liveActivity = nil
    }
}
