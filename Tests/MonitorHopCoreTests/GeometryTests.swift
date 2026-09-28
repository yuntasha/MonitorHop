import CoreGraphics
import Testing
@testable import MonitorHopCore

@Suite("Geometry")
struct GeometryTests {
    // Real layout of the development machine: external monitor to the left of the built-in one.
    let primaryHeight: CGFloat = 1112
    let externalCocoa = CGRect(x: -1920, y: 327, width: 1920, height: 1080)

    @Test func flipConvertsCocoaToQuartz() {
        let ax = Geometry.flip(externalCocoa, primaryHeight: primaryHeight)
        #expect(ax == CGRect(x: -1920, y: -295, width: 1920, height: 1080))
    }

    @Test func flipIsItsOwnInverse() {
        let rects = [externalCocoa, CGRect(x: 0, y: 0, width: 1710, height: 1112), CGRect(x: 12.5, y: -40, width: 300, height: 200)]
        for r in rects {
            #expect(Geometry.flip(Geometry.flip(r, primaryHeight: primaryHeight), primaryHeight: primaryHeight) == r)
        }
    }

    @Test func primaryDisplayMapsToItself() {
        let primary = CGRect(x: 0, y: 0, width: 1710, height: 1112)
        #expect(Geometry.flip(primary, primaryHeight: primaryHeight) == primary)
    }

    @Test func pointFlip() {
        #expect(Geometry.flip(CGPoint(x: 10, y: 0), primaryHeight: 100) == CGPoint(x: 10, y: 100))
        #expect(Geometry.flip(CGPoint(x: 10, y: 100), primaryHeight: 100) == CGPoint(x: 10, y: 0))
    }

    let screens = [
        CGRect(x: -1920, y: -295, width: 1920, height: 1080), // left
        CGRect(x: 0, y: 0, width: 1710, height: 1112),        // right (primary)
    ]

    @Test func bestMatchUsesCenterFirst() {
        // Mostly on the right screen, center on the right screen.
        #expect(Geometry.bestMatch(for: CGRect(x: -100, y: 100, width: 800, height: 400), in: screens) == 1)
        // Center on the left screen.
        #expect(Geometry.bestMatch(for: CGRect(x: -900, y: 100, width: 800, height: 400), in: screens) == 0)
    }

    @Test func bestMatchFallsBackToOverlapThenDistance() {
        // Center in the gap below the left screen (y > 785) but overlapping it.
        let overlapping = CGRect(x: -1000, y: 700, width: 200, height: 300) // center y 850
        #expect(Geometry.bestMatch(for: overlapping, in: screens) == 0)
        // Completely off-screen far to the right: nearest center wins.
        #expect(Geometry.bestMatch(for: CGRect(x: 5000, y: 0, width: 10, height: 10), in: screens) == 1)
        #expect(Geometry.bestMatch(for: CGRect.zero, in: []) == nil)
    }

    @Test func sharedEdgeBelongsToExactlyOneScreen() {
        let onEdge = CGPoint(x: 0, y: 500)
        #expect(Geometry.contains(screens[1], onEdge))
        #expect(!Geometry.contains(screens[0], onEdge))
        #expect(Geometry.bestMatch(for: onEdge, in: screens) == 1)
    }

    @Test func clampPoint() {
        let r = CGRect(x: 0, y: 0, width: 100, height: 100)
        #expect(Geometry.clamp(CGPoint(x: -5, y: 50), into: r) == CGPoint(x: 1, y: 50))
        #expect(Geometry.clamp(CGPoint(x: 500, y: 500), into: r) == CGPoint(x: 99, y: 99))
        #expect(Geometry.clamp(CGPoint(x: 50, y: 50), into: r) == CGPoint(x: 50, y: 50))
    }

    @Test func approximatelyEqual() {
        let a = CGRect(x: 0, y: 0, width: 100, height: 100)
        #expect(Geometry.approximatelyEqual(a, CGRect(x: 1, y: -1, width: 100, height: 101), tolerance: 2))
        #expect(!Geometry.approximatelyEqual(a, CGRect(x: 5, y: 0, width: 100, height: 100), tolerance: 2))
    }
}
