import CoreLocation
import MapKit
import SwiftUI
import UIKit

struct ContentView: View {
    @State private var session = ExplorationSession()
    @State private var cameraPosition: MapCameraPosition = .userLocation(
        fallback: .region(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7671),
                latitudinalMeters: 1200,
                longitudinalMeters: 1200
            )
        )
    )

    @State private var tripStore = TripStore()
    @State private var collectionStore = CollectionStore()
    @State private var fogStore = FogStore()
    @State private var areaStore = AreaStore()
    @State private var settings = AppSettings()
    @State private var visibleMapRect = MKMapRect.null
    @State private var isARViewEnabled = false
    @State private var tripRecap: TripRecap?
    @State private var showMenu = false

    var body: some View {
        ZStack {
            Map(position: $cameraPosition, interactionModes: [.pan, .zoom]) {
                UserAnnotation()

                if session.isTrackingTrip && session.routeCoordinates.count > 1 {
                    MapPolyline(coordinates: session.routeCoordinates, contourStyle: .straight)
                        .stroke(.green, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                }

                ForEach(availableNearbyPlaces) { place in
                    Annotation(place.name, coordinate: place.coordinate, anchor: .center) {
                        Circle()
                            .fill(place.kind.color)
                            .frame(width: 14, height: 14)
                            .overlay {
                                Circle().stroke(.white, lineWidth: 2)
                            }
                    }
                }
            }
            .mapStyle(settings.mapStyleOption.mapStyle)
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .ignoresSafeArea()
            .onMapCameraChange(frequency: .continuous) { context in
                visibleMapRect = context.rect
            }

            FogOfWarView(revealedCoordinates: fogStore.revealedCoordinates, visibleRect: visibleMapRect)
                .ignoresSafeArea()

            if isARViewEnabled {
                ARExplorationView(
                    places: availableNearbyPlaces,
                    userLocation: session.currentLocation,
                    collectionStore: collectionStore,
                    onCollect: { place in collectionStore.collect(place: place) }
                )
                .ignoresSafeArea()
                .transition(.opacity)
            }

            VStack(spacing: 12) {
                if !isARViewEnabled {
                    topStatusBar
                }

                Spacer()

                VStack(spacing: 10) {
                    if !isARViewEnabled && session.isTrackingTrip {
                        tripStats
                    }
                    controlBar
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .animation(.snappy, value: isARViewEnabled)
        .onChange(of: session.currentLocation) { _, newLocation in
            guard let loc = newLocation else { return }
            fogStore.reveal(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
            areaStore.maybeGeocode(loc)
        }
        .onAppear {
            session.prepareLocation()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                session.refreshElapsedTime()
            }
        }
        .sheet(item: $tripRecap) { recap in
            TripRecapView(recap: recap)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showMenu) {
            NavigationStack {
                AppMenuView(tripStore: tripStore, collectionStore: collectionStore, areaStore: areaStore, fogStore: fogStore)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            cameraPosition = .userLocation(fallback: .automatic)
        }
        .environment(tripStore)
        .environment(settings)
    }

    private var topStatusBar: some View {
        HStack(spacing: 12) {
            Image(systemName: session.isTrackingTrip ? "figure.walk.circle.fill" : "map.circle.fill")
                .font(.title2)
                .foregroundStyle(session.isTrackingTrip ? .green : .blue)

            VStack(alignment: .leading, spacing: 2) {
                Text("Wanderer").font(.headline)
                Text(statusSubtitle).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            Button { showMenu = true } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.title2)
                    .foregroundStyle(.primary)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    private var tripStats: some View {
        HStack(spacing: 0) {
            statItem(value: "\(session.stepCount)", label: "Steps")
            Divider().frame(height: 28)
            statItem(value: Formatters.distance(session.distanceMeters, imperial: settings.useImperial), label: "Distance")
            Divider().frame(height: 28)
            statItem(value: Formatters.speed(session.averageSpeedMetersPerSecond, imperial: settings.useImperial), label: "Avg speed")
            Divider().frame(height: 28)
            statItem(value: session.formattedElapsedTime, label: "Time")
        }
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var controlBar: some View {
        HStack(spacing: 10) {
            Button {
                cameraPosition = .userLocation(fallback: .automatic)
            } label: {
                Image(systemName: "location.fill")
                    .font(.headline)
                    .frame(minWidth: 48, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)

            toggleButton(title: "AR", systemImage: "camera.viewfinder", isOn: isARViewEnabled) {
                isARViewEnabled.toggle()
            }

            if session.isTrackingTrip {
                // Pause/Resume — manual pause independent of auto speed-pause.
                let paused = session.isManuallyPaused || session.isSpeedPaused
                toggleButton(
                    title: "",
                    systemImage: session.isManuallyPaused ? "play.fill" : "pause.fill",
                    isOn: true,
                    activeTint: paused ? .orange : .green
                ) {
                    session.toggleManualPause()
                }
                .disabled(session.isSpeedPaused)

                // Stop — ends the trip and saves it.
                Button {
                    if let recap = session.toggleTripTracking(), recap.distanceMeters > 0 {
                        tripStore.save(recap)
                        tripRecap = recap
                    }
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.headline)
                        .frame(minWidth: 48, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                toggleButton(title: "Tracker", systemImage: "shoeprints.fill", isOn: false) {
                    session.toggleTripTracking()
                }
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func toggleButton(
        title: String,
        systemImage: String,
        isOn: Bool,
        activeTint: Color = .green,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(.borderedProminent)
        .tint(isOn ? activeTint : .secondary)
    }

    private var statusSubtitle: String {
        if session.isTrackingTrip || areaStore.currentAreaName == nil {
            return session.statusText
        }
        return areaStore.currentAreaName!
    }

    private var availableNearbyPlaces: [NearbyPlace] {
        session.nearbyPlaces.filter {
            !collectionStore.isCollectedToday(name: $0.name, kind: $0.kind)
        }
    }
}

#Preview {
    ContentView()
}
