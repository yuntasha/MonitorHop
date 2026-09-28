import CoreGraphics

/// Coordinate helpers.
///
/// macOS uses two global coordinate spaces:
/// - **Cocoa** (`NSScreen.frame`, `NSEvent.mouseLocation`): origin at the bottom-left of the
///   primary display, y grows upward.
/// - **Quartz / Accessibility** (`CGWindowList`, `AXPosition`, `CGWarpMouseCursorPosition`):
///   origin at the top-left of the primary display, y grows downward.
///
/// The conversion only depends on the height of the primary display and is its own inverse.
public enum Geometry {
    /// Converts a rect between Cocoa and Quartz global coordinates (the operation is symmetric).
    public static func flip(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: primaryHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    /// Converts a point between Cocoa and Quartz global coordinates (the operation is symmetric).
    public static func flip(_ point: CGPoint, primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    public static func center(of rect: CGRect) -> CGPoint {
        CGPoint(x: rect.midX, y: rect.midY)
    }

    public static func intersectionArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let i = a.intersection(b)
        if i.isNull || i.isEmpty { return 0 }
        return i.width * i.height
    }

    /// Returns the index of the candidate that "owns" `rect`:
    /// 1. the candidate containing the rect's center,
    /// 2. otherwise the candidate with the largest intersection,
    /// 3. otherwise the candidate whose center is closest.
    /// Returns nil only when `candidates` is empty.
    public static func bestMatch(for rect: CGRect, in candidates: [CGRect]) -> Int? {
        guard !candidates.isEmpty else { return nil }
        let c = center(of: rect)
        if let i = candidates.firstIndex(where: { contains($0, c) }) { return i }

        var bestIndex = -1
        var bestArea: CGFloat = 0
        for (i, candidate) in candidates.enumerated() {
            let area = intersectionArea(rect, candidate)
            if area > bestArea { bestArea = area; bestIndex = i }
        }
        if bestIndex >= 0 { return bestIndex }

        var nearest = 0
        var nearestDistance = CGFloat.greatestFiniteMagnitude
        for (i, candidate) in candidates.enumerated() {
            let d = distanceSquared(c, center(of: candidate))
            if d < nearestDistance { nearestDistance = d; nearest = i }
        }
        return nearest
    }

    /// Same as `bestMatch(for:in:)` but for a point.
    public static func bestMatch(for point: CGPoint, in candidates: [CGRect]) -> Int? {
        bestMatch(for: CGRect(origin: point, size: .zero), in: candidates)
    }

    /// Half-open containment (min edges inclusive, max edges exclusive) so that a point on the
    /// shared edge of two adjacent displays belongs to exactly one of them.
    public static func contains(_ rect: CGRect, _ point: CGPoint) -> Bool {
        point.x >= rect.minX && point.x < rect.maxX && point.y >= rect.minY && point.y < rect.maxY
    }

    /// True when every edge of `a` is within `tolerance` of the same edge of `b`.
    public static func approximatelyEqual(_ a: CGRect, _ b: CGRect, tolerance: CGFloat) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.maxX - b.maxX) <= tolerance && abs(a.maxY - b.maxY) <= tolerance
    }

    /// Moves `point` inside `rect` (inset by `inset`) if it is outside.
    public static func clamp(_ point: CGPoint, into rect: CGRect, inset: CGFloat = 1) -> CGPoint {
        let r = rect.insetBy(dx: min(inset, rect.width / 2), dy: min(inset, rect.height / 2))
        return CGPoint(x: min(max(point.x, r.minX), r.maxX), y: min(max(point.y, r.minY), r.maxY))
    }

    private static func distanceSquared(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x, dy = a.y - b.y
        return dx * dx + dy * dy
    }
}
