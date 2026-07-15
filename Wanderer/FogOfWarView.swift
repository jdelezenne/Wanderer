import MapKit
import SwiftUI

struct FogOfWarView: View {
    let revealedCoordinates: [CodableCoordinate]
    let visibleRect: MKMapRect

    private let revealRadius: Double = 128
    private let fogColor = Color(red: 0.06, green: 0.07, blue: 0.16, opacity: 0.86)

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(fogColor))

            guard !visibleRect.isNull, visibleRect.size.width > 0 else { return }

            var clearCtx = context
            clearCtx.blendMode = .destinationOut

            for point in revealedCoordinates {
                let mapPoint = MKMapPoint(CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))
                let mpp = MKMetersPerMapPointAtLatitude(point.latitude)
                guard mpp > 0 else { continue }

                let marginPts = revealRadius * 2 / mpp
                guard visibleRect.insetBy(dx: -marginPts, dy: -marginPts).contains(mapPoint) else { continue }

                let center = toScreen(mapPoint, in: visibleRect, size: size)
                let radius = CGFloat(revealRadius / mpp / visibleRect.size.width) * size.width
                guard radius > 0.5 else { continue }

                let holeRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                clearCtx.fill(
                    Path(ellipseIn: holeRect),
                    with: .radialGradient(
                        Gradient(stops: [
                            .init(color: .white, location: 0.00),
                            .init(color: .white, location: 0.55),
                            .init(color: .clear, location: 1.00),
                        ]),
                        center: center,
                        startRadius: 0,
                        endRadius: radius
                    )
                )
            }
        }
        .allowsHitTesting(false)
    }

    private func toScreen(_ mapPoint: MKMapPoint, in rect: MKMapRect, size: CGSize) -> CGPoint {
        CGPoint(
            x: CGFloat((mapPoint.x - rect.origin.x) / rect.size.width)  * size.width,
            y: CGFloat((mapPoint.y - rect.origin.y) / rect.size.height) * size.height
        )
    }
}
