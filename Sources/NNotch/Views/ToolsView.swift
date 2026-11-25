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
        timers.pomodoroPhase == .work ? .red : .green
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
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                CardTitle(
                    "Pomodoro · \(timers.pomodoroPhase.rawValue)",
                    symbol: "brain.head.profile",
                    tint: phaseTint
                )
                Spacer()
                if timers.pomodoroCycles > 0 {
                    Text("\(timers.pomodoroCycles) \(timers.pomodoroCycles == 1 ? "ciclo" : "ciclos")")
                        .font(.system(size: 9, weight: .semibold).monospacedDigit())
                        .foregroundStyle(phaseTint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(phaseTint.opacity(0.16)))
                }
            }

            Text(TimerCenter.format(timers.pomodoroRemaining))
                .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)

            ProgressView(value: progress)
                .tint(phaseTint)
                .animation(Motion.standard, value: progress)

            HStack(spacing: 8) {
                RoundIconButton(
                    symbol: timers.pomodoroRunning ? "pause.fill" : "play.fill",
                    tint: phaseTint,
                    label: timers.pomodoroRunning ? "Pausar Pomodoro" : "Iniciar Pomodoro"
                ) { timers.pomodoroToggle() }

                RoundIconButton(
                    symbol: "arrow.counterclockwise",
                    tint: .gray,
                    label: "Reiniciar Pomodoro"
                ) { timers.pomodoroReset() }

                Spacer()

                if !timers.pomodoroRunning {
                    HStack(spacing: 10) {
                        MiniStepper(label: "Foco", value: $timers.workMinutes, range: 5...90)
                        MiniStepper(label: "Pausa", value: $timers.breakMinutes, range: 1...30)
                    }
                } else {
                    Text(timers.pomodoroPhase == .work ? "En foco" : "Descansando")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
        }
        .islandCard()
    }
}

// MARK: - Countdown

struct CountdownCard: View {
    @EnvironmentObject private var timers: TimerCenter
    private let presets = [5, 10, 15, 30]

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
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                CardTitle("Cuenta Regresiva", symbol: "timer", tint: .orange)
                Spacer()
                if !timers.countdownRunning && timers.countdownRemaining <= 0 {
                    HStack(spacing: 4) {
                        ForEach(presets, id: \.self) { mins in
                            Button {
                                timers.countdownMinutes = mins
                            } label: {
                                Text("\(mins)m")
                                    .font(.system(size: 9, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(
                                        timers.countdownMinutes == mins ? .orange : .white.opacity(0.45)
                                    )
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule().fill(
                                            timers.countdownMinutes == mins
                                                ? Color.orange.opacity(0.18)
                                                : Color.white.opacity(0.06)
                                        )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Text(TimerCenter.format(displayedSeconds))
                .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)

            ProgressView(value: progress)
                .tint(.orange)
                .animation(Motion.standard, value: progress)

            HStack(spacing: 8) {
                RoundIconButton(
                    symbol: timers.countdownRunning ? "pause.fill" : "play.fill",
                    tint: .orange,
                    label: timers.countdownRunning ? "Pausar cuenta regresiva" : "Iniciar cuenta regresiva"
                ) {
                    timers.countdownRunning ? timers.countdownPause() : timers.countdownStart()
                }

                RoundIconButton(
                    symbol: "arrow.counterclockwise",
                    tint: .gray,
                    label: "Reiniciar cuenta regresiva"
                ) {
                    timers.countdownReset()
                }

                Spacer()

                if !timers.countdownRunning && timers.countdownRemaining <= 0 {
                    MiniStepper(label: "min", value: $timers.countdownMinutes, range: 1...240)
                } else if timers.countdownRunning {
                    Text("En curso")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
        }
        .islandCard()
    }
}

// MARK: - Stopwatch

struct StopwatchCard: View {
    @EnvironmentObject private var timers: TimerCenter

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                CardTitle("Cronómetro", symbol: "stopwatch", tint: .cyan)
                Spacer()
                if timers.stopwatchRunning {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.cyan)
                            .frame(width: 5, height: 5)
                        Text("Activo")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.cyan)
                    }
                }
            }

            Text(TimerCenter.format(timers.stopwatchElapsed))
                .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)

            HStack(spacing: 8) {
                RoundIconButton(
                    symbol: timers.stopwatchRunning ? "pause.fill" : "play.fill",
                    tint: .cyan,
                    label: timers.stopwatchRunning ? "Pausar cronómetro" : "Iniciar cronómetro"
                ) { timers.stopwatchToggle() }

                RoundIconButton(
                    symbol: "arrow.counterclockwise",
                    tint: .gray,
                    label: "Reiniciar cronómetro"
                ) { timers.stopwatchReset() }

                Spacer()

                if timers.stopwatchElapsed > 0 && !timers.stopwatchRunning {
                    Text("Pausado")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.4))
                }
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

// MARK: - Small controls

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
                .background(Circle().fill(tint.opacity(0.55)))
                .padding(2)
                .contentShape(Circle())
        }
        .buttonStyle(IslandButtonStyle())
        .accessibilityLabel(label)
    }
}

struct MiniStepper: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: 4) {
            Text("\(label) \(value)")
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(.white.opacity(0.5))
            VStack(spacing: 0) {
                Button {
                    if value < range.upperBound { value += 1 }
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 16, height: 11)
                        .contentShape(Rectangle())
                }
                .buttonStyle(IslandButtonStyle())
                .accessibilityLabel("Subir \(label)")
                Button {
                    if value > range.lowerBound { value -= 1 }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 16, height: 11)
                        .contentShape(Rectangle())
                }
                .buttonStyle(IslandButtonStyle())
                .accessibilityLabel("Bajar \(label)")
            }
        }
    }
}
