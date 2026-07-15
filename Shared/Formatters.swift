import Foundation

enum Formatters {
    static func distance(_ meters: Double, imperial: Bool = false) -> String {
        if imperial {
            let miles = meters / 1609.344
            if miles >= 0.1 { return String(format: "%.2f mi", miles) }
            return "\(Int((meters * 3.28084).rounded())) ft"
        }
        return meters >= 1000
            ? String(format: "%.2f km", meters / 1000)
            : "\(Int(meters.rounded())) m"
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }

    static func speed(_ metersPerSecond: Double, imperial: Bool = false) -> String {
        imperial
            ? String(format: "%.1f mph", metersPerSecond * 2.23694)
            : String(format: "%.1f km/h", metersPerSecond * 3.6)
    }
}
