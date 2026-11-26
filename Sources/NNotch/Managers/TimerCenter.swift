import AppKit
import AVFoundation
import Combine
import UserNotifications

/// Pomodoro, countdown and stopwatch in one engine with a single tick source.
@MainActor
final class TimerCenter: ObservableObject {
    // MARK: Alarm state
    enum AlarmSource: Equatable {
        case pomodoro
        case countdown
    }

    @Published private(set) var activeAlarm: AlarmSource?
    @Published private(set) var alarmMessage: String?
    var onAlarmTriggered: ((AlarmSource, String) -> Void)?

    private var alarmPlayer: AVAudioPlayer?
    private var alarmStopWork: DispatchWorkItem?
    private static let alarmWAVData: Data = TimerCenter.buildIPhoneStyleAlarmWAV()

    /// Duration the alarm rings before auto-stopping if not manually dismissed.
    static let alarmDuration: TimeInterval = 15.0
    // MARK: Pomodoro
    enum PomodoroPhase: String {
        case work = "Foco"
        case rest = "Descanso"
    }

    @Published var workMinutes: Int {
        didSet {
            UserDefaults.standard.set(workMinutes, forKey: "pomodoro.work")
            if !pomodoroRunning && pomodoroPhase == .work {
                pomodoroRemaining = TimeInterval(workMinutes * 60)
            }
        }
    }
    @Published var breakMinutes: Int {
        didSet {
            UserDefaults.standard.set(breakMinutes, forKey: "pomodoro.break")
            if !pomodoroRunning && pomodoroPhase == .rest {
                pomodoroRemaining = TimeInterval(breakMinutes * 60)
            }
        }
    }
    @Published private(set) var pomodoroPhase: PomodoroPhase = .work
    @Published private(set) var pomodoroRemaining: TimeInterval = 25 * 60
    @Published private(set) var pomodoroRunning = false
    @Published private(set) var pomodoroCycles = 0

    // MARK: Countdown
    @Published var countdownMinutes: Int = 10
    @Published private(set) var countdownRemaining: TimeInterval = 0
    @Published private(set) var countdownRunning = false

    // MARK: Stopwatch
    @Published private(set) var stopwatchElapsed: TimeInterval = 0
    @Published private(set) var stopwatchRunning = false

    private var timer: Timer?
    private var lastTick = Date()

    init() {
        let work = UserDefaults.standard.integer(forKey: "pomodoro.work")
        let rest = UserDefaults.standard.integer(forKey: "pomodoro.break")
        workMinutes = work > 0 ? work : 25
        breakMinutes = rest > 0 ? rest : 5
        pomodoroRemaining = TimeInterval((work > 0 ? work : 25) * 60)
    }

    deinit {
        timer?.invalidate()
        alarmStopWork?.cancel()
        alarmPlayer?.stop()
    }

    /// No periodic wakeups when all three timers are stopped.
    private func updateTimer() {
        guard pomodoroRunning || countdownRunning || stopwatchRunning else {
            timer?.invalidate()
            timer = nil
            return
        }
        guard timer == nil else { return }
        lastTick = Date()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let now = Date()
        // Duvar saatine bağlı ilerleme: Mac uyusa da geri sayım/pomodoro gerçek
        // zamana göre biter (uyku deltası yutulursa sayaç "geç" bitiyordu).
        let delta = now.timeIntervalSince(lastTick)
        lastTick = now
        guard delta > 0 else { return }

        if pomodoroRunning {
            pomodoroRemaining -= delta
            if pomodoroRemaining <= 0 {
                advancePomodoroPhase()
            }
        }
        if countdownRunning {
            countdownRemaining -= delta
            if countdownRemaining <= 0 {
                countdownRemaining = 0
                countdownRunning = false
                notifyDone(source: .countdown, message: "Terminó la cuenta regresiva")
            }
        }
        if stopwatchRunning {
            stopwatchElapsed += delta
        }
        updateTimer()
    }

    private func advancePomodoroPhase() {
        if pomodoroPhase == .work {
            notifyDone(source: .pomodoro, message: "Tiempo de foco terminado — hora de descansar")
            pomodoroCycles += 1
            pomodoroPhase = .rest
            pomodoroRemaining = TimeInterval(breakMinutes * 60)
        } else {
            notifyDone(source: .pomodoro, message: "Descanso terminado — hora de volver al foco")
            pomodoroPhase = .work
            pomodoroRemaining = TimeInterval(workMinutes * 60)
        }
    }

    private func notifyDone(source: AlarmSource, message: String) {
        startAlarm(source: source, message: message)
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        postNotification(message)
        onAlarmTriggered?(source, message)
    }

    // MARK: - iPhone-style repeating alarm sound

    func startAlarm(source: AlarmSource, message: String) {
        stopAlarm()
        activeAlarm = source
        alarmMessage = message

        do {
            let player = try AVAudioPlayer(data: Self.alarmWAVData)
            player.numberOfLoops = -1
            player.volume = 0.9
            player.prepareToPlay()
            player.play()
            alarmPlayer = player
        } catch {
            NSSound(named: "Glass")?.play()
        }

        let work = DispatchWorkItem { [weak self] in
            self?.stopAlarm()
        }
        alarmStopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.alarmDuration, execute: work)
    }

    func stopAlarm() {
        alarmStopWork?.cancel()
        alarmStopWork = nil
        alarmPlayer?.stop()
        alarmPlayer = nil
        if activeAlarm != nil { activeAlarm = nil }
        if alarmMessage != nil { alarmMessage = nil }
    }

    /// Synthesizes a 1-second stereo/mono 16-bit PCM WAV buffer with the classic iPhone
    /// morning alarm pattern: 4 rapid dual-tone harmonic pulses ("beep-beep-beep-beep")
    /// followed by a half-second pause, designed to loop seamlessly.
    nonisolated private static func buildIPhoneStyleAlarmWAV() -> Data {
        let sampleRate = 44_100
        let durationSeconds = 1.0
        let totalSamples = Int(Double(sampleRate) * durationSeconds)
        var samples = [Int16](repeating: 0, count: totalSamples)

        // Classic bright wake-up alarm frequencies (A5 880 Hz + E6 1318.5 Hz + A6 1760 Hz warm chime/beep)
        let f1 = 1046.50 // C6
        let f2 = 1318.51 // E6
        let f3 = 2093.00 // C7 overtone

        // 4 rapid pulses at 0.00s, 0.13s, 0.26s, 0.39s (each 0.095s long), rest is silence until 1.0s
        let pulseStarts: [Double] = [0.00, 0.13, 0.26, 0.39]
        let pulseLength: Double = 0.095
        let attack: Double = 0.006
        let release: Double = 0.018

        for i in 0..<totalSamples {
            let t = Double(i) / Double(sampleRate)
            var env = 0.0
            for start in pulseStarts {
                let local = t - start
                if local >= 0 && local < pulseLength {
                    if local < attack {
                        env = local / attack
                    } else if local > pulseLength - release {
                        env = max((pulseLength - local) / release, 0)
                    } else {
                        env = 1.0
                    }
                    break
                }
            }
            guard env > 0 else { continue }
            let wave = 0.58 * sin(2.0 * .pi * f1 * t)
                + 0.28 * sin(2.0 * .pi * f2 * t)
                + 0.14 * sin(2.0 * .pi * f3 * t)
            let clamped = max(min(wave * env * 0.85, 1.0), -1.0)
            samples[i] = Int16(clamped * Double(Int16.max))
        }

        let dataSize = UInt32(totalSamples * MemoryLayout<Int16>.size)
        let fileSize = 36 + dataSize
        var wav = Data(capacity: Int(44 + dataSize))

        func appendASCII(_ s: String) { wav.append(contentsOf: s.utf8) }
        func appendUInt32(_ v: UInt32) {
            var le = v.littleEndian
            withUnsafeBytes(of: &le) { wav.append(contentsOf: $0) }
        }
        func appendUInt16(_ v: UInt16) {
            var le = v.littleEndian
            withUnsafeBytes(of: &le) { wav.append(contentsOf: $0) }
        }

        appendASCII("RIFF")
        appendUInt32(fileSize)
        appendASCII("WAVE")
        appendASCII("fmt ")
        appendUInt32(16) // PCM chunk size
        appendUInt16(1)  // AudioFormat = 1 (PCM)
        appendUInt16(1)  // NumChannels = 1 (Mono)
        appendUInt32(UInt32(sampleRate))
        appendUInt32(UInt32(sampleRate * 2)) // ByteRate
        appendUInt16(2)  // BlockAlign
        appendUInt16(16) // BitsPerSample
        appendASCII("data")
        appendUInt32(dataSize)

        samples.withUnsafeBufferPointer { buf in
            wav.append(UnsafeBufferPointer(
                start: UnsafeRawPointer(buf.baseAddress!).assumingMemoryBound(to: UInt8.self),
                count: Int(dataSize)
            ))
        }
        return wav
    }

    // MARK: - Sistem bildirimi

    /// Ses kapalıyken ya da kullanıcı Mac'ten uzaktayken bitiş kaçmasın diye
    /// sistem bildirimi de gönderilir. Bundle dışı çalıştırmada (swift run)
    /// UNUserNotificationCenter crash ettiği için bundle kontrolüyle korunur.
    private var notificationAuthRequested = false

    /// Zamanlayıcı BAŞLARKEN istenir; bitişte istemek ilk bildirimi kaçırırdı.
    private func requestNotificationAuthIfNeeded() {
        guard Bundle.main.bundleIdentifier != nil, !notificationAuthRequested else { return }
        notificationAuthRequested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    private func postNotification(_ message: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = "nnotch"
        content.body = message
        // Ses zaten NSSound ile çalınıyor; bildirim sessiz kalsın (çift ses olmasın).
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }

    // MARK: - Pomodoro controls

    func pomodoroToggle() {
        if activeAlarm == .pomodoro { stopAlarm() }
        tick()
        pomodoroRunning.toggle()
        updateTimer()
        if pomodoroRunning { requestNotificationAuthIfNeeded() }
    }

    func pomodoroReset() {
        if activeAlarm == .pomodoro { stopAlarm() }
        tick()
        defer { updateTimer() }
        pomodoroRunning = false
        pomodoroPhase = .work
        pomodoroRemaining = TimeInterval(workMinutes * 60)
        pomodoroCycles = 0
    }

    // MARK: - Countdown controls

    func countdownStart() {
        if activeAlarm == .countdown { stopAlarm() }
        tick()
        defer { updateTimer() }
        if countdownRemaining <= 0 {
            countdownRemaining = TimeInterval(countdownMinutes * 60)
        }
        countdownRunning = true
        requestNotificationAuthIfNeeded()
    }

    func countdownPause() {
        if activeAlarm == .countdown { stopAlarm() }
        tick()
        countdownRunning = false
        updateTimer()
    }

    func countdownReset() {
        if activeAlarm == .countdown { stopAlarm() }
        tick()
        defer { updateTimer() }
        countdownRunning = false
        countdownRemaining = 0
    }

    // MARK: - Stopwatch controls

    func stopwatchToggle() {
        tick()
        stopwatchRunning.toggle()
        updateTimer()
    }

    func stopwatchReset() {
        tick()
        defer { updateTimer() }
        stopwatchRunning = false
        stopwatchElapsed = 0
    }

    // MARK: - Collapsed pill badge

    /// Short text shown next to the notch while a timer runs.
    var collapsedBadge: String? {
        if pomodoroRunning {
            return Self.format(pomodoroRemaining)
        }
        if countdownRunning {
            return Self.format(countdownRemaining)
        }
        if stopwatchRunning {
            return Self.format(stopwatchElapsed)
        }
        return nil
    }

    static func format(_ interval: TimeInterval) -> String {
        let total = max(Int(interval.rounded()), 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
