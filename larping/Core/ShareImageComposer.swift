import CoreLocation
import MapKit
import UIKit

/// Builds the shareable activity card: the recorded route as an accent-color
/// line over either a custom photo (full-bleed, dimmed) or a deep space-black
/// background, with the sport icon on the left of a "LARPING <SPORT>" header
/// and stats centered in full white. System font throughout. Background is
/// always space-dark regardless of the app's light/dark theme; only the route
/// line adopts the current adaptive brand accent (lime dark / #463CFF light).
enum ShareImageComposer {
    static let canvasSize = CGSize(width: 1080, height: 1920) // Instagram Story ratio

    static let white = UIColor.white
    static let spaceBlack = UIColor(red: 0.055, green: 0.067, blue: 0.082, alpha: 1) // Grok-style near-black
    static var routeColor: UIColor { UIColor(named: "Accent") ?? white }

    struct Stats {
        let symbolName: String
        let sportLabel: String
        let distance: String
        let duration: String
        let paceOrSpeed: String
        let date: String
    }

    static func compose(
        photo: UIImage?,
        coordinates: [CLLocationCoordinate2D],
        stats: Stats,
        routeRevealFraction: Double = 1
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)

        let width = canvasSize.width

        return renderer.image { context in
            let bounds = CGRect(origin: .zero, size: canvasSize)
            let cgContext = context.cgContext

            if let photo {
                draw(photo, filling: bounds)
                UIColor.black.withAlphaComponent(0.48).setFill()
                cgContext.fill(bounds)
            } else {
                spaceBlack.setFill()
                cgContext.fill(bounds)
            }

            drawHeader(stats, canvasWidth: width)

            drawRoute(coordinates, canvasWidth: width, revealFraction: routeRevealFraction)

            drawStats(stats, canvasWidth: width)
            drawFooter(canvasWidth: width)
        }
    }

    /// Second template: a dedicated card with real map imagery (MapKit
    /// snapshot) and the route overlaid on it, instead of a plain line on a
    /// flat background. Same header/stats/footer treatment as `compose`.
    static func composeMapCard(coordinates: [CLLocationCoordinate2D], stats: Stats) async -> UIImage {
        let width = canvasSize.width
        let cardRect = CGRect(x: 54, y: 480, width: width - 108, height: 620)
        let snapshot = coordinates.count > 1 ? await snapshotMap(coordinates: coordinates, size: cardRect.size) : nil

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)

        return renderer.image { context in
            let bounds = CGRect(origin: .zero, size: canvasSize)
            let cgContext = context.cgContext
            spaceBlack.setFill()
            cgContext.fill(bounds)

            drawHeader(stats, canvasWidth: width)

            let cardPath = UIBezierPath(roundedRect: cardRect, cornerRadius: 28)
            cgContext.saveGState()
            cardPath.addClip()
            if let snapshot {
                snapshot.image.draw(in: cardRect)
                UIColor.black.withAlphaComponent(0.15).setFill()
                cgContext.fill(cardRect)
                drawRoute(onto: snapshot, coordinates: coordinates, cardRect: cardRect)
            } else {
                spaceBlack.setFill()
                cgContext.fill(cardRect)
            }
            cgContext.restoreGState()
            routeColor.withAlphaComponent(0.6).setStroke()
            cardPath.lineWidth = 2
            cardPath.stroke()

            drawStats(stats, canvasWidth: width, startY: cardRect.maxY + 70)
            drawFooter(canvasWidth: width)
        }
    }

    /// Snapshots real map tiles for the route's bounding box, padded so the
    /// path doesn't touch the card edges.
    private static func snapshotMap(coordinates: [CLLocationCoordinate2D], size: CGSize) async -> MKMapSnapshotter.Snapshot? {
        let lats = coordinates.map(\.latitude)
        let lngs = coordinates.map(\.longitude)
        let minLat = lats.min()!, maxLat = lats.max()!
        let minLng = lngs.min()!, maxLng = lngs.max()!
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.3, 0.004),
            longitudeDelta: max((maxLng - minLng) * 1.3, 0.004)
        )

        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: center, span: span)
        options.size = size
        options.scale = 1
        options.mapType = .standard
        options.showsBuildings = false

        return try? await MKMapSnapshotter(options: options).start()
    }

    /// Draws the route on top of an already-rendered map snapshot, using the
    /// snapshot's own coordinate→point conversion so it lines up with the
    /// tiles exactly.
    private static func drawRoute(onto snapshot: MKMapSnapshotter.Snapshot, coordinates: [CLLocationCoordinate2D], cardRect: CGRect) {
        guard coordinates.count > 1 else { return }
        let path = UIBezierPath()
        for (index, coordinate) in coordinates.enumerated() {
            let point = snapshot.point(for: coordinate)
            let translated = CGPoint(x: cardRect.minX + point.x, y: cardRect.minY + point.y)
            index == 0 ? path.move(to: translated) : path.addLine(to: translated)
        }
        path.lineWidth = 10
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        routeColor.setStroke()
        path.stroke()
    }

    private static func draw(_ image: UIImage, filling rect: CGRect) {
        let scale = max(rect.width / image.size.width, rect.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let origin = CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
        image.draw(in: CGRect(origin: origin, size: size))
    }

    /// Large sport icon centered at the top, with a smaller "LARPING <SPORT>"
    /// header + date centered beneath it.
    private static func drawHeader(_ stats: Stats, canvasWidth: CGFloat) {
        let iconBox: CGFloat = 230
        if let glyph = UIImage(systemName: stats.symbolName, withConfiguration: UIImage.SymbolConfiguration(pointSize: iconBox, weight: .bold)) {
            let tinted = glyph.withTintColor(white)
            let glyphSize = tinted.size
            let scale = min(iconBox / glyphSize.width, iconBox / glyphSize.height)
            let size = CGSize(width: glyphSize.width * scale, height: glyphSize.height * scale)
            tinted.draw(in: CGRect(
                x: canvasWidth / 2 - size.width / 2,
                y: 130,
                width: size.width,
                height: size.height
            ))
        }

        let title = NSAttributedString(string: "LARPING \(stats.sportLabel.uppercased())", attributes: [
            .font: UIFont.systemFont(ofSize: 54, weight: .heavy),
            .foregroundColor: white,
        ])
        let date = NSAttributedString(string: stats.date, attributes: [
            .font: UIFont.systemFont(ofSize: 40, weight: .semibold),
            .foregroundColor: white.withAlphaComponent(0.78),
        ])

        drawCentered(title, atY: 410, canvasWidth: canvasWidth)
        drawCentered(date, atY: 410 + title.size().height + 12, canvasWidth: canvasWidth)
    }

    /// Draws the recorded route as a stroked accent-color line, scaled to fit a
    /// region whose aspect exactly matches the route's own bounding box, so the
    /// path is always centered with symmetric margins on all four sides — never
    /// shifted toward one edge — no matter how big or small the route is.
    /// `revealFraction` (0...1) draws only the leading portion of the route in
    /// recorded point order, for the animated video export. No endpoint markers.
    private static func drawRoute(_ coordinates: [CLLocationCoordinate2D], canvasWidth: CGFloat, revealFraction: Double = 1) {
        guard coordinates.count > 1 else { return }

        let lats = coordinates.map(\.latitude)
        let lngs = coordinates.map(\.longitude)
        let minLat = lats.min()!, maxLat = lats.max()!
        let minLng = lngs.min()!, maxLng = lngs.max()!
        let latSpan = max(maxLat - minLat, 0.0001)
        let lngSpan = max(maxLng - minLng, 0.0001)

        // Available canvas area for the route (clear of header/stats).
        let available = CGRect(x: 54, y: 560, width: canvasWidth - 108, height: 410)
        // Match the fit rect's aspect to the route's own aspect, then center it
        // in `available` → symmetric margins around the path by construction.
        let routeAspect = lngSpan / latSpan
        let availableAspect = available.width / available.height
        var region = available
        if routeAspect > availableAspect {
            region.size.height = available.width / routeAspect
            region.origin.y = available.midY - region.height / 2
            region.size.width = available.width
        } else {
            region.size.width = available.height * routeAspect
            region.origin.x = available.midX - region.width / 2
            region.size.height = available.height
        }

        let scale = region.width / lngSpan // == region.height / latSpan
        let points = coordinates.map { coordinate -> CGPoint in
            CGPoint(
                x: region.minX + (coordinate.longitude - minLng) * scale,
                y: region.minY + (maxLat - coordinate.latitude) * scale
            )
        }

        let revealCount = max(2, Int(Double(points.count) * revealFraction))
        let visiblePoints = Array(points.prefix(revealCount))

        let path = UIBezierPath()
        path.move(to: visiblePoints[0])
        visiblePoints.dropFirst().forEach { path.addLine(to: $0) }
        path.lineWidth = 16
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        routeColor.withAlphaComponent(0.95).setStroke()
        path.stroke()

        // Leading dot marks the current tip while the route is still being
        // revealed (video export); the finished static image has none.
        if revealFraction < 1, let tip = visiblePoints.last {
            let dotRect = CGRect(x: tip.x - 14, y: tip.y - 14, width: 28, height: 28)
            routeColor.setFill()
            UIBezierPath(ovalIn: dotRect).fill()
            let outline = UIBezierPath(ovalIn: dotRect)
            outline.lineWidth = 3
            white.setStroke()
            outline.stroke()
        }
    }

    /// Stats rendered as one centered column — three rows of label + value.
    private static func drawStats(_ stats: Stats, canvasWidth: CGFloat, startY: CGFloat = 1020) {
        let rows: [(String, String)] = [
            ("DISTANCE", stats.distance),
            ("DURATION", stats.duration),
            ("PACE", stats.paceOrSpeed),
        ]
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 34, weight: .medium),
            .foregroundColor: white.withAlphaComponent(0.62),
        ]
        let valueAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 64, weight: .heavy),
            .foregroundColor: white,
        ]

        var y: CGFloat = startY
        for row in rows {
            drawCentered(NSAttributedString(string: row.0, attributes: labelAttrs), atY: y, canvasWidth: canvasWidth)
            let value = NSAttributedString(string: row.1, attributes: valueAttrs)
            drawCentered(value, atY: y + 42, canvasWidth: canvasWidth)
            y += 42 + value.size().height + 46
        }
    }

    /// `LogoHorizontal` wordmark (replaces the old plain-text watermark) with
    /// the repo URL right below it, positioned high enough to clear Instagram
    /// Story's reply input area.
    private static func drawFooter(canvasWidth: CGFloat) {
        var logoBottom: CGFloat = 1580
        if let logo = UIImage(named: "LogoHorizontal") {
            let tinted = logo.withTintColor(white.withAlphaComponent(0.85), renderingMode: .alwaysTemplate)
            let height: CGFloat = 44
            let size = CGSize(width: tinted.size.width * (height / tinted.size.height), height: height)
            tinted.draw(in: CGRect(x: (canvasWidth - size.width) / 2, y: 1560, width: size.width, height: size.height))
            logoBottom = 1560 + size.height
        }

        let repo = NSAttributedString(string: "github.com/ramadhanep/larping", attributes: [
            .font: UIFont.systemFont(ofSize: 30, weight: .semibold),
            .foregroundColor: white.withAlphaComponent(0.72),
        ])
        drawCentered(repo, atY: logoBottom + 20, canvasWidth: canvasWidth)
    }

    private static func drawCentered(_ string: NSAttributedString, atY y: CGFloat, canvasWidth: CGFloat) {
        let size = string.size()
        string.draw(at: CGPoint(x: (canvasWidth - size.width) / 2, y: y))
    }
}