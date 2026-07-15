import CoreLocation
import MapKit
import Photos
import SwiftUI

struct TripRecapView: View {
    let recap: TripRecap
    @Environment(TripStore.self) private var tripStore
    @Environment(AppSettings.self) private var settings
    @State private var animatedCoordinates: [CLLocationCoordinate2D] = []
    @State private var recapCameraPosition: MapCameraPosition
    @State private var savedPhotos: [PHAsset] = []
    @State private var matchingPhotos: [PHAsset] = []
    @State private var photoAuthStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @State private var showPhotoSelector = false
    @State private var tripName: String
    @State private var tripNotes: String
    @State private var fullscreenPhoto: PHAsset?
    @FocusState private var isNotesFocused: Bool

    private let maxNotesLength = 300

    init(recap: TripRecap) {
        self.recap = recap
        _recapCameraPosition = State(initialValue: recap.mapCameraPosition)
        _tripName = State(initialValue: recap.name)
        _tripNotes = State(initialValue: recap.notes)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                nameField
                replayMap
                statsGrid
                notesField
                photosSection
                Text("\(recap.pathPointCount) location points recorded")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .contentShape(Rectangle())
        .onTapGesture { isNotesFocused = false }
        .scrollDismissesKeyboard(.interactively)
        .task(id: recap.id) { await replayPath() }
        .task(id: recap.id) { await loadPhotos() }
        .onDisappear { persistMetaIfChanged() }
        .sheet(isPresented: $showPhotoSelector) {
            TripPhotoSelectorView(
                photos: matchingPhotos,
                preselectedIDs: Set(tripStore.savedPhotoIDs(for: recap.id))
            ) { selectedIDs in
                tripStore.savePhotoIDs(selectedIDs, for: recap.id)
                Task { savedPhotos = await fetchPhotosByIDs(selectedIDs) }
            }
        }
        .overlay {
            if let asset = fullscreenPhoto {
                PhotoFullscreenOverlay(
                    asset: asset,
                    onClose: { fullscreenPhoto = nil },
                    onRemove: { removePhoto(asset) }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: fullscreenPhoto?.localIdentifier)
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            Image(systemName: "checkmark.seal.fill")
                .font(.title2)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Trip Recap").font(.title2.bold())
                Text(recap.formattedDate).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private var nameField: some View {
        TextField("Name this trip…", text: $tripName)
            .font(.headline)
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .submitLabel(.done)
    }

    private var replayMap: some View {
        TripReplayMap(
            cameraPosition: $recapCameraPosition,
            fullCoordinates: recap.coordinates,
            animatedCoordinates: animatedCoordinates
        )
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var statsGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 14) {
            GridRow {
                recapMetric("Steps", "\(recap.steps)", "shoeprints.fill")
                recapMetric("Distance",
                            Formatters.distance(recap.distanceMeters, imperial: settings.useImperial),
                            "point.topleft.down.curvedto.point.bottomright.up")
            }
            GridRow {
                recapMetric("Time", recap.formattedDuration, "timer")
                recapMetric("Avg speed",
                            Formatters.speed(recap.averageSpeedMetersPerSecond, imperial: settings.useImperial),
                            "speedometer")
            }
        }
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $tripNotes)
                    .focused($isNotesFocused)
                    .frame(minHeight: 72, maxHeight: 120)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .onChange(of: tripNotes) { _, new in
                        if new.count > maxNotesLength {
                            tripNotes = String(new.prefix(maxNotesLength))
                        }
                    }
                if tripNotes.isEmpty {
                    Text("Add notes…")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
            Text("\(tripNotes.count)/\(maxNotesLength)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var photosSection: some View {
        if !savedPhotos.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Photos").font(.subheadline.bold())
                    Spacer()
                    Button("Edit") { showPhotoSelector = true }
                        .font(.subheadline)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(savedPhotos, id: \.localIdentifier) { asset in
                            AssetThumbnailView(asset: asset)
                                .frame(width: 80, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .onTapGesture { fullscreenPhoto = asset }
                        }
                    }
                }
            }
        } else if !matchingPhotos.isEmpty {
            Button { showPhotoSelector = true } label: {
                Label("Add Photos (\(matchingPhotos.count) available)", systemImage: "photo.badge.plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .tint(.green)
        } else if photoAuthStatus == .notDetermined {
            Button {
                Task {
                    let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
                    photoAuthStatus = status
                    if status == .authorized || status == .limited {
                        matchingPhotos = await fetchPhotos()
                    }
                    showPhotoSelector = true
                }
            } label: {
                Label("Add Photos", systemImage: "photo.badge.plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .tint(.green)
        } else {
            Button {} label: {
                Label("No Photos Available", systemImage: "photo.slash")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .disabled(true)
        }
    }

    private func recapMetric(_ label: String, _ value: String, _ systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage).frame(width: 26, height: 26).foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.headline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.75)
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Photo management

    private func removePhoto(_ asset: PHAsset) {
        savedPhotos.removeAll { $0.localIdentifier == asset.localIdentifier }
        tripStore.savePhotoIDs(savedPhotos.map(\.localIdentifier), for: recap.id)
        fullscreenPhoto = nil
    }

    // MARK: - Persistence

    private func persistMetaIfChanged() {
        let name = tripName.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = tripNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name != recap.name || notes != recap.notes else { return }
        tripStore.updateMeta(id: recap.id, name: name, notes: notes)
    }

    // MARK: - Async helpers

    @MainActor
    private func replayPath() async {
        animatedCoordinates = []
        let coords = recap.coordinates
        guard !coords.isEmpty else { return }
        let totalMs = 2500
        let stepMs = max(16, totalMs / coords.count)
        let animDuration = min(Double(stepMs) / 1000.0, 0.18)
        for coordinate in coords {
            guard !Task.isCancelled else { return }
            withAnimation(.linear(duration: animDuration)) { animatedCoordinates.append(coordinate) }
            try? await Task.sleep(for: .milliseconds(stepMs))
        }
    }

    private func loadPhotos() async {
        let savedIDs = tripStore.savedPhotoIDs(for: recap.id)
        if !savedIDs.isEmpty {
            savedPhotos = await fetchPhotosByIDs(savedIDs)
        }
        if photoAuthStatus == .authorized || photoAuthStatus == .limited {
            matchingPhotos = await fetchPhotos()
        }
    }

    private func fetchPhotosByIDs(_ ids: [String]) async -> [PHAsset] {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }

    private func fetchPhotos() async -> [PHAsset] {
        let start = recap.startDate.addingTimeInterval(-300)
        let end   = recap.startDate.addingTimeInterval(recap.elapsedSeconds + 300)
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "creationDate >= %@ AND creationDate <= %@",
            start as NSDate, end as NSDate
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

        let result = PHAsset.fetchAssets(with: .image, options: options)
        guard result.count > 0 else { return [] }

        let coords = recap.coordinates
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in
            guard let location = asset.location else { return }
            if coords.isEmpty || coords.contains(where: {
                location.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) < 500
            }) {
                assets.append(asset)
            }
        }
        return assets
    }
}

// MARK: - Photo Fullscreen Overlay

struct PhotoFullscreenOverlay: View {
    let asset: PHAsset
    let onClose: () -> Void
    let onRemove: () -> Void

    @State private var image: UIImage?
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
                .opacity(dragDismissOpacity)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(.horizontal, 4)
            } else {
                ProgressView()
                    .tint(.white)
            }

            // Controls
            VStack {
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Color.white, Color.black.opacity(0.4))
                            .padding(16)
                    }
                    Spacer()
                    Button(action: onRemove) {
                        Image(systemName: "trash.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Color.white, Color.red.opacity(0.85))
                            .padding(16)
                    }
                }
                Spacer()
            }
        }
        .offset(y: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.height > 0 {
                        dragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    if value.translation.height > 80 {
                        onClose()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            dragOffset = 0
                        }
                    }
                }
        )
        .task(id: asset.localIdentifier) {
            // Fast preview first, then full quality
            if let preview = await loadImage(size: CGSize(width: 800, height: 800), delivery: .fastFormat) {
                image = preview
            }
            if let full = await loadImage(size: PHImageManagerMaximumSize, delivery: .highQualityFormat) {
                image = full
            }
        }
    }

    private var dragDismissOpacity: Double {
        let progress = dragOffset / 250
        return max(0, 1 - Double(progress))
    }

    private func loadImage(size: CGSize, delivery: PHImageRequestOptionsDeliveryMode) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let opts = PHImageRequestOptions()
            opts.deliveryMode = delivery
            opts.resizeMode = delivery == .fastFormat ? .fast : .none
            opts.isNetworkAccessAllowed = true
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: size,
                contentMode: .aspectFit,
                options: opts
            ) { img, _ in continuation.resume(returning: img) }
        }
    }
}

// MARK: - Supporting views

struct TripPhotoSelectorView: View {
    let photos: [PHAsset]
    let onSave: ([String]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIDs: Set<String>
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 2)]

    init(photos: [PHAsset], preselectedIDs: Set<String>, onSave: @escaping ([String]) -> Void) {
        self.photos = photos
        self.onSave = onSave
        _selectedIDs = State(initialValue: preselectedIDs)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(photos, id: \.localIdentifier) { asset in
                        let isSelected = selectedIDs.contains(asset.localIdentifier)
                        ZStack(alignment: .topTrailing) {
                            AssetThumbnailView(asset: asset)
                                .aspectRatio(1, contentMode: .fill)
                                .clipped()
                                .overlay(isSelected ? Color.blue.opacity(0.25) : Color.clear)
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.white, .blue)
                                    .padding(4)
                            }
                        }
                        .onTapGesture {
                            if isSelected { selectedIDs.remove(asset.localIdentifier) }
                            else { selectedIDs.insert(asset.localIdentifier) }
                        }
                    }
                }
            }
            .navigationTitle("Add Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selectedIDs.isEmpty ? "Skip" : "Add \(selectedIDs.count)") {
                        onSave(Array(selectedIDs))
                        dismiss()
                    }
                }
            }
            .overlay {
                if photos.isEmpty {
                    ContentUnavailableView("No Matching Photos", systemImage: "photo.slash",
                        description: Text("No photos were taken near this trip's route."))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

struct AssetThumbnailView: View {
    let asset: PHAsset
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color.secondary.opacity(0.2).overlay { ProgressView() }
            }
        }
        .task(id: asset.localIdentifier) { image = await loadThumbnail() }
    }

    private func loadThumbnail() async -> UIImage? {
        await withCheckedContinuation { continuation in
            let opts = PHImageRequestOptions()
            opts.deliveryMode = .fastFormat
            opts.resizeMode = .fast
            opts.isNetworkAccessAllowed = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 220, height: 220),
                contentMode: .aspectFill,
                options: opts
            ) { image, _ in continuation.resume(returning: image) }
        }
    }
}

struct TripReplayMap: View {
    @Binding var cameraPosition: MapCameraPosition
    let fullCoordinates: [CLLocationCoordinate2D]
    let animatedCoordinates: [CLLocationCoordinate2D]

    var body: some View {
        Map(position: $cameraPosition, interactionModes: []) {
            if let first = fullCoordinates.first {
                Annotation("Start", coordinate: first, anchor: .center) {
                    Image(systemName: "play.circle.fill")
                        .font(.title3).foregroundStyle(.green)
                        .background(.background, in: Circle())
                }
            }
            if let last = fullCoordinates.last, fullCoordinates.count > 1 {
                Annotation("Finish", coordinate: last, anchor: .center) {
                    Image(systemName: "flag.circle.fill")
                        .font(.title3).foregroundStyle(.blue)
                        .background(.background, in: Circle())
                }
            }
            if animatedCoordinates.count > 1 {
                MapPolyline(coordinates: animatedCoordinates, contourStyle: .straight)
                    .stroke(.green, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
        .overlay(alignment: .topLeading) {
            Label("Path replay", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                .font(.caption.bold())
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(.regularMaterial, in: Capsule())
                .padding(10)
        }
    }
}

struct TripHistoryView: View {
    let tripStore: TripStore
    @State private var selectedTrip: TripRecap?

    var body: some View {
        List(tripStore.trips) { trip in
            Button { selectedTrip = trip } label: { TripHistoryRow(trip: trip) }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) { tripStore.delete(trip) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
        }
        .navigationTitle("Trip History")
        .overlay {
            if tripStore.trips.isEmpty {
                ContentUnavailableView("No Trips Yet", systemImage: "figure.walk",
                    description: Text("Complete a trip to see it here."))
            }
        }
        .sheet(item: $selectedTrip) { recap in
            TripRecapView(recap: recap)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}

struct TripHistoryRow: View {
    let trip: TripRecap
    @Environment(AppSettings.self) private var settings

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(trip.name.isEmpty ? trip.formattedDate : trip.name)
                    .font(.headline)
                if !trip.name.isEmpty {
                    Text(trip.formattedDate)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    Label(Formatters.distance(trip.distanceMeters, imperial: settings.useImperial),
                          systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    Label(trip.formattedDuration, systemImage: "timer")
                }
                .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }
}
