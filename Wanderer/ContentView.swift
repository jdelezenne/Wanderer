import CoreLocation
import MapKit
import SwiftUI
import SwiftData
import UIKit

struct ContentView: View {
    @State private var session: ExplorationSession
    @State private var cameraPosition: MapCameraPosition = .userLocation(
        fallback: .region(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7671),
                latitudinalMeters: 1200,
                longitudinalMeters: 1200
            )
        )
    )

    @State private var tripStore: TripStore
    @State private var collectionStore: CollectionStore
    @State private var fogStore: FogStore
    @State private var areaStore: AreaStore
    @State private var persistenceStatus: PersistenceStatus
    @State private var settings = AppSettings()
    @State private var visibleMapRect = MKMapRect.null
    @State private var isARViewEnabled = false
    @State private var tripRecap: TripRecap?
    @State private var showMenu = false

    init(modelContext: ModelContext, persistenceStatus: PersistenceStatus) {
        _session = State(initialValue: ExplorationSession(
            modelContext: modelContext,
            persistenceStatus: persistenceStatus
        ))
        _tripStore = State(initialValue: TripStore(
            modelContext: modelContext,
            persistenceStatus: persistenceStatus
        ))
        _collectionStore = State(initialValue: CollectionStore(
            modelContext: modelContext,
            persistenceStatus: persistenceStatus
        ))
        _fogStore = State(initialValue: FogStore(
            modelContext: modelContext,
            persistenceStatus: persistenceStatus
        ))
        _areaStore = State(initialValue: AreaStore(
            modelContext: modelContext,
            persistenceStatus: persistenceStatus
        ))
        _persistenceStatus = State(initialValue: persistenceStatus)
    }

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
                        Image(uiImage: place.kind.spriteImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 46, height: 46)
                            .padding(3)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay {
                                Circle().stroke(place.kind.color.opacity(0.7), lineWidth: 1)
                            }
                            .shadow(color: .black.opacity(0.24), radius: 5, y: 3)
                            .accessibilityLabel("\(place.name), \(place.kind.label)")
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
                    onCollect: { place in
                        collectionStore.collect(place: place, areaID: areaStore.currentAreaID)
                    }
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
        .alert(item: $persistenceStatus.problem) { problem in
            Alert(
                title: Text(problem.title),
                message: Text(problem.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var topStatusBar: some View {
        HStack(spacing: 12) {
            Group {
                if let appIcon {
                    Image(uiImage: appIcon)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "map.fill")
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                        .foregroundStyle(.white)
                        .background(.blue)
                }
            }
                .frame(width: 38, height: 38)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.65), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                .accessibilityHidden(true)

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

            if session.isTrackingTrip {
                let paused = session.isManuallyPaused || session.isSpeedPaused
                Button {
                    session.toggleManualPause()
                } label: {
                    Label(
                        session.isManuallyPaused ? "Resume" : "Pause",
                        systemImage: session.isManuallyPaused ? "play.fill" : "pause.fill"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(paused ? .orange : .green)
                .disabled(session.isSpeedPaused)

                Button(action: finishWalk) {
                    Image(systemName: "stop.fill")
                        .font(.headline)
                        .frame(minWidth: 48, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                Button {
                    _ = session.toggleTripTracking()
                } label: {
                    Label("Start Walk", systemImage: "figure.walk")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }

            Button { isARViewEnabled.toggle() } label: {
                Image(systemName: "camera.viewfinder")
                    .font(.headline)
                    .frame(minWidth: 48, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(isARViewEnabled ? .green : .secondary)
            .accessibilityLabel(isARViewEnabled ? "Close AR" : "Open AR")
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

    private var statusSubtitle: String {
        if session.isTrackingTrip || areaStore.currentAreaName == nil {
            return session.statusText
        }
        return areaStore.currentAreaName!
    }

    private var appIcon: UIImage? {
        guard
            let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
            let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
            let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
            let iconName = iconFiles.last
        else { return nil }

        return UIImage(named: iconName)
    }

    private var availableNearbyPlaces: [NearbyPlace] {
        session.nearbyPlaces.filter {
            !collectionStore.isCollectedToday($0)
        }
    }

    private func finishWalk() {
        guard var recap = session.toggleTripTracking() else { return }
        guard recap.distanceMeters > 0 else {
            session.clearPersistedTrip()
            return
        }

        if recap.name.isEmpty { recap.name = defaultTripName }
        if tripStore.save(recap) {
            session.completedTripWasPersisted()
            tripRecap = recap
        }
    }

    private var defaultTripName: String {
        if let area = areaStore.currentAreaName {
            return "\(area) Walk"
        }
        if let landmark = session.nearbyPlaces.first {
            return "Walk near \(landmark.name)"
        }
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Morning Walk"
        case 12..<17: return "Afternoon Walk"
        case 17..<22: return "Evening Walk"
        default: return "Night Walk"
        }
    }
}

#Preview {
    let container = try! WandererPersistence.makeContainer(inMemory: true)
    ContentView(modelContext: container.mainContext, persistenceStatus: PersistenceStatus())
        .modelContainer(container)
}
