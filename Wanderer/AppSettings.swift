import MapKit
import Observation
import SwiftUI

@Observable final class AppSettings {
    var mapStyleOption: MapStyleOption {
        didSet { UserDefaults.standard.set(mapStyleOption.rawValue, forKey: Keys.mapStyle) }
    }
    var useImperial: Bool {
        didSet { UserDefaults.standard.set(useImperial, forKey: Keys.useImperial) }
    }
    var nickname: String {
        didSet { UserDefaults.standard.set(nickname, forKey: Keys.nickname) }
    }

    init() {
        let raw = UserDefaults.standard.string(forKey: Keys.mapStyle) ?? ""
        mapStyleOption = MapStyleOption(rawValue: raw) ?? .standard
        useImperial = UserDefaults.standard.bool(forKey: Keys.useImperial)
        nickname = UserDefaults.standard.string(forKey: Keys.nickname) ?? ""
    }

    enum MapStyleOption: String, CaseIterable {
        case standard  = "Standard"
        case satellite = "Satellite"
        case hybrid    = "Hybrid"

        var icon: String {
            switch self {
            case .standard:  return "map"
            case .satellite: return "globe.americas.fill"
            case .hybrid:    return "map.fill"
            }
        }

        var mapStyle: MapStyle {
            switch self {
            case .standard:
                return .standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false)
            case .satellite:
                return .imagery(elevation: .flat)
            case .hybrid:
                return .hybrid(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false)
            }
        }
    }

    private enum Keys {
        static let mapStyle    = "mapStyleOption"
        static let useImperial = "useImperial"
        static let nickname    = "nickname"
    }
}
