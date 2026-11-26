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

        var triggeredSource: TimerCenter.AlarmSource?
        timers.onAlarmTriggered = { source, _ in triggeredSource = source }
        timers.startAlarm(source: .countdown, message: "Terminó la cuenta regresiva")
        precondition(timers.activeAlarm == .countdown)
        precondition(timers.alarmMessage == "Terminó la cuenta regresiva")
        timers.countdownReset()
        precondition(timers.activeAlarm == nil && timers.alarmMessage == nil, "Resetting countdown must silence alarm")
        timers.startAlarm(source: .pomodoro, message: "Tiempo de foco terminado")
        precondition(timers.activeAlarm == .pomodoro)
        timers.stopAlarm()
        precondition(timers.activeAlarm == nil && triggeredSource == nil)

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


        precondition(ClipboardContent.pngData(from: png, isPNG: true) == png, "PNG bytes must be preserved")
        precondition(ClipboardContent.pngData(from: Data("invalid".utf8), isPNG: true) == nil)
        precondition(ClipboardContent.pngData(from: Data("invalid".utf8), isPNG: false) == nil)
        let converted = ClipboardContent.pngData(from: bitmap.tiffRepresentation!, isPNG: false)!
        let convertedRep = NSBitmapImageRep(data: converted)!
        precondition(convertedRep.pixelsWide == 4096 && convertedRep.pixelsHigh == 2048,
                     "Clipboard originals must keep their full resolution")
        let longText = String(repeating: "Texto largo 😀\n", count: 10_000)
        let legacy = ClipboardItem(id: UUID(), date: Date(), kind: .text, value: longText, contentKey: "text:" + longText)
        let migrated = ClipboardContent.migrated(legacy)
        precondition(migrated.id == legacy.id && migrated.date == legacy.date && migrated.value == longText)
        let link = ClipboardItem(id: UUID(), date: Date(), kind: .link, value: "https://example.com",
                                 contentKey: "link:https://example.com")
        let migratedLink = ClipboardContent.migrated(link)
        precondition(migratedLink.value == link.value && migratedLink.id == link.id)
        precondition(migratedLink.contentKey == ClipboardContent.key(kind: .link, value: link.value))
        let imageItem = ClipboardItem(id: UUID(), date: Date(), kind: .image, value: "/tmp/image.png", contentKey: "image:legacy")
        precondition(ClipboardContent.migrated(imageItem) == imageItem)
        precondition(migrated.contentKey.count == 76, "Text key has constant size")
        precondition(ClipboardContent.migrated(migrated) == migrated, "Migration is idempotent")
        precondition(ClipboardContent.key(kind: .text, value: longText) == migrated.contentKey, "Recopy deduplicates migrated text")
        precondition(ClipboardContent.key(kind: .link, value: longText) != migrated.contentKey)
        let encodedLegacy = try JSONEncoder().encode(legacy).count
        let encodedNew = try JSONEncoder().encode(migrated).count
        precondition(encodedNew < encodedLegacy * 6 / 10)
        let decoded = try JSONDecoder().decode(ClipboardItem.self, from: JSONEncoder().encode(migrated))
        precondition(decoded == migrated, "New records retain the existing JSON schema")
        var capture = ClipboardCaptureState()
        let first = capture.begin()!
        precondition(capture.begin() == nil, "No overlapping large-image conversions")
        capture.invalidate()
        precondition(!capture.finish(first), "Cleared or disabled captures cannot reappear")
        let second = capture.begin()!
        precondition(capture.finish(second), "New captures work after invalidation")
        precondition(!capture.isProcessing)
        print("Clipboard fixture JSON: \(encodedLegacy) -> \(encodedNew) bytes; full content preserved")
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
