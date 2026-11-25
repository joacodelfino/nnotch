import Foundation

@main
struct DragShakeTests {
    static func main() {
        func triggered(_ points: [CGFloat], step: Double = 0.1) -> Bool {
            var detector = DragShakeDetector()
            return points.enumerated().contains { detector.sample(x: $0.element, time: Double($0.offset) * step) }
        }
        precondition(triggered([0, 40, 0, 40, 0]))
        precondition(!triggered([0, 40, 80, 120, 160]))
        precondition(!triggered([0, 2, -2, 3, -3]))
        precondition(!triggered([0, 40, 0, 40, 0], step: 0.4))
        var detector = DragShakeDetector()
        for (i, x) in [0.0, 40, 0, 40].enumerated() {
            precondition(!detector.sample(x: x, time: Double(i) * 0.1))
        }
        detector.reset()
        precondition(!detector.sample(x: 0, time: 0.4))
        print("Drag shake checks passed: gesture, straight drag, jitter, slow movement and reset.")
    }
}
