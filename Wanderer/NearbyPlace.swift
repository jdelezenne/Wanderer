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

    var color: Color { Color(uiColor: accentColor) }

    var accentColor: UIColor {
        switch self {
        case .restaurant: return UIColor(red: 0.92, green: 0.39, blue: 0.12, alpha: 1)
        case .cafe:       return UIColor(red: 0.62, green: 0.38, blue: 0.20, alpha: 1)
        case .attraction: return UIColor(red: 0.10, green: 0.65, blue: 0.59, alpha: 1)
        }
    }

    var assetName: String {
        switch self {
        case .restaurant: return "PlaceRestaurant"
        case .cafe:       return "PlaceCafe"
        case .attraction: return "PlaceAttraction"
        }
    }

    var fallbackSystemName: String {
        switch self {
        case .restaurant: return "fork.knife"
        case .cafe:       return "cup.and.saucer.fill"
        case .attraction: return "building.columns.fill"
        }
    }

    var spriteImage: UIImage {
        UIImage(named: assetName)
            ?? UIImage(systemName: fallbackSystemName)?.withTintColor(accentColor, renderingMode: .alwaysOriginal)
            ?? UIImage()
    }
}

struct NearbyPlace: Identifiable {
    let id: String
    let renderID = UUID()
    let name: String
    let coordinate: CLLocationCoordinate2D
    let kind: NearbyPlaceKind
    let distanceMeters: CLLocationDistance
    let address: String?

    init(
        id: String? = nil,
        name: String,
        coordinate: CLLocationCoordinate2D,
        kind: NearbyPlaceKind,
        distanceMeters: CLLocationDistance,
        address: String? = nil
    ) {
        self.id = id ?? Self.fallbackID(name: name, coordinate: coordinate, kind: kind)
        self.name = name
        self.coordinate = coordinate
        self.kind = kind
        self.distanceMeters = distanceMeters
        self.address = address
    }

    private static func fallbackID(name: String, coordinate: CLLocationCoordinate2D, kind: NearbyPlaceKind) -> String {
        "\(kind.rawValue)|\(name.lowercased())|\(String(format: "%.5f", coordinate.latitude))|\(String(format: "%.5f", coordinate.longitude))"
    }

    static let previewPlaces: [NearbyPlace] = [
        NearbyPlace(name: "Station Cafe", coordinate: CLLocationCoordinate2D(latitude: 35.6817, longitude: 139.7669), kind: .cafe, distanceMeters: 80),
        NearbyPlace(name: "Garden Restaurant", coordinate: CLLocationCoordinate2D(latitude: 35.6804, longitude: 139.7684), kind: .restaurant, distanceMeters: 140),
        NearbyPlace(name: "City Landmark", coordinate: CLLocationCoordinate2D(latitude: 35.6822, longitude: 139.7691), kind: .attraction, distanceMeters: 210),
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
                    id: item.identifier?.rawValue,
                    name: item.name ?? kind.label,
                    coordinate: item.location.coordinate,
                    kind: kind,
                    distanceMeters: item.location.distance(from: origin),
                    address: item.address?.fullAddress
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

#Preview("Discovery Icons") {
    HStack(spacing: 20) {
        ForEach(NearbyPlaceKind.allCases, id: \.rawValue) { kind in
            VStack(spacing: 8) {
                Image(uiImage: kind.spriteImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                Text(kind.label)
                    .font(.caption.weight(.semibold))
            }
        }
    }
    .padding()
}
