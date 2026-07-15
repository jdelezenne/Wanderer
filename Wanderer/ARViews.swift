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
    @State private var collectedIDs: Set<UUID> = []

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isARSupported {
                POIARView(
                    places: activePlaces,
                    userLocation: userLocation,
                    onCollect: { place in
                        _ = collectedIDs.insert(place.id)
                        onCollect(place)
                    }
                )
            } else {
                ARSimulatorFallbackView(
                    places: activePlaces,
                    onCollect: { place in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            _ = collectedIDs.insert(place.id)
                        }
                        onCollect(place)
                    }
                )
            }
        }
    }

    private var activePlaces: [NearbyPlace] {
        let source = places.isEmpty ? NearbyPlace.previewPlaces : places
        return source.filter { !collectedIDs.contains($0.id) }
    }

    private var isARSupported: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        ARWorldTrackingConfiguration.isSupported
        #endif
    }
}

struct ARSimulatorFallbackView: View {
    let places: [NearbyPlace]
    let onCollect: (NearbyPlace) -> Void

    var body: some View {
        ZStack {
            VStack(spacing: 8) {
                Image(systemName: "camera.slash")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("Camera AR needs an iPhone")
                    .font(.headline)
                Text("Tap a sprite to collect it")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 190)

            ForEach(Array(places.prefix(9).enumerated()), id: \.element.id) { index, place in
                Button {
                    onCollect(place)
                } label: {
                    VStack(spacing: 6) {
                        Image(uiImage: place.kind.spriteImage)
                            .resizable()
                            .interpolation(.none)
                            .frame(width: 64, height: 64)
                            .background(place.kind.color, in: RoundedRectangle(cornerRadius: 10))
                            .shadow(color: place.kind.color.opacity(0.6), radius: 12)
                        Text(place.name)
                            .font(.caption2.bold())
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .offset(simulatorOffset(for: index))
                .transition(.scale.combined(with: .opacity))
            }
        }
        .foregroundStyle(.white)
    }

    private func simulatorOffset(for index: Int) -> CGSize {
        let columns: [CGFloat] = [-120, 0, 120]
        let row = index / columns.count
        let col = index % columns.count
        return CGSize(width: columns[col], height: CGFloat(row * 110) - 40)
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
            let sig = Self.signature(for: places, userLocation: userLocation)
            guard sig != configSignature else { return }
            configSignature = sig

            arView.scene.anchors.removeAll()
            placeByAnchorID.removeAll()
            placeLookup.removeAll()

            let displayed = Array((places.isEmpty ? NearbyPlace.previewPlaces : places).prefix(12))
            guard !displayed.isEmpty else { return }

            if ARGeoTrackingConfiguration.isSupported, let coord = userLocation?.coordinate {
                ARGeoTrackingConfiguration.checkAvailability(at: coord) { [weak self, weak arView] available, _ in
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
            let pt = recognizer.location(in: arView)
            var hit: Entity? = arView.entity(at: pt)
            while let e = hit, UUID(uuidString: e.name) == nil { hit = e.parent }
            guard let container = hit,
                  let id = UUID(uuidString: container.name),
                  let place = placeLookup[id] else { return }

            var shrunk = container.transform
            shrunk.scale = SIMD3<Float>(repeating: 0.001)
            container.move(to: shrunk, relativeTo: container.parent, duration: 0.3, timingFunction: .easeIn)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                container.removeFromParent()
                self?.onCollect(place)
            }
        }

        func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            guard let arView else { return }
            for anchor in anchors {
                guard let geo = anchor as? ARGeoAnchor,
                      let place = placeByAnchorID[geo.identifier] else { continue }
                placeLookup[place.id] = place
                let anchorEntity = AnchorEntity(anchor: anchor)
                anchorEntity.addChild(Self.spriteEntity(for: place))
                arView.scene.addAnchor(anchorEntity)
            }
        }

        // MARK: - Private

        private func runGeoTracking(in arView: ARView, places: [NearbyPlace]) {
            let config = ARGeoTrackingConfiguration()
            config.planeDetection = []
            arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
            for place in places {
                let anchor = ARGeoAnchor(coordinate: place.coordinate)
                placeByAnchorID[anchor.identifier] = place
                arView.session.add(anchor: anchor)
            }
        }

        private func runWorldTracking(in arView: ARView, places: [NearbyPlace], userLocation: CLLocation?) {
            let config = ARWorldTrackingConfiguration()
            config.worldAlignment = .gravityAndHeading
            arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
            let origin = userLocation ?? CLLocation(
                latitude: NearbyPlaceSearch.fallbackCoordinate.latitude,
                longitude: NearbyPlaceSearch.fallbackCoordinate.longitude
            )
            for (i, place) in places.enumerated() {
                placeLookup[place.id] = place
                let anchor = AnchorEntity(world: Self.worldPosition(for: place, from: origin, index: i))
                anchor.addChild(Self.spriteEntity(for: place))
                arView.scene.addAnchor(anchor)
            }
        }

        private static func spriteEntity(for place: NearbyPlace) -> Entity {
            let container = Entity()
            container.name = place.id.uuidString
            container.components.set(BillboardComponent())

            let spriteMesh = MeshResource.generatePlane(width: 0.7, height: 0.7)
            let sprite = ModelEntity(mesh: spriteMesh)
            if let cgImage = place.kind.spriteImage.cgImage,
               let texture = try? TextureResource(image: cgImage, withName: nil, options: .init(semantic: .color)) {
                var mat = UnlitMaterial()
                mat.color = .init(tint: .white, texture: .init(texture))
                sprite.model?.materials = [mat]
            }
            container.addChild(sprite)

            let labelMesh = MeshResource.generateText(
                place.name,
                extrusionDepth: 0.001,
                font: .systemFont(ofSize: 0.06),
                containerFrame: CGRect(x: -0.35, y: 0, width: 0.7, height: 0.09),
                alignment: .center,
                lineBreakMode: .byTruncatingTail
            )
            let label = ModelEntity(mesh: labelMesh, materials: [UnlitMaterial(color: .white)])
            label.position = [0, -0.44, 0.01]
            container.addChild(label)

            return container
        }

        private static func worldPosition(for place: NearbyPlace, from origin: CLLocation, index: Int) -> SIMD3<Float> {
            let target = CLLocation(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude)
            let bearing = bearingRadians(from: origin.coordinate, to: place.coordinate)
            let dist = Float(min(max(target.distance(from: origin) / 20, 2.0), 20))
            let height = Float(1.2 + Double(index % 3) * 0.5)
            return SIMD3<Float>(sin(Float(bearing)) * dist, height, -cos(Float(bearing)) * dist)
        }

        private static func bearingRadians(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
            let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
            let dLng = (b.longitude - a.longitude) * .pi / 180
            return atan2(sin(dLng) * cos(lat2), cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLng))
        }

        private static func signature(for places: [NearbyPlace], userLocation: CLLocation?) -> String {
            let p = places.prefix(12).map(\.id.uuidString).joined(separator: "|")
            let l = userLocation.map { "\(String(format: "%.4f", $0.coordinate.latitude)),\(String(format: "%.4f", $0.coordinate.longitude))" } ?? "none"
            return "\(p)-\(l)"
        }
    }
}
