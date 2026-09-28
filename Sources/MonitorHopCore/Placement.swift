import CoreGraphics

/// How a window is placed on the destination display when it is moved.
public enum PlacementMode: String, Codable, CaseIterable, Sendable {
    /// Keep the window size (shrunk if it does not fit) and its relative position.
    case keepSize
    /// Scale position and size proportionally to the destination display.
    case proportional
    /// Keep the window size and center it on the destination display.
    case center
    /// Fill the destination display's visible area.
    case fill
}

/// All rects passed to `Placement` must be in the same coordinate space
/// (the app uses Quartz / Accessibility coordinates, top-left origin).
public enum Placement {
    /// Windows within this distance of every edge of the source area are treated as maximized.
    public static let maximizedTolerance: CGFloat = 16

    public static func targetFrame(
        window: CGRect,
        source: CGRect,
        target: CGRect,
        mode: PlacementMode
    ) -> CGRect {
        guard target.width > 0, target.height > 0 else { return window }

        let isMaximized = source.width > 0 && source.height > 0
            && Geometry.approximatelyEqual(window, source, tolerance: maximizedTolerance)

        let result: CGRect
        switch mode {
        case .fill:
            result = target

        case .keepSize:
            if isMaximized {
                result = target
            } else {
                let size = fit(window.size, in: target.size)
                let center = relativeCenter(of: window, from: source, to: target)
                result = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                                width: size.width, height: size.height)
            }

        case .proportional:
            if isMaximized {
                result = target
            } else if source.width <= 0 || source.height <= 0 {
                result = centered(window.size, in: target)
            } else {
                let sx = target.width / source.width
                let sy = target.height / source.height
                result = CGRect(
                    x: target.minX + (window.minX - source.minX) * sx,
                    y: target.minY + (window.minY - source.minY) * sy,
                    width: window.width * sx,
                    height: window.height * sy
                )
            }

        case .center:
            result = centered(window.size, in: target)
        }
        return integral(clamp(result, into: target))
    }

    /// Shrinks `rect` to fit inside `bounds`, then moves it so that it lies completely inside.
    public static func clamp(_ rect: CGRect, into bounds: CGRect) -> CGRect {
        reposition(CGRect(origin: rect.origin, size: fit(rect.size, in: bounds.size)), into: bounds)
    }

    /// Keeps the size and moves `rect` so that as much of it as possible lies inside `bounds`.
    /// A rect larger than `bounds` gets its min corner aligned with `bounds` (top-left in AX space).
    public static func reposition(_ rect: CGRect, into bounds: CGRect) -> CGRect {
        var x = rect.minX, y = rect.minY
        if x + rect.width > bounds.maxX { x = bounds.maxX - rect.width }
        if y + rect.height > bounds.maxY { y = bounds.maxY - rect.height }
        if x < bounds.minX { x = bounds.minX }
        if y < bounds.minY { y = bounds.minY }
        return CGRect(x: x, y: y, width: rect.width, height: rect.height)
    }

    // MARK: - Helpers

    private static func fit(_ size: CGSize, in bounds: CGSize) -> CGSize {
        CGSize(width: min(max(size.width, 1), bounds.width), height: min(max(size.height, 1), bounds.height))
    }

    private static func centered(_ size: CGSize, in target: CGRect) -> CGRect {
        let s = fit(size, in: target.size)
        return CGRect(x: target.midX - s.width / 2, y: target.midY - s.height / 2, width: s.width, height: s.height)
    }

    private static func relativeCenter(of window: CGRect, from source: CGRect, to target: CGRect) -> CGPoint {
        guard source.width > 0, source.height > 0 else { return CGPoint(x: target.midX, y: target.midY) }
        let rx = min(max((window.midX - source.minX) / source.width, 0), 1)
        let ry = min(max((window.midY - source.minY) / source.height, 0), 1)
        return CGPoint(x: target.minX + rx * target.width, y: target.minY + ry * target.height)
    }

    private static func integral(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX.rounded(), y: r.minY.rounded(), width: r.width.rounded(.down), height: r.height.rounded(.down))
    }
}
