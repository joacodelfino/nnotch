import AppKit
import Combine

@main
struct PerformanceTests {
    @MainActor
    static func main() throws {
        let timers = TimerCenter()
        func hasTimer() -> Bool {
            let value = Mirror(reflecting: timers).children.first { $0.label == "timer" }!.value
            return Mirror(reflecting: value).children.count != 0
        }
        precondition(!hasTimer(), "Idle timers must not schedule wakeups")
        timers.stopwatchToggle()
        precondition(hasTimer())
        Thread.sleep(forTimeInterval: 0.08)
        timers.countdownStart()
        precondition(timers.stopwatchElapsed >= 0.07, "Starting another timer must preserve elapsed time")
        Thread.sleep(forTimeInterval: 0.08)
        timers.countdownPause()
        precondition(timers.countdownRemaining < 600)
        precondition(hasTimer(), "Stopwatch still needs the shared timer")
        timers.stopwatchToggle()
        precondition(!hasTimer(), "Pausing the last timer must stop wakeups")
        let elapsed = timers.stopwatchElapsed
        Thread.sleep(forTimeInterval: 0.05)
        timers.stopwatchToggle()
        precondition(timers.stopwatchElapsed == elapsed, "Paused time must not count")
        timers.stopwatchReset()
        timers.countdownReset()
        precondition(!hasTimer())
        timers.pomodoroToggle()
        precondition(hasTimer())
        timers.pomodoroReset()
        precondition(!hasTimer())

        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4096, pixelsHigh: 2048,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        memset(bitmap.bitmapData!, 128, bitmap.bytesPerRow * bitmap.pixelsHigh)
        let png = bitmap.representation(using: .png, properties: [:])!
        let thumbnail = ImageThumbnail.make(data: png, maxPixel: 640)!
        let rep = thumbnail.representations[0]
        precondition(rep.pixelsWide == 640 && rep.pixelsHigh == 320)
        precondition(ImageThumbnail.decodedCost(thumbnail) == 819_200)
        precondition(ImageThumbnail.make(data: Data("invalid".utf8), maxPixel: 640) == nil)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        try png.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let small = ImageThumbnail.make(url: url, maxPixel: 128)!
        precondition(small.representations[0].pixelsWide == 128)

        let intervals = [DateInterval(start: Date(timeIntervalSince1970: 10), end: Date(timeIntervalSince1970: 20)),
                         DateInterval(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 15))]
        let merged = CalendarLayout.mergedIntervals(intervals)
        precondition(merged.count == 1 && merged[0].duration == 20)
        precondition(CalendarLayout.mergedIntervals([]).isEmpty)
        let separate = intervals + [DateInterval(start: Date(timeIntervalSince1970: 30), duration: 5)]
        precondition(CalendarLayout.mergedIntervals(separate).count == 2)
        print("PASS: timer lifecycle and overlapping counters; image bounds and invalid data; calendar interval union")
        print("Fixture decoded pixels: 33,554,432 bytes original -> 819,200 bytes thumbnail (97.6% fewer)")
    }
}
