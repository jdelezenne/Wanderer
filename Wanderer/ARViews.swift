import ARKit
import CoreLocation
import RealityKit
import SwiftUI
import UIKit

struct ARExplorationView: View {
    let places: [NearbyPlace]
    let userLocation: CLLocation?
    let collectionStore: CollectionStore
    let onCollect: (NearbyPlace) -> Void

    @State private var collectedIDs: Set<String> = []
    @State private var lastCollected: NearbyPlace?
    @State private var feedbackTrigger = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.ignoresSafeArea()

                if isARSupported {
                    POIARView(
                        places: activePlaces,
                        userLocation: userLocation,
                        onCollect: collect
                    )
                } else {
                    ARSimulatorFallbackView(
                        places: activePlaces,
                        onCollect: collect
                    )
                }

                ARScanReticle()

                VStack(spacing: 12) {
                    discoveryHeader

                    Spacer()

                    if let lastCollected {
                        collectionToast(lastCollected)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else if let nearestPlace {
                        nearestPlaceCard(nearestPlace)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, max(proxy.safeAreaInsets.top, 12))
                .padding(.bottom, max(proxy.safeAreaInsets.bottom, 12) + 92)
                .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
        .sensoryFeedback(.success, trigger: feedbackTrigger)
    }

    private var activePlaces: [NearbyPlace] {
        let source = places.isEmpty ? NearbyPlace.previewPlaces : places
        return source.filter { !collectedIDs.contains($0.id) }
    }

    private var nearestPlace: NearbyPlace? {
        activePlaces.min { $0.distanceMeters < $1.distanceMeters }
    }

    private var discoveryHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.mint.opacity(0.16))
                    .frame(width: 42, height: 42)
                Circle()
                    .stroke(Color.mint.opacity(0.5), lineWidth: 1)
                    .frame(width: 32, height: 32)
                Image(systemName: "viewfinder")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.mint)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("DISCOVERY LENS")
                    .font(.caption.weight(.bold))
                    .tracking(1.4)
                Text(headerSubtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.62))
            }

            Spacer()

            Text("\(activePlaces.count)")
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(.mint)
                .contentTransition(.numericText())
            Text("nearby")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.62))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
    }

    private var headerSubtitle: String {
        if activePlaces.isEmpty { return "Area complete — keep exploring" }
        if !isARSupported { return "Preview mode • tap a discovery" }
        return "Move slowly • tap to collect"
    }

    private func nearestPlaceCard(_ place: NearbyPlace) -> some View {
        HStack(spacing: 12) {
            Image(uiImage: place.kind.spriteImage)
                .resizable()
                .scaledToFit()
                .frame(width: 62, height: 62)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("CLOSEST DISCOVERY")
                    .font(.caption2.weight(.bold))
                    .tracking(1)
                    .foregroundStyle(place.kind.color)
                Text(place.name)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(place.kind.label) • \(formatDistance(place.distanceMeters))")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.62))
            }

            Spacer(minLength: 4)

            Image(systemName: "hand.tap.fill")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.72))
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(Color.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(place.kind.color.opacity(0.45), lineWidth: 1)
        }
    }

    private func collectionToast(_ place: NearbyPlace) -> some View {
        HStack(spacing: 12) {
            Image(uiImage: place.kind.spriteImage)
                .resizable()
                .scaledToFit()
                .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 3) {
                Text("DISCOVERY COLLECTED")
                    .font(.caption2.weight(.bold))
                    .tracking(1)
                    .foregroundStyle(.mint)
                Text(place.name)
                    .font(.headline)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.title2)
                .foregroundStyle(.mint)
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(Color.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.mint.opacity(0.55), lineWidth: 1)
        }
    }

    private func collect(_ place: NearbyPlace) {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.76)) {
            _ = collectedIDs.insert(place.id)
            lastCollected = place
            feedbackTrigger += 1
        }
        onCollect(place)

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.2))
            guard lastCollected?.id == place.id else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                lastCollected = nil
            }
        }
    }

    private var isARSupported: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        ARWorldTrackingConfiguration.isSupported
        #endif
    }
}

private struct ARScanReticle: View {
    @State private var pulsing = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.mint.opacity(0.22), lineWidth: 1)
                .frame(width: pulsing ? 112 : 82, height: pulsing ? 112 : 82)
                .opacity(pulsing ? 0 : 0.9)

            Circle()
                .strokeBorder(.white.opacity(0.78), style: StrokeStyle(lineWidth: 1.5, dash: [7, 8]))
                .frame(width: 72, height: 72)

            Circle()
                .fill(.mint)
                .frame(width: 5, height: 5)
                .shadow(color: .mint, radius: 6)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) {
                pulsing = true
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct ARSimulatorFallbackView: View {
    let places: [NearbyPlace]
    let onCollect: (NearbyPlace) -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.025, green: 0.055, blue: 0.08), .black],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Circle()
                    .fill(Color.mint.opacity(0.04))
                    .frame(width: proxy.size.width * 1.15)
                    .overlay {
                        ForEach(1..<4, id: \.self) { ring in
                            Circle()
                                .stroke(Color.mint.opacity(0.09), lineWidth: 1)
                                .padding(CGFloat(ring) * 34)
                        }
                    }
                    .offset(y: 40)

                ForEach(Array(places.prefix(6).enumerated()), id: \.element.id) { index, place in
                    Button {
                        onCollect(place)
                    } label: {
                        simulatorToken(place)
                    }
                    .buttonStyle(.plain)
                    .position(position(for: index, in: proxy.size))
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel("Collect \(place.name), \(formatDistance(place.distanceMeters)) away")
                }

                if places.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 38))
                            .foregroundStyle(.mint)
                        Text("Area complete")
                            .font(.headline)
                        Text("Walk farther to reveal new discoveries")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .foregroundStyle(.white)
                    .padding(24)
                }
            }
        }
    }

    private func simulatorToken(_ place: NearbyPlace) -> some View {
        VStack(spacing: 5) {
            Image(uiImage: place.kind.spriteImage)
                .resizable()
                .scaledToFit()
                .frame(width: 92, height: 92)
                .shadow(color: place.kind.color.opacity(0.45), radius: 16)

            Text(place.name)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .foregroundStyle(.white)
                .background(Color.black.opacity(0.72), in: Capsule())
        }
        .frame(width: 132)
    }

    private func position(for index: Int, in size: CGSize) -> CGPoint {
        let positions: [(CGFloat, CGFloat)] = [
            (0.24, 0.31), (0.73, 0.28), (0.49, 0.47),
            (0.20, 0.62), (0.77, 0.61), (0.50, 0.73),
        ]
        let value = positions[index % positions.count]
        return CGPoint(x: size.width * value.0, y: size.height * value.1)
    }
}

struct POIARView: UIViewRepresentable {
    let places: [NearbyPlace]
    let userLocation: CLLocation?
    let onCollect: (NearbyPlace) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCollect: onCollect) }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.automaticallyConfigureSession = false
        arView.session.delegate = context.coordinator
        arView.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:))))

        let coaching = ARCoachingOverlayView()
        coaching.session = arView.session
        coaching.goal = .tracking
        coaching.activatesAutomatically = true
        coaching.translatesAutoresizingMaskIntoConstraints = false
        arView.addSubview(coaching)
        NSLayoutConstraint.activate([
            coaching.leadingAnchor.constraint(equalTo: arView.leadingAnchor),
            coaching.trailingAnchor.constraint(equalTo: arView.trailingAnchor),
            coaching.topAnchor.constraint(equalTo: arView.topAnchor),
            coaching.bottomAnchor.constraint(equalTo: arView.bottomAnchor),
        ])

        context.coordinator.arView = arView
        context.coordinator.configure(places: places, userLocation: userLocation)
        return arView
    }

    func updateUIView(_ arView: ARView, context: Context) {
        context.coordinator.configure(places: places, userLocation: userLocation)
    }

    final class Coordinator: NSObject, ARSessionDelegate {
        weak var arView: ARView?
        let onCollect: (NearbyPlace) -> Void
        private var configSignature = ""
        private var placeByAnchorID: [UUID: NearbyPlace] = [:]
        private var placeLookup: [UUID: NearbyPlace] = [:]

        init(onCollect: @escaping (NearbyPlace) -> Void) { self.onCollect = onCollect }

        func configure(places: [NearbyPlace], userLocation: CLLocation?) {
            guard let arView else { return }
            let signature = Self.signature(for: places, userLocation: userLocation)
            guard signature != configSignature else { return }
            configSignature = signature

            arView.scene.anchors.removeAll()
            placeByAnchorID.removeAll()
            placeLookup.removeAll()

            let displayed = Array((places.isEmpty ? NearbyPlace.previewPlaces : places).prefix(12))
            guard !displayed.isEmpty else { return }

            if ARGeoTrackingConfiguration.isSupported, let coordinate = userLocation?.coordinate {
                ARGeoTrackingConfiguration.checkAvailability(at: coordinate) { [weak self, weak arView] available, _ in
                    DispatchQueue.main.async {
                        guard let self, let arView else { return }
                        available
                            ? self.runGeoTracking(in: arView, places: displayed)
                            : self.runWorldTracking(in: arView, places: displayed, userLocation: userLocation)
                    }
                }
            } else {
                runWorldTracking(in: arView, places: displayed, userLocation: userLocation)
            }
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let arView else { return }
            let point = recognizer.location(in: arView)
            var hit: Entity? = arView.entity(at: point)
            while let entity = hit, UUID(uuidString: entity.name) == nil { hit = entity.parent }
            guard let container = hit,
                  let id = UUID(uuidString: container.name),
                  let place = placeLookup[id] else { return }

            var lifted = container.transform
            lifted.translation.y += 0.25
            lifted.scale = SIMD3<Float>(repeating: 0.001)
            container.move(to: lifted, relativeTo: container.parent, duration: 0.36, timingFunction: .easeIn)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) { [weak self] in
                container.removeFromParent()
                self?.onCollect(place)
            }
        }

        func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            guard let arView else { return }
            for anchor in anchors {
                guard let geo = anchor as? ARGeoAnchor,
                      let place = placeByAnchorID[geo.identifier] else { continue }
                placeLookup[place.renderID] = place
                let anchorEntity = AnchorEntity(anchor: anchor)
                let marker = Self.markerEntity(for: place)
                marker.position.y = 1.5
                anchorEntity.addChild(marker)
                arView.scene.addAnchor(anchorEntity)
            }
        }

        private func runGeoTracking(in arView: ARView, places: [NearbyPlace]) {
            let configuration = ARGeoTrackingConfiguration()
            configuration.planeDetection = []
            arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
            for place in places {
                let anchor = ARGeoAnchor(coordinate: place.coordinate)
                placeByAnchorID[anchor.identifier] = place
                arView.session.add(anchor: anchor)
            }
        }

        private func runWorldTracking(in arView: ARView, places: [NearbyPlace], userLocation: CLLocation?) {
            let configuration = ARWorldTrackingConfiguration()
            configuration.worldAlignment = .gravityAndHeading
            arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
            let origin = userLocation ?? CLLocation(
                latitude: NearbyPlaceSearch.fallbackCoordinate.latitude,
                longitude: NearbyPlaceSearch.fallbackCoordinate.longitude
            )
            for (index, place) in places.enumerated() {
                placeLookup[place.renderID] = place
                let anchor = AnchorEntity(world: Self.worldPosition(for: place, from: origin, index: index))
                anchor.addChild(Self.markerEntity(for: place))
                arView.scene.addAnchor(anchor)
            }
        }

        private static func markerEntity(for place: NearbyPlace) -> Entity {
            let container = Entity()
            container.name = place.renderID.uuidString
            container.components.set(BillboardComponent())

            let markerImage = markerImage(for: place)
            let markerMesh = MeshResource.generatePlane(width: 0.92, height: 1.14)
            let marker = ModelEntity(mesh: markerMesh)
            if let cgImage = markerImage.cgImage,
               let texture = try? TextureResource(image: cgImage, withName: place.id, options: .init(semantic: .color)) {
                var material = UnlitMaterial()
                material.color = .init(tint: .white, texture: .init(texture))
                marker.model?.materials = [material]
            }
            container.addChild(marker)
            container.generateCollisionShapes(recursive: true)
            return container
        }

        private static func markerImage(for place: NearbyPlace) -> UIImage {
            let size = CGSize(width: 512, height: 640)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = false
            return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
                let context = renderer.cgContext
                context.setShadow(offset: .zero, blur: 28, color: place.kind.accentColor.withAlphaComponent(0.55).cgColor)
                place.kind.spriteImage.draw(in: CGRect(x: 74, y: 8, width: 364, height: 364))
                context.setShadow(offset: .zero, blur: 0, color: nil)

                let cardRect = CGRect(x: 18, y: 380, width: 476, height: 220)
                let card = UIBezierPath(roundedRect: cardRect, cornerRadius: 44)
                UIColor(white: 0.025, alpha: 0.88).setFill()
                card.fill()
                place.kind.accentColor.withAlphaComponent(0.82).setStroke()
                card.lineWidth = 4
                card.stroke()

                let categoryAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 28, weight: .bold),
                    .foregroundColor: place.kind.accentColor,
                    .kern: 2.2,
                ]
                place.kind.label.uppercased().draw(
                    in: CGRect(x: 48, y: 412, width: 416, height: 36),
                    withAttributes: categoryAttributes
                )

                let paragraph = NSMutableParagraphStyle()
                paragraph.lineBreakMode = .byTruncatingTail
                let titleAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 40, weight: .semibold),
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: paragraph,
                ]
                place.name.draw(
                    in: CGRect(x: 48, y: 456, width: 416, height: 52),
                    withAttributes: titleAttributes
                )

                let distanceAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.monospacedDigitSystemFont(ofSize: 28, weight: .medium),
                    .foregroundColor: UIColor.white.withAlphaComponent(0.66),
                ]
                formatDistance(place.distanceMeters).draw(
                    in: CGRect(x: 48, y: 528, width: 416, height: 36),
                    withAttributes: distanceAttributes
                )
            }
        }

        private static func worldPosition(for place: NearbyPlace, from origin: CLLocation, index: Int) -> SIMD3<Float> {
            let target = CLLocation(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude)
            let bearing = bearingRadians(from: origin.coordinate, to: place.coordinate)
            let distance = Float(min(max(target.distance(from: origin) / 20, 2.0), 20))
            let height = Float(1.35 + Double(index % 3) * 0.42)
            return SIMD3<Float>(sin(Float(bearing)) * distance, height, -cos(Float(bearing)) * distance)
        }

        private static func bearingRadians(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
            let latitude1 = a.latitude * .pi / 180
            let latitude2 = b.latitude * .pi / 180
            let longitudeDelta = (b.longitude - a.longitude) * .pi / 180
            return atan2(
                sin(longitudeDelta) * cos(latitude2),
                cos(latitude1) * sin(latitude2) - sin(latitude1) * cos(latitude2) * cos(longitudeDelta)
            )
        }

        private static func signature(for places: [NearbyPlace], userLocation: CLLocation?) -> String {
            let placeIDs = places.prefix(12).map(\.id).joined(separator: "|")
            let location = userLocation.map {
                "\(String(format: "%.4f", $0.coordinate.latitude)),\(String(format: "%.4f", $0.coordinate.longitude))"
            } ?? "none"
            return "\(placeIDs)-\(location)"
        }
    }
}

private func formatDistance(_ meters: CLLocationDistance) -> String {
    if meters >= 1_000 {
        return String(format: "%.1f km away", meters / 1_000)
    }
    return "\(Int(meters.rounded())) m away"
}
