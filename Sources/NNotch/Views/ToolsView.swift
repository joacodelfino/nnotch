import SwiftUI

/// Herramientas de productividad y monitoreo: grilla 2×2 equilibrada a pantalla completa
/// (Pomodoro, Cuenta Regresiva, Cronómetro y Sistema/Red).
struct ToolsView: View {
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                PomodoroCard()
                CountdownCard()
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: 10) {
                StopwatchCard()
                SystemMonitorCard()
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Pomodoro

struct PomodoroCard: View {
    @EnvironmentObject private var timers: TimerCenter

    private var phaseTint: Color {
        timers.pomodoroPhase == .work ? Color(hex: "#FF453A") : Color(hex: "#30D158")
    }

    private var totalSeconds: Double {
        let mins = timers.pomodoroPhase == .work ? timers.workMinutes : timers.breakMinutes
        return Double(max(mins * 60, 1))
    }

    private var progress: Double {
        let elapsed = totalSeconds - timers.pomodoroRemaining
        return min(max(elapsed / totalSeconds, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                CardTitle(
                    "Pomodoro",
                    symbol: "brain.head.profile",
                    tint: phaseTint
                )
                Text(timers.pomodoroPhase.rawValue)
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(phaseTint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(phaseTint.opacity(0.16)))
                Spacer()
                if timers.pomodoroCycles > 0 {
                    Text("\(timers.pomodoroCycles)×")
                        .font(.system(size: 9.5, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.65))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                }
            }

            HStack(spacing: 12) {
                CircularProgressRing(progress: progress, tint: phaseTint, lineWidth: 3.5) {
                    Image(systemName: timers.pomodoroPhase == .work ? "flame.fill" : "leaf.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(phaseTint)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(TimerCenter.format(timers.pomodoroRemaining))
                        .font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    if timers.activeAlarm == .pomodoro {
                        Text("¡Tiempo cumplido!")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(phaseTint)
                    } else if timers.pomodoroRunning {
                        Text(timers.pomodoroPhase == .work ? "Sesión de foco activa" : "Pausa en curso")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.white.opacity(0.45))
                    } else {
                        HStack(spacing: 8) {
                            CompactStepperPill(label: "Foco", value: $timers.workMinutes, range: 5...90, suffix: "m")
                            CompactStepperPill(label: "Pausa", value: $timers.breakMinutes, range: 1...30, suffix: "m")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: 6) {
                if timers.activeAlarm == .pomodoro {
                    AlarmStopButton(tint: phaseTint) {
                        timers.stopAlarm()
                    }
                } else {
                    PrimaryPillButton(
                        title: timers.pomodoroRunning ? "Pausar" : "Iniciar",
                        symbol: timers.pomodoroRunning ? "pause.fill" : "play.fill",
                        tint: phaseTint
                    ) {
                        timers.pomodoroToggle()
                    }
                }

                RoundIconButton(
                    symbol: "arrow.counterclockwise",
                    tint: .white.opacity(0.22),
                    label: "Reiniciar Pomodoro"
                ) { timers.pomodoroReset() }

                Spacer()
            }
        }
        .islandCard()
    }
}

// MARK: - Countdown

struct CountdownCard: View {
    @EnvironmentObject private var timers: TimerCenter
    private let presets = [5, 10, 15, 30, 60]

    private var isIdle: Bool {
        !timers.countdownRunning && timers.countdownRemaining <= 0
    }

    private var displayedSeconds: TimeInterval {
        timers.countdownRemaining > 0
            ? timers.countdownRemaining
            : TimeInterval(timers.countdownMinutes * 60)
    }

    private var progress: Double {
        let total = Double(max(timers.countdownMinutes * 60, 1))
        guard timers.countdownRemaining > 0 else { return 0 }
        return min(max((total - timers.countdownRemaining) / total, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                CardTitle("Temporizador", symbol: "timer", tint: .orange)
                Spacer()
                if isIdle {
                    HStack(spacing: 3) {
                        ForEach(presets, id: \.self) { mins in
                            let active = timers.countdownMinutes == mins
                            Button {
                                withAnimation(Motion.quick) {
                                    timers.countdownMinutes = mins
                                }
                            } label: {
                                Text(mins == 60 ? "1h" : "\(mins)m")
                                    .font(.system(size: 8.5, weight: active ? .bold : .medium).monospacedDigit())
                                    .foregroundStyle(active ? Color.black : Color.white.opacity(0.6))
                                    .padding(.horizontal, 5.5)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule().fill(active ? Color.orange : Color.white.opacity(0.07))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else if timers.countdownRunning {
                    StatusDotBadge(text: "En curso", tint: .orange)
                } else if timers.activeAlarm == .countdown {
                    StatusDotBadge(text: "¡Alarma!", tint: .orange)
                } else {
                    StatusDotBadge(text: "Pausado", tint: .white.opacity(0.5))
                }
            }

            HStack(spacing: 12) {
                CircularProgressRing(progress: progress, tint: .orange, lineWidth: 3.5) {
                    Image(systemName: timers.activeAlarm == .countdown ? "bell.badge.fill" : "hourglass")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.orange)
                }
                .frame(width: 44, height: 44)

                HStack(spacing: 6) {
                    if isIdle {
                        MiniCircleAdjustButton(symbol: "minus", label: "Restar 1 minuto") {
                            timers.countdownMinutes = max(1, timers.countdownMinutes - (timers.countdownMinutes > 10 ? 5 : 1))
                        }
                    }

                    Text(TimerCenter.format(displayedSeconds))
                        .font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity, alignment: isIdle ? .center : .leading)

                    if isIdle {
                        MiniCircleAdjustButton(symbol: "plus", label: "Sumar minutos") {
                            timers.countdownMinutes = min(240, timers.countdownMinutes + (timers.countdownMinutes >= 10 ? 5 : 1))
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: 6) {
                if timers.activeAlarm == .countdown {
                    AlarmStopButton(tint: .orange) {
                        timers.stopAlarm()
                    }
                } else {
                    PrimaryPillButton(
                        title: timers.countdownRunning ? "Pausar" : "Iniciar",
                        symbol: timers.countdownRunning ? "pause.fill" : "play.fill",
                        tint: .orange
                    ) {
                        timers.countdownRunning ? timers.countdownPause() : timers.countdownStart()
                    }
                }

                RoundIconButton(
                    symbol: "arrow.counterclockwise",
                    tint: .white.opacity(0.22),
                    label: "Reiniciar temporizador"
                ) {
                    timers.countdownReset()
                }

                Spacer()
            }
        }
        .islandCard()
    }
}

// MARK: - Stopwatch

struct StopwatchCard: View {
    @EnvironmentObject private var timers: TimerCenter
    @State private var laps: [TimeInterval] = []

    private var formattedStopwatch: (main: String, tenths: String) {
        let total = max(timers.stopwatchElapsed, 0)
        let tenths = Int((total.truncatingRemainder(dividingBy: 1.0)) * 10)
        return (TimerCenter.format(floor(total)), ".\(tenths)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                CardTitle("Cronómetro", symbol: "stopwatch", tint: .cyan)
                Spacer()
                if timers.stopwatchRunning {
                    StatusDotBadge(text: "Activo", tint: .cyan)
                } else if timers.stopwatchElapsed > 0 {
                    StatusDotBadge(text: "Pausado", tint: .white.opacity(0.5))
                }
            }

            HStack(alignment: .lastTextBaseline, spacing: 1) {
                Text(formattedStopwatch.main)
                    .font(.system(size: 32, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                Text(formattedStopwatch.tenths)
                    .font(.system(size: 16, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(.cyan.opacity(0.85))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let lastLap = laps.first {
                HStack(spacing: 6) {
                    Text("Vuelta \(laps.count)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.cyan.opacity(0.8))
                    Text(TimerCenter.format(lastLap))
                        .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.75))
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.cyan.opacity(0.1)))
            }

            HStack(spacing: 6) {
                PrimaryPillButton(
                    title: timers.stopwatchRunning ? "Pausar" : "Iniciar",
                    symbol: timers.stopwatchRunning ? "pause.fill" : "play.fill",
                    tint: .cyan
                ) {
                    timers.stopwatchToggle()
                }

                if timers.stopwatchRunning {
                    Button {
                        withAnimation(Motion.quick) {
                            laps.insert(timers.stopwatchElapsed, at: 0)
                            if laps.count > 20 { laps.removeLast() }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "flag.fill")
                                .font(.system(size: 8.5, weight: .bold))
                            Text("Vuelta")
                                .font(.system(size: 9.5, weight: .semibold))
                        }
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .background(Capsule().fill(Color.white.opacity(0.1)))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(IslandButtonStyle())
                }

                RoundIconButton(
                    symbol: "arrow.counterclockwise",
                    tint: .white.opacity(0.22),
                    label: "Reiniciar cronómetro"
                ) {
                    timers.stopwatchReset()
                    laps.removeAll()
                }

                Spacer()
            }
        }
        .islandCard()
    }
}

// MARK: - System & Network monitor

struct SystemMonitorCard: View {
    @EnvironmentObject private var stats: SystemStats
    @EnvironmentObject private var network: NetworkMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                CardTitle("Sistema y Red", symbol: "gauge.with.dots.needle.50percent", tint: .orange)
                Spacer()
                if let level = stats.batteryLevel {
                    HStack(spacing: 3) {
                        if stats.batteryCharging {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.green)
                        }
                        Text("%\(level)")
                            .font(.system(size: 9, weight: .semibold).monospacedDigit())
                            .foregroundStyle(level <= 20 ? .red : .white.opacity(0.65))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
                }
            }

            meter(
                label: "CPU",
                fraction: stats.cpuUsage,
                detail: String(format: "%%%.0f", stats.cpuUsage * 100),
                tint: .orange
            )

            meter(
                label: "RAM",
                fraction: stats.memoryUsage,
                detail: String(format: "%.1f / %.0f GB", stats.memoryUsedGB, stats.memoryTotalGB),
                tint: .purple
            )

            HStack(spacing: 10) {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.green)
                    Text(NetworkMonitor.format(network.downloadBps))
                        .font(.system(size: 9.5).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.8))
                }
                HStack(spacing: 3) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.blue)
                    Text(NetworkMonitor.format(network.uploadBps))
                        .font(.system(size: 9.5).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.8))
                }
                Spacer(minLength: 4)
                NetworkSparkline(samples: network.history)
                    .frame(width: 68, height: 16)
            }
        }
        .islandCard()
    }

    private func meter(label: String, fraction: Double, detail: String, tint: Color) -> some View {
        VStack(spacing: 3) {
            HStack {
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                Text(detail)
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.75))
            }
            ProgressView(value: min(max(fraction, 0), 1))
                .tint(tint)
                .animation(Motion.standard, value: fraction)
        }
    }
}

private struct NetworkSparkline: View {
    let samples: [Double]

    var body: some View {
        GeometryReader { geo in
            let peak = max(samples.max() ?? 0, 1024)
            Path { path in
                guard samples.count > 1 else { return }
                let stepX = geo.size.width / CGFloat(max(samples.count - 1, 1))
                for (index, value) in samples.enumerated() {
                    let x = CGFloat(index) * stepX
                    let normalized = CGFloat(min(max(value / peak, 0), 1))
                    let y = geo.size.height * (1 - normalized)
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(Color.green.opacity(0.75), style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Modern Timer Controls

private struct CircularProgressRing<Center: View>: View {
    let progress: Double
    let tint: Color
    let lineWidth: CGFloat
    @ViewBuilder let center: () -> Center

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.09), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(
                    tint,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(Motion.standard, value: progress)
            center()
        }
    }
}

private struct PrimaryPillButton: View {
    let title: String
    let symbol: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 8.5, weight: .bold))
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 11)
            .frame(height: 24)
            .background(Capsule().fill(tint))
            .contentShape(Capsule())
        }
        .buttonStyle(IslandButtonStyle())
    }
}

private struct StatusDotBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tint)
                .frame(width: 5, height: 5)
            Text(text)
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(tint.opacity(0.14)))
    }
}

private struct MiniCircleAdjustButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.white.opacity(0.1)))
                .contentShape(Circle())
        }
        .buttonStyle(IslandButtonStyle())
        .accessibilityLabel(label)
    }
}

private struct CompactStepperPill: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let suffix: String

    var body: some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
            Button {
                if value > range.lowerBound { value -= 1 }
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 13, height: 14)
            }
            .buttonStyle(.plain)
            Text("\(value)\(suffix)")
                .font(.system(size: 9, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
            Button {
                if value < range.upperBound { value += 1 }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 13, height: 14)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.white.opacity(0.06)))
    }
}

struct AlarmStopButton: View {
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "bell.slash.fill")
                    .font(.system(size: 9, weight: .bold))
                Text("Detener")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Capsule().fill(tint))
            .contentShape(Capsule())
        }
        .buttonStyle(IslandButtonStyle())
        .accessibilityLabel("Detener alarma")
    }
}

struct RoundIconButton: View {
    let symbol: String
    let tint: Color
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(tint))
                .contentShape(Circle())
        }
        .buttonStyle(IslandButtonStyle())
        .accessibilityLabel(label)
    }
}
