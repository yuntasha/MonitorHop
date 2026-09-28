import CoreGraphics
import Testing
@testable import MonitorHopCore

@Suite("Placement")
struct PlacementTests {
    // AX coordinates (top-left origin).
    let small = CGRect(x: 0, y: 33, width: 1710, height: 990)          // built-in visible area
    let large = CGRect(x: -2560, y: -300, width: 2560, height: 1415)   // 1440p visible area
    let same = CGRect(x: 1710, y: 33, width: 1710, height: 990)

    @Test func keepSizePreservesSizeAndRelativePosition() {
        let window = CGRect(x: 100, y: 133, width: 800, height: 500)
        let result = Placement.targetFrame(window: window, source: small, target: same, mode: .keepSize)
        #expect(result == CGRect(x: 1810, y: 133, width: 800, height: 500))
    }

    @Test func keepSizeShrinksTooLargeWindows() {
        let window = CGRect(x: -2500, y: -250, width: 2400, height: 1300)
        let result = Placement.targetFrame(window: window, source: large, target: small, mode: .keepSize)
        #expect(result.width <= small.width && result.height <= small.height)
        #expect(small.contains(result))
    }

    @Test func maximizedWindowsStayMaximized() {
        let window = small.insetBy(dx: 4, dy: 4)
        for mode in [PlacementMode.keepSize, .proportional, .fill] {
            #expect(Placement.targetFrame(window: window, source: small, target: large, mode: mode) == large)
        }
    }

    @Test func proportionalScales() {
        let source = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let target = CGRect(x: 1000, y: 0, width: 2000, height: 500)
        let window = CGRect(x: 100, y: 200, width: 400, height: 400)
        let result = Placement.targetFrame(window: window, source: source, target: target, mode: .proportional)
        #expect(result == CGRect(x: 1200, y: 100, width: 800, height: 200))
    }

    @Test func centerKeepsSize() {
        let window = CGRect(x: 10, y: 50, width: 600, height: 400)
        let result = Placement.targetFrame(window: window, source: small, target: large, mode: .center)
        #expect(result.size == window.size)
        #expect(abs(result.midX - large.midX) <= 1 && abs(result.midY - large.midY) <= 1)
    }

    @Test func fillUsesVisibleArea() {
        let window = CGRect(x: 10, y: 50, width: 600, height: 400)
        #expect(Placement.targetFrame(window: window, source: small, target: large, mode: .fill) == large)
    }

    @Test func resultIsAlwaysInsideTarget() {
        let windows = [
            CGRect(x: -50, y: -50, width: 300, height: 300),
            CGRect(x: 1600, y: 900, width: 500, height: 500),
            CGRect(x: 0, y: 33, width: 5000, height: 5000),
            CGRect(x: 800, y: 500, width: 1, height: 1),
        ]
        for window in windows {
            for mode in PlacementMode.allCases {
                for (source, target) in [(small, large), (large, small), (small, same)] {
                    let result = Placement.targetFrame(window: window, source: source, target: target, mode: mode)
                    #expect(target.contains(result), "mode \(mode) window \(window) → \(result)")
                    #expect(result.width >= 1 && result.height >= 1)
                }
            }
        }
    }

    @Test func clampShrinksAndMoves() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        #expect(Placement.clamp(CGRect(x: 90, y: -10, width: 50, height: 50), into: bounds) == CGRect(x: 50, y: 0, width: 50, height: 50))
        #expect(Placement.clamp(CGRect(x: 0, y: 0, width: 500, height: 20), into: bounds) == CGRect(x: 0, y: 0, width: 100, height: 20))
    }

    @Test func repositionKeepsSize() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        #expect(Placement.reposition(CGRect(x: 80, y: 80, width: 50, height: 50), into: bounds) == CGRect(x: 50, y: 50, width: 50, height: 50))
        // Larger than bounds: aligned to the min (top-left) corner.
        #expect(Placement.reposition(CGRect(x: 30, y: 30, width: 150, height: 150), into: bounds) == CGRect(x: 0, y: 0, width: 150, height: 150))
    }

    @Test func degenerateTargetReturnsWindow() {
        let window = CGRect(x: 1, y: 2, width: 3, height: 4)
        #expect(Placement.targetFrame(window: window, source: small, target: .zero, mode: .fill) == window)
    }
}
