// One of the Shutter theme's panels: a parallelogram whose top is `slant` points to the right of its foot
import SwiftUI

struct ShutterSlant: Shape {
    var slant: CGFloat

    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.minX + slant, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX - slant, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            p.closeSubpath()
        }
    }
}
