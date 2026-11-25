import SwiftUI

/// Productivity toolbox: pomodoro, countdown, stopwatch, water, counter,
/// days-left events and the system monitor.
struct ToolsView: View {
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 10) {
                PomodoroCard().frame(height: 150)
                CountdownCard().frame(height: 150)
                StopwatchCard().frame(height: 150)
                WaterCard().frame(height: 140)
                CounterCard().frame(height: 140)
                SystemMonitorCard().frame(height: 140)
            }
            DaysLeftCard()
                .frame(minHeight: 120)
                .padding(.top, 10)
        }
    }
}

// MARK: - Pomodoro

struct PomodoroCard: View {
    @EnvironmentObject private var timers: TimerCenter

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CardTitle(
                "Pomodoro · \(timers.pomodoroPhase.rawValue)",
                symbol: "brain.head.profile",
                tint: timers.pomodoroPhase == .work ? .red : .green
            )
            Spacer(minLength: 0)
            Text(TimerCenter.format(timers.pomodoroRemaining))
                .font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
            if timers.pomodoroCycles > 0 {
                Text("\(timers.pomodoroCycles) ciclos completados")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity)
            }
            Spacer(minLength: 0)
            HStack {
                RoundIconButton(
                    symbol: timers.pomodoroRunning ? "pause.fill" : "play.fill",
                    tint: .red,
                    label: timers.pomodoroRunning ? "Pausar Pomodoro" : "Iniciar Pomodoro"
                ) { timers.pomodoroToggle() }
                RoundIconButton(symbol: "arrow.counterclockwise", tint: .gray, label: "Reiniciar Pomodoro") {
                    timers.pomodoroReset()
                }
                Spacer()
                if !timers.pomodoroRunning {
                    VStack(alignment: .trailing, spacing: 2) {
                        MiniStepper(label: "Foco", value: $timers.workMinutes, range: 5...90)
                        MiniStepper(label: "Pausa", value: $timers.breakMinutes, range: 1...30)
                    }
                }
            }
        }
        .islandCard()
    }
}

// MARK: - Countdown

struct CountdownCard: View {
    @EnvironmentObject private var timers: TimerCenter

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CardTitle("Cuenta Regresiva", symbol: "timer", tint: .orange)
            Spacer(minLength: 0)
            Text(
                TimerCenter.format(
                    timers.countdownRemaining > 0
                        ? timers.countdownRemaining
                        : TimeInterval(timers.countdownMinutes * 60)
                )
            )
            .font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
            HStack {
                RoundIconButton(
                    symbol: timers.countdownRunning ? "pause.fill" : "play.fill",
                    tint: .orange,
                    label: timers.countdownRunning ? "Pausar cuenta regresiva" : "Iniciar cuenta regresiva"
                ) {
                    timers.countdownRunning ? timers.countdownPause() : timers.countdownStart()
                }
                RoundIconButton(symbol: "arrow.counterclockwise", tint: .gray, label: "Reiniciar cuenta regresiva") {
                    timers.countdownReset()
                }
                Spacer()
                if !timers.countdownRunning && timers.countdownRemaining <= 0 {
                    MiniStepper(label: "min", value: $timers.countdownMinutes, range: 1...240)
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
        VStack(alignment: .leading, spacing: 6) {
            CardTitle("Cronómetro", symbol: "stopwatch", tint: .cyan)
            Spacer(minLength: 0)
            Text(TimerCenter.format(timers.stopwatchElapsed))
                .font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
            HStack {
                RoundIconButton(
                    symbol: timers.stopwatchRunning ? "pause.fill" : "play.fill",
                    tint: .cyan,
                    label: timers.stopwatchRunning ? "Pausar cronómetro" : "Iniciar cronómetro"
                ) { timers.stopwatchToggle() }
                RoundIconButton(symbol: "arrow.counterclockwise", tint: .gray, label: "Reiniciar cronómetro") {
                    timers.stopwatchReset()
                }
                Spacer()
            }
        }
        .islandCard()
    }
}

// MARK: - Water

struct WaterCard: View {
    @EnvironmentObject private var habits: HabitStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CardTitle("Agua", symbol: "drop.fill", tint: .blue)
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(habits.waterCount)")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("/ \(habits.waterGoal) vasos")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.45))
            }
            .frame(maxWidth: .infinity)
            ProgressView(value: Double(habits.waterCount), total: Double(max(habits.waterGoal, 1)))
                .tint(.blue)
                .animation(Motion.standard, value: habits.waterCount)
            Spacer(minLength: 0)
            HStack {
                RoundIconButton(symbol: "minus", tint: .gray, label: "Restar un vaso") { habits.undoWater() }
                RoundIconButton(symbol: "plus", tint: .blue, label: "Sumar un vaso") { habits.drinkWater() }
                Spacer()
                MiniStepper(label: "Meta", value: $habits.waterGoal, range: 1...20)
            }
        }
        .islandCard()
        .onAppear { habits.rolloverIfNeeded() }
    }
}

// MARK: - Counter

struct CounterCard: View {
    @EnvironmentObject private var habits: HabitStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CardTitle("Contador", symbol: "number.circle.fill", tint: .mint)
            Spacer(minLength: 0)
            Text("\(habits.counterValue)")
                .font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
            HStack {
                RoundIconButton(symbol: "minus", tint: .gray, label: "Restar") { habits.counterValue -= 1 }
                RoundIconButton(symbol: "plus", tint: .mint, label: "Sumar") { habits.counterValue += 1 }
                Spacer()
                Button("Cero") { habits.counterValue = 0 }
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .islandCard()
    }
}

// MARK: - System monitor

struct SystemMonitorCard: View {
    @EnvironmentObject private var stats: SystemStats

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardTitle("Sistema", symbol: "gauge.with.dots.needle.50percent", tint: .orange)
            Spacer(minLength: 0)
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
            if let level = stats.batteryLevel {
                meter(
                    label: "Batería",
                    fraction: Double(level) / 100,
                    detail: stats.batteryCharging ? "%\(level) ⚡︎" : "%\(level)",
                    tint: level <= 20 ? .red : .green
                )
            }
            Spacer(minLength: 0)
        }
        .islandCard()
    }

    private func meter(label: String, fraction: Double, detail: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                Text(detail)
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
            }
            ProgressView(value: min(max(fraction, 0), 1))
                .tint(tint)
                .animation(Motion.standard, value: fraction)
        }
    }
}

// MARK: - Days left

struct DaysLeftCard: View {
    @EnvironmentObject private var habits: HabitStore
    @State private var newName = ""
    @State private var newDate = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardTitle("Días Restantes", symbol: "calendar.badge.clock", tint: .pink)
            if habits.events.isEmpty {
                Text("Sumá una fecha importante para ver cuántos días faltan.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.35))
            } else {
                ForEach(habits.events) { event in
                    HStack {
                        Text(event.name)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 6)
                        Text(event.date, format: .dateTime.day().month())
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.35))
                        Text(event.daysLeft >= 0 ? "\(event.daysLeft) d" : "pasó")
                            .font(.caption2.weight(event.daysLeft <= 3 ? .bold : .semibold).monospacedDigit())
                            .foregroundStyle(event.daysLeft <= 3 ? .pink : .white.opacity(0.7))
                        Button {
                            withAnimation(Motion.standard) { habits.removeEvent(event) }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                        .buttonStyle(IslandButtonStyle())
                        .accessibilityLabel("Eliminar \(event.name)")
                    }
                    .padding(.vertical, 2)
                    .transition(.opacity)
                }
            }
            HStack(spacing: 6) {
                TextField("Nombre de la fecha", text: $newName)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.07)))
                    .foregroundStyle(.white)
                DatePicker("", selection: $newDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .colorScheme(.dark)
                Button {
                    withAnimation(Motion.standard) {
                        habits.addEvent(name: newName.isEmpty ? "Evento" : newName, date: newDate)
                    }
                    newName = ""
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.pink)
                }
                .buttonStyle(IslandButtonStyle())
                .accessibilityLabel("Agregar fecha")
            }
        }
        .islandCard()
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
                .padding(2)                // görsel 24pt kalır, dokunma hedefi ~28pt
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
                .accessibilityLabel("\(label) artır")
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
                .accessibilityLabel("\(label) azalt")
            }
        }
    }
}
