import XCTest
import simd
@testable import KevLines2_0

final class AngleCalculatorTests: XCTestCase {

    func testRightAngle() {
        let a = SIMD2<Float>(0, 0)
        let b = SIMD2<Float>(0, 1)
        let c = SIMD2<Float>(1, 1)
        let angle = AngleCalculator.angle(a: a, b: b, c: c)
        XCTAssertEqual(angle, 90.0, accuracy: 0.1)
    }

    func testStraightAngle() {
        let a = SIMD2<Float>(0, 0)
        let b = SIMD2<Float>(1, 0)
        let c = SIMD2<Float>(2, 0)
        let angle = AngleCalculator.angle(a: a, b: b, c: c)
        XCTAssertEqual(angle, 180.0, accuracy: 0.1)
    }

    func test45DegreeAngle() {
        let a = SIMD2<Float>(0, 0)
        let b = SIMD2<Float>(1, 0)
        let c = SIMD2<Float>(2, 1)
        let angle = AngleCalculator.angle(a: a, b: b, c: c)
        XCTAssertEqual(angle, 135.0, accuracy: 0.5)
    }

    func testExtendLineToFrame() {
        let p1 = SIMD2<Float>(100, 100)
        let p2 = SIMD2<Float>(200, 100)  // horizontal line
        let (start, end) = AngleCalculator.extendLineToFrame(
            p1: p1, p2: p2, width: 1000, height: 500
        )
        // Should extend to left and right edges
        XCTAssertEqual(start.y, 100, accuracy: 1.0)
        XCTAssertEqual(end.y, 100, accuracy: 1.0)
    }
}
