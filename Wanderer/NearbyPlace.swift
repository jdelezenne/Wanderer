import CoreLocation
import MapKit
import SwiftUI
import UIKit

enum NearbyPlaceKind: String, CaseIterable, Codable {
    case restaurant
    case cafe
    case attraction

    var label: String {
        switch self {
        case .restaurant: return "Restaurant"
        case .cafe:       return "Cafe"
        case .attraction: return "Attraction"
        }
    }

    var searchQuery: String {
        switch self {
        case .restaurant: return "restaurant"
        case .cafe:       return "cafe"
        case .attraction: return "attraction"
        }
    }

    var categories: [MKPointOfInterestCategory] {
        switch self {
        case .restaurant: return [.restaurant]
        case .cafe:       return [.cafe]
        case .attraction: return [.landmark, .museum, .park, .amusementPark, .theater]
        }
    }

    var color: Color {
        switch self {
        case .restaurant: return .orange
        case .cafe:       return .brown
        case .attraction: return .green
        }
    }

    var spriteImage: UIImage { PixelArtSprite.image(for: self) }
}

// 16×16 pixel art sprites rendered at 8× scale (128×128 px, pixelated, no anti-aliasing)
enum PixelArtSprite {
    static func image(for kind: NearbyPlaceKind) -> UIImage {
        let scale = 8
        let size = 16
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: size * scale, height: size * scale), format: format).image { ctx in
            let grid = pixels(for: kind)
            for (row, cols) in grid.enumerated() {
                for (col, hex) in cols.enumerated() {
                    guard hex != 0 else { continue }
                    ctx.cgContext.setFillColor(color(hex).cgColor)
                    ctx.cgContext.fill(CGRect(x: col * scale, y: row * scale, width: scale, height: scale))
                }
            }
        }
    }

    private static func pixels(for kind: NearbyPlaceKind) -> [[UInt32]] {
        switch kind {
        case .restaurant: return restaurantGrid
        case .cafe:       return cafeGrid
        case .attraction: return attractionGrid
        }
    }

    private static func color(_ hex: UInt32) -> UIColor {
        UIColor(
            red:   CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >>  8) & 0xFF) / 255,
            blue:  CGFloat( hex        & 0xFF) / 255,
            alpha: 1
        )
    }

    // Orange background, white fork & knife
    private static let restaurantGrid: [[UInt32]] = [
        [0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0],
        [0,        0xE87722, 0xE87722, 0xE87722, 0xE87722, 0xE87722, 0xE87722, 0xE87722, 0xE87722, 0xE87722, 0xE87722, 0xE87722, 0xE87722, 0xE87722, 0xE87722, 0],
        [0,        0xE87722, 0xFFFFFF, 0,        0,        0xFFFFFF, 0,        0,        0,        0,        0xFFFFFF, 0,        0,        0xFFFFFF, 0xE87722, 0],
        [0,        0xE87722, 0xFFFFFF, 0,        0,        0xFFFFFF, 0,        0,        0,        0,        0xFFFFFF, 0,        0,        0xFFFFFF, 0xE87722, 0],
        [0,        0xE87722, 0xFFFFFF, 0,        0,        0xFFFFFF, 0,        0,        0,        0,        0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xE87722, 0],
        [0,        0xE87722, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0,        0,        0,        0,        0xFFFFFF, 0,        0,        0xFFFFFF, 0xE87722, 0],
        [0,        0xE87722, 0,        0,        0,        0xFFFFFF, 0,        0,        0,        0,        0xFFFFFF, 0,        0,        0xFFFFFF, 0xE87722, 0],
        [0,        0xE87722, 0,        0,        0,        0xFFFFFF, 0,        0,        0,        0,        0xFFFFFF, 0,        0,        0xFFFFFF, 0xE87722, 0],
        [0,        0xE87722, 0,        0,        0,        0xFFFFFF, 0,        0,        0,        0,        0xFFFFFF, 0,        0,        0xFFFFFF, 0xE87722, 0],
        [0,        0xE87722, 0,        0,        0,        0xFFFFFF, 0,        0,        0,        0,        0xFFFFFF, 0,        0,        0xFFFFFF, 0xE87722, 0],
        [0,        0xE87722, 0,        0,        0,        0xFFFFFF, 0,        0,        0,        0,        0xFFFFFF, 0,        0,        0xFFFFFF, 0xE87722, 0],
        [0,        0xE87722, 0,        0,        0,        0xFFFFFF, 0,        0,        0,        0,        0,        0,        0,        0,        0xE87722, 0],
        [0,        0xE87722, 0xE87722, 0xE87722, 0xE87722, 0xE87722, 0xE87722, 0xE87722, 0xE87722, 0xE87722, 0xE87722, 0xE87722, 0xE87722, 0xE87722, 0xE87722, 0],
        [0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0],
        [0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0],
        [0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0],
    ]

    // Brown background, white coffee cup
    private static let cafeGrid: [[UInt32]] = [
        [0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0],
        [0,        0x7B4F2E, 0x7B4F2E, 0x7B4F2E, 0x7B4F2E, 0x7B4F2E, 0x7B4F2E, 0x7B4F2E, 0x7B4F2E, 0x7B4F2E, 0x7B4F2E, 0x7B4F2E, 0x7B4F2E, 0x7B4F2E, 0x7B4F2E, 0],
        [0,        0x7B4F2E, 0,        0,        0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0,        0,        0,        0,        0x7B4F2E, 0],
        [0,        0x7B4F2E, 0,        0,        0xFFFFFF, 0,        0,        0,        0,        0xFFFFFF, 0xFFFFFF, 0,        0,        0,        0x7B4F2E, 0],
        [0,        0x7B4F2E, 0,        0,        0xFFFFFF, 0,        0,        0,        0,        0xFFFFFF, 0,        0xFFFFFF, 0,        0,        0x7B4F2E, 0],
        [0,        0x7B4F2E, 0,        0,        0xFFFFFF, 0,        0,        0,        0,        0xFFFFFF, 0xFFFFFF, 0,        0,        0,        0x7B4F2E, 0],
        [0,        0x7B4F2E, 0,        0,        0xFFFFFF, 0,        0,        0,        0,        0xFFFFFF, 0,        0,        0,        0,        0x7B4F2E, 0],
        [0,        0x7B4F2E, 0,        0,        0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0,        0,        0,        0,        0x7B4F2E, 0],
        [0,        0x7B4F2E, 0,        0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0,        0,        0,        0x7B4F2E, 0],
        [0,        0x7B4F2E, 0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0x7B4F2E, 0],
        [0,        0x7B4F2E, 0,        0,        0,        0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0,        0,        0,        0,        0,        0x7B4F2E, 0],
        [0,        0x7B4F2E, 0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0x7B4F2E, 0],
        [0,        0x7B4F2E, 0x7B4F2E, 0x7B4F2E, 0x7B4F2E, 0x7B4F2E, 0x7B4F2E, 0x7B4F2E, 0x7B4F2E, 0x7B4F2E, 0x7B4F2E, 0x7B4F2E, 0x7B4F2E, 0x7B4F2E, 0x7B4F2E, 0],
        [0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0],
        [0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0],
        [0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0],
    ]

    // Green background, white 5-pointed star
    private static let attractionGrid: [[UInt32]] = [
        [0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0],
        [0,        0x2E8B57, 0x2E8B57, 0x2E8B57, 0x2E8B57, 0x2E8B57, 0x2E8B57, 0x2E8B57, 0x2E8B57, 0x2E8B57, 0x2E8B57, 0x2E8B57, 0x2E8B57, 0x2E8B57, 0x2E8B57, 0],
        [0,        0x2E8B57, 0,        0,        0,        0,        0,        0xFFFFFF, 0xFFFFFF, 0,        0,        0,        0,        0,        0x2E8B57, 0],
        [0,        0x2E8B57, 0,        0,        0,        0,        0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0,        0,        0,        0,        0x2E8B57, 0],
        [0,        0x2E8B57, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0x2E8B57, 0],
        [0,        0x2E8B57, 0,        0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0,        0x2E8B57, 0],
        [0,        0x2E8B57, 0,        0,        0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0,        0,        0x2E8B57, 0],
        [0,        0x2E8B57, 0,        0,        0,        0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0,        0,        0,        0x2E8B57, 0],
        [0,        0x2E8B57, 0,        0xFFFFFF, 0xFFFFFF, 0,        0,        0xFFFFFF, 0xFFFFFF, 0,        0,        0xFFFFFF, 0xFFFFFF, 0,        0x2E8B57, 0],
        [0,        0x2E8B57, 0xFFFFFF, 0xFFFFFF, 0,        0,        0,        0xFFFFFF, 0xFFFFFF, 0,        0,        0,        0xFFFFFF, 0xFFFFFF, 0x2E8B57, 0],
        [0,        0x2E8B57, 0xFFFFFF, 0,        0,        0,        0,        0xFFFFFF, 0xFFFFFF, 0,        0,        0,        0,        0xFFFFFF, 0x2E8B57, 0],
        [0,        0x2E8B57, 0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0x2E8B57, 0],
        [0,        0x2E8B57, 0x2E8B57, 0x2E8B57, 0x2E8B57, 0x2E8B57, 0x2E8B57, 0x2E8B57, 0x2E8B57, 0x2E8B57, 0x2E8B57, 0x2E8B57, 0x2E8B57, 0x2E8B57, 0x2E8B57, 0],
        [0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0],
        [0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0],
        [0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0,        0],
    ]
}

struct NearbyPlace: Identifiable {
    let id = UUID()
    let name: String
    let coordinate: CLLocationCoordinate2D
    let kind: NearbyPlaceKind
    let distanceMeters: CLLocationDistance

    static let previewPlaces: [NearbyPlace] = [
        NearbyPlace(name: "Station Cafe",     coordinate: CLLocationCoordinate2D(latitude: 35.6817, longitude: 139.7669), kind: .cafe,       distanceMeters: 80),
        NearbyPlace(name: "Garden Restaurant",coordinate: CLLocationCoordinate2D(latitude: 35.6804, longitude: 139.7684), kind: .restaurant, distanceMeters: 140),
        NearbyPlace(name: "City Landmark",    coordinate: CLLocationCoordinate2D(latitude: 35.6822, longitude: 139.7691), kind: .attraction, distanceMeters: 210),
    ]
}

enum NearbyPlaceSearch {
    static let fallbackCoordinate = CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7671)

    static func search(near coordinate: CLLocationCoordinate2D) async -> [NearbyPlace] {
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 1000, longitudinalMeters: 1000)

        return await withTaskGroup(of: [NearbyPlace].self) { group in
            for kind in NearbyPlaceKind.allCases {
                group.addTask { await search(kind: kind, origin: origin, region: region) }
            }

            var places: [NearbyPlace] = []
            for await result in group { places.append(contentsOf: result) }

            var seenKeys = Set<String>()
            let unique = places.filter { place in
                let key = "\(place.name.lowercased())-\(String(format: "%.4f", place.coordinate.latitude))-\(String(format: "%.4f", place.coordinate.longitude))"
                guard !seenKeys.contains(key) else { return false }
                seenKeys.insert(key)
                return true
            }
            return Array(unique.sorted { $0.distanceMeters < $1.distanceMeters }.prefix(12))
        }
    }

    private static func search(kind: NearbyPlaceKind, origin: CLLocation, region: MKCoordinateRegion) async -> [NearbyPlace] {
        let request = MKLocalSearch.Request(naturalLanguageQuery: kind.searchQuery, region: region)
        request.resultTypes = .pointOfInterest
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: kind.categories)
        do {
            let response = try await MKLocalSearch(request: request).start()
            return response.mapItems.compactMap { item in
                NearbyPlace(
                    name: item.name ?? kind.label,
                    coordinate: item.location.coordinate,
                    kind: kind,
                    distanceMeters: item.location.distance(from: origin)
                )
            }
            .filter { $0.distanceMeters <= 1000 }
            .prefix(4)
            .map { $0 }
        } catch {
            return []
        }
    }
}

#Preview("Pixel Art Sprites") {
    HStack(spacing: 24) {
        ForEach(NearbyPlaceKind.allCases, id: \.rawValue) { kind in
            VStack(spacing: 8) {
                Image(uiImage: kind.spriteImage)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 96, height: 96)
                Text(kind.label)
                    .font(.caption)
            }
        }
    }
    .padding()
}
