import Foundation
import simd

struct AngleCalculator {

    /// Compute the interior angle at vertex `b` formed by rays b→a and b→c.
    /// Returns degrees in the range [0, 180].
    static func angle(a: SIMD2<Float>, b: SIMD2<Float>, c: SIMD2<Float>) -> Float {
        let radians = atan2(c.y - b.y, c.x - b.x) - atan2(a.y - b.y, a.x - b.x)
        var deg = abs(radians * 180.0 / .pi)
        if deg > 180.0 { deg = 360.0 - deg }
        return deg
    }

    /// Extend the line through `p1` and `p2` in both directions until it hits the
    /// frame boundary defined by (0,0)–(width, height). Returns the two intersection points.
    static func extendLineToFrame(
        p1: SIMD2<Float>,
        p2: SIMD2<Float>,
        width: Float,
        height: Float
    ) -> (SIMD2<Float>, SIMD2<Float>) {
        let dir = simd_normalize(p2 - p1)
        let forward  = edgeIntersection(origin: p1, direction: dir, width: width, height: height)
        let backward = edgeIntersection(origin: p2, direction: -dir, width: width, height: height)
        return (forward ?? p1, backward ?? p2)
    }

    // MARK: - Private

    private static func edgeIntersection(
        origin: SIMD2<Float>,
        direction: SIMD2<Float>,
        width: Float,
        height: Float
    ) -> SIMD2<Float>? {
        var bestT: Float = .greatestFiniteMagnitude
        var bestPoint: SIMD2<Float>?

        let edges: [(axis: WritableKeyPath<SIMD2<Float>, Float>,
                      cross: WritableKeyPath<SIMD2<Float>, Float>,
                      value: Float, crossMax: Float)] = [
            (\.y, \.x, 0,      width),   // top
            (\.y, \.x, height, width),    // bottom
            (\.x, \.y, 0,      height),   // left
            (\.x, \.y, width,  height)    // right
        ]

        for edge in edges {
            let dAxis = direction[keyPath: edge.axis]
            guard dAxis != 0 else { continue }
            let t = (edge.value - origin[keyPath: edge.axis]) / dAxis
            guard t > 0 else { continue }
            let crossVal = origin[keyPath: edge.cross] + t * direction[keyPath: edge.cross]
            guard crossVal >= 0, crossVal <= edge.crossMax else { continue }
            if t < bestT {
                bestT = t
                var pt = SIMD2<Float>.zero
                pt[keyPath: edge.axis] = edge.value
                pt[keyPath: edge.cross] = crossVal
                bestPoint = pt
            }
        }
        return bestPoint
    }
}
