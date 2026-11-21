// Flat views placed in three dimensions: Theatre's case in the hand, its lid, the game card. Each face is an ordinary SwiftUI
// view with a 4 × 4 matrix that says where it is in the room; the camera looks down the z axis from `distance` away (x right,
// y down, z towards the viewer, as Core Animation has it). Faces turned away are not drawn, so a closed box needs no sorting.
import simd
import SwiftUI

enum Solid {
    typealias Matrix = simd_double4x4

    static let identity = matrix_identity_double4x4

    static func move(_ x: Double, _ y: Double, _ z: Double = 0) -> Matrix {
        var m = identity
        m.columns.3 = SIMD4(x, y, z, 1)
        return m
    }

    /// about the y axis: a positive angle turns the face's front towards +x (the right)
    static func turnY(_ a: Double) -> Matrix {
        let c = cos(a), s = sin(a)
        return Matrix(columns: (SIMD4(c, 0, -s, 0), SIMD4(0, 1, 0, 0), SIMD4(s, 0, c, 0), SIMD4(0, 0, 0, 1)))
    }

    /// about the x axis: a positive angle turns the face's front towards -y (up)
    static func turnX(_ a: Double) -> Matrix {
        let c = cos(a), s = sin(a)
        return Matrix(columns: (SIMD4(1, 0, 0, 0), SIMD4(0, c, s, 0), SIMD4(0, -s, c, 0), SIMD4(0, 0, 0, 1)))
    }

    /// about the z axis: a positive angle turns the face clockwise on screen
    static func turnZ(_ a: Double) -> Matrix {
        let c = cos(a), s = sin(a)
        return Matrix(columns: (SIMD4(c, s, 0, 0), SIMD4(-s, c, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(0, 0, 0, 1)))
    }

    static func scale(_ k: Double) -> Matrix {
        Matrix(diagonal: SIMD4(k, k, k, 1))
    }

    /// where a point of the model is in the room
    static func point(_ m: Matrix, _ x: Double = 0, _ y: Double = 0, _ z: Double = 0) -> SIMD3<Double> {
        let p = m * SIMD4(x, y, z, 1)
        return SIMD3(p.x, p.y, p.z)
    }

    /// the way a face looks (its front is +z before it is placed)
    static func normal(_ m: Matrix) -> SIMD3<Double> {
        let n = m * SIMD4(0, 0, 1, 0)
        return simd_normalize(SIMD3(n.x, n.y, n.z))
    }

    /// how squarely a face looks at the camera: 1 straight at it, 0 edge on, less than 0 turned away
    static func facing(_ m: Matrix, distance d: Double) -> Double {
        let p = point(m)
        let toCamera = simd_normalize(SIMD3(0, 0, d) - p)
        return simd_dot(normal(m), toCamera)
    }

    /// where a point of the room lands on the screen, from the middle of the picture
    static func onScreen(_ p: SIMD3<Double>, distance d: Double) -> CGPoint {
        let k = d / max(d - p.z, 1)
        return CGPoint(x: p.x * k, y: p.y * k)
    }

    /// The projection for a view of `size` laid out about the middle of the picture: its own middle goes to the face's place
    static func projection(_ m: Matrix, size: CGSize, distance d: Double) -> ProjectionTransform {
        var t = CATransform3DIdentity
        t.m11 = m.columns.0.x; t.m12 = m.columns.0.y; t.m13 = m.columns.0.z; t.m14 = m.columns.0.w
        t.m21 = m.columns.1.x; t.m22 = m.columns.1.y; t.m23 = m.columns.1.z; t.m24 = m.columns.1.w
        t.m31 = m.columns.2.x; t.m32 = m.columns.2.y; t.m33 = m.columns.2.z; t.m34 = m.columns.2.w
        t.m41 = m.columns.3.x; t.m42 = m.columns.3.y; t.m43 = m.columns.3.z; t.m44 = m.columns.3.w
        var lens = CATransform3DIdentity
        lens.m34 = -1 / d
        let toMiddle = CATransform3DMakeTranslation(-size.width / 2, -size.height / 2, 0)
        let back = CATransform3DMakeTranslation(size.width / 2, size.height / 2, 0)
        return ProjectionTransform(CATransform3DConcat(CATransform3DConcat(CATransform3DConcat(toMiddle, t), lens), back))
    }

    /// The six faces of a box about its middle: front, back, left, right, top, bottom, each with its size
    static func box(width w: Double, height h: Double, depth d: Double) -> [Face] {
        [Face(side: .front, matrix: move(0, 0, d / 2), size: CGSize(width: w, height: h)),
         Face(side: .back, matrix: move(0, 0, -d / 2) * turnY(.pi), size: CGSize(width: w, height: h)),
         Face(side: .left, matrix: move(-w / 2, 0, 0) * turnY(-.pi / 2), size: CGSize(width: d, height: h)),
         Face(side: .right, matrix: move(w / 2, 0, 0) * turnY(.pi / 2), size: CGSize(width: d, height: h)),
         Face(side: .top, matrix: move(0, -h / 2, 0) * turnX(.pi / 2), size: CGSize(width: w, height: d)),
         Face(side: .bottom, matrix: move(0, h / 2, 0) * turnX(-.pi / 2), size: CGSize(width: w, height: d))]
    }

    enum BoxSide: Hashable { case front, back, left, right, top, bottom }

    struct Face: Identifiable {
        let side: BoxSide
        let matrix: Matrix
        let size: CGSize
        var id: BoxSide { side }
    }
}

extension View {
    /// This view as a face in the room: laid out at `size`, placed by `matrix`, darker the more it turns from the camera, and
    /// not drawn at all once it faces away
    func solid(_ matrix: Solid.Matrix, size: CGSize, distance: Double, shade: Double = 0.5) -> some View {
        let f = Solid.facing(matrix, distance: distance)
        return self
            .frame(width: size.width, height: size.height)
            .colorMultiply(Color(white: 1 - shade * (1 - min(max(f, 0), 1))))
            .projectionEffect(Solid.projection(matrix, size: size, distance: distance))
            .opacity(f > 0.001 ? 1 : 0)
    }
}
