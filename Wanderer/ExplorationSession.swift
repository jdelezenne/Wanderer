import ActivityKit
import CoreLocation
import CoreMotion
import Foundation
import Observation

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
    var elapsedSeconds: TimeInterval = 0
    var nearbyPlaces: [NearbyPlace] = []
    var statusText = "Finding your location"

    @ObservationIgnored private let locationManager = CLLocationManager()
    @ObservationIgnored private let pedometer = CMPedometer()
    @ObservationIgnored private var backgroundActivitySession: CLBackgroundActivitySession?
    @ObservationIgnored private var locationServiceSession: CLServiceSession?
    @ObservationIgnored private var trackingStartDate: Date?
    @ObservationIgnored private var nearbyPlaceSearchLocation: CLLocation?
    @ObservationIgnored private var isSearchingNearbyPlaces = false
    @ObservationIgnored private var manualPauseStartDate: Date?
    @ObservationIgnored private var totalPausedSeconds: TimeInterval = 0
    @ObservationIgnored private var liveActivity: Activity<TripActivityAttributes>?

    var formattedDistance: String        { Formatters.distance(distanceMeters) }
    var formattedAverageSpeed: String    { Formatters.speed(averageSpeedMetersPerSecond) }
    var formattedElapsedTime: String     { Formatters.duration(elapsedSeconds) }

    var averageSpeedMetersPerSecond: Double {
        guard elapsedSeconds > 0 else { return 0 }
        return distanceMeters / elapsedSeconds
    }

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 8
        locationManager.activityType = .fitness
        locationManager.pausesLocationUpdatesAutomatically = true
        locationManager.showsBackgroundLocationIndicator = false
        authorizationStatus = locationManager.authorizationStatus
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
    }

    func refreshElapsedTime() {
        guard isTrackingTrip, let trackingStartDate else { return }
        let raw = Date().timeIntervalSince(trackingStartDate)
        let currentPause = isManuallyPaused
            ? (manualPauseStartDate.map { Date().timeIntervalSince($0) } ?? 0)
            : 0
        elapsedSeconds = max(0, raw - totalPausedSeconds - currentPause)
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

        let speed = newestLocation.speed
        let tooFast = speed >= 0 && speed > 6.0
        if tooFast != isSpeedPaused { isSpeedPaused = tooFast }

        if isSpeedPaused {
            statusText = "Moving too fast — paused"
            return
        }

        if isManuallyPaused { return }

        statusText = "Tracking your trip"
        for location in locations where isUsableLocation(location) {
            appendRoutePointIfNeeded(location)
        }
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
        elapsedSeconds = 0
        routeCoordinates = currentLocation.map { [$0.coordinate] } ?? []
        trackingStartDate = Date()
        statusText = "Tracking your trip"
        beginBackgroundLocationSession()
        prepareLocation()
        startPedometerUpdates()
        startLiveActivity()
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
        endBackgroundLocationSession()
        Task { await endLiveActivity() }
        statusText = authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse
            ? "Trip saved on map"
            : "Location unavailable"
        return TripRecap(
            startDate: startDate,
            steps: stepCount,
            distanceMeters: distanceMeters,
            elapsedSeconds: elapsedSeconds,
            averageSpeedMetersPerSecond: averageSpeedMetersPerSecond,
            coordinates: routeCoordinates
        )
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
                if let distance = data.distance?.doubleValue { self.distanceMeters = distance }
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
        location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= 50
    }

    private func appendRoutePointIfNeeded(_ location: CLLocation) {
        guard let prev = routeCoordinates.last else {
            routeCoordinates.append(location.coordinate)
            return
        }
        let prevLocation = CLLocation(latitude: prev.latitude, longitude: prev.longitude)
        guard location.distance(from: prevLocation) >= 5 else { return }
        routeCoordinates.append(location.coordinate)
    }

    private func refreshNearbyPlacesIfNeeded(from location: CLLocation) {
        guard let nearbyPlaceSearchLocation else { refreshNearbyPlaces(); return }
        if location.distance(from: nearbyPlaceSearchLocation) > 150 { refreshNearbyPlaces() }
    }

    // MARK: - Live Activity

    private func startLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
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
