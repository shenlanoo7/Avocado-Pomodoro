import Foundation
import CoreGraphics

/// Keeps the entire timer visible after ordinary dragging and monitor changes.
/// No snapping, remembered edge, concealment, interaction interception or idle policy.
enum VisibleWindow {
    static func frame(_ frame: CGRect, screens: [CGRect]) -> CGRect {
        func area(_ rect: CGRect) -> CGFloat { rect.isNull ? 0 : rect.width * rect.height }
        func distance(_ rect: CGRect) -> CGFloat {
            let dx = max(rect.minX - frame.midX, 0, frame.midX - rect.maxX)
            let dy = max(rect.minY - frame.midY, 0, frame.midY - rect.maxY)
            return dx * dx + dy * dy
        }
        guard let screen = screens.max(by: { a,b in
            let aa = area(frame.intersection(a)), bb = area(frame.intersection(b))
            return aa == bb ? distance(a) > distance(b) : aa < bb
        }) else { return frame }
        var result = frame
        result.origin.x = min(max(frame.minX, screen.minX), max(screen.minX, screen.maxX - frame.width))
        result.origin.y = min(max(frame.minY, screen.minY), max(screen.minY, screen.maxY - frame.height))
        return result
    }
}
