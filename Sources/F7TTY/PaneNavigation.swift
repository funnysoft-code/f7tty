import Foundation

/// Rectangles use AppKit coordinates, with increasing Y pointing up.
enum PaneNavigation {
    static func neighbor(of source: UUID, direction: SplitDirection, frames: [UUID: CGRect]) -> UUID? {
        guard let origin = frames[source] else { return nil }
        let horizontal = direction == .left || direction == .right
        return frames.compactMap { id, rect -> (UUID, CGFloat, CGFloat)? in
            guard id != source else { return nil }
            let dx = rect.midX - origin.midX
            let dy = rect.midY - origin.midY
            let forward: CGFloat
            switch direction {
            case .left: forward = -dx
            case .right: forward = dx
            case .up: forward = dy
            case .down: forward = -dy
            }
            guard forward > 0 else { return nil }
            let overlap = horizontal
                ? min(origin.maxY, rect.maxY) - max(origin.minY, rect.minY)
                : min(origin.maxX, rect.maxX) - max(origin.minX, rect.minX)
            guard overlap > 0 else { return nil }
            return (id, forward, horizontal ? abs(dy) : abs(dx))
        }.sorted {
            if $0.1 != $1.1 { return $0.1 < $1.1 }
            if $0.2 != $1.2 { return $0.2 < $1.2 }
            return $0.0.uuidString < $1.0.uuidString
        }.first?.0
    }
}
