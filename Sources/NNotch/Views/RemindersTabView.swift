import SwiftUI

/// Dedicated tab for short personal reminders (up to 12 hours ahead) with 2-stage inline notch alerts
/// (15m pre-alert + sticky alert at the exact scheduled time).
struct RemindersTabView: View {
    @EnvironmentObject private var reminders: ReminderStore
    @EnvironmentObject private var vm: NotchViewModel
    @EnvironmentObject private var prefs: Preferences

    @State private var title = ""
    /// Offset from now in minutes (5 min ... 12 hours = 720 min).
    @State private var offsetMinutes: Double = 30

    private let minMinutes: Double = 5
    private let maxMinutes: Double = 12 * 60
    private let quickPresets: [(label: String, minutes: Double)] = [
        ("15m", 15),
        ("30m", 30),
        ("1h", 60),
        ("2h", 120),
        ("4h", 240),
        ("8h", 480),
        ("12h", 720),
    ]

    private var targetDate: Date {
        Date().addingTimeInterval(offsetMinutes * 60)
    }

    private var relativeLabel: String {
        Self.formatRelative(minutes: Int(offsetMinutes.rounded()))
    }

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var pendingCount: Int {
        reminders.reminders.filter { !$0.isCompleted }.count
    }

    private var hasCompleted: Bool {
        reminders.reminders.contains(where: \.isCompleted)
    }

    var body: some View {
        HStack(spacing: 10) {
            composerCard
                .frame(width: 268)

            listCard
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Left Card: Composer

    private var composerCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                CardTitle("Nuevo recordatorio", symbol: "bell.badge.fill", tint: .orange)
                Spacer()
                Menu {
                    Button("Probar aviso 15 min antes") {
                        vm.collapseNow()
                        vm.showNotchAlerts([
                            NotchAlertItem(
                                id: "preview-15m-\(UUID().uuidString)",
                                title: "Reunión de equipo",
                                scheduledDate: Date().addingTimeInterval(15 * 60),
                                stage: .upcoming15m,
                                colorHex: "#FF9F0A",
                                sourceLabel: "Recordatorio",
                                meetingURL: nil,
                                reminderID: nil
                            )
                        ])
                    }
                    Button("Probar aviso fijo a la hora") {
                        vm.collapseNow()
                        vm.showNotchAlerts([
                            NotchAlertItem(
                                id: "preview-due-\(UUID().uuidString)",
                                title: "Llamar ahora",
                                scheduledDate: Date(),
                                stage: .dueNow,
                                colorHex: "#FF9F0A",
                                sourceLabel: "Recordatorio",
                                meetingURL: nil,
                                reminderID: nil
                            )
                        ])
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "play.circle")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Probar")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(Capsule().fill(Color.white.opacity(0.07)))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Probar cómo aparece el aviso en el notch")
            }

            HStack(spacing: 7) {
                Image(systemName: "pencil")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.orange.opacity(0.85))
                TextField("¿Qué te recuerdo?", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white)
                    .onSubmit { submit() }
                if !title.isEmpty {
                    Button { title = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(canSubmit ? Color.orange.opacity(0.45) : Color.white.opacity(0.08), lineWidth: 1)
                    )
            )

            timeSelectorBox

            Spacer(minLength: 0)

            Button {
                submit()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "bell.badge.plus.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                    Text("Programar para las \(targetDate.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                }
                .foregroundStyle(canSubmit ? Color.black : Color.white.opacity(0.4))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7.5)
                .background(
                    Capsule().fill(canSubmit ? Color.orange : Color.white.opacity(0.09))
                )
                .contentShape(Capsule())
            }
            .buttonStyle(IslandButtonStyle())
            .disabled(!canSubmit)
        }
        .islandCard()
    }

    private var timeSelectorBox: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                adjustCircleButton(symbol: "minus", label: "Restar 5 minutos") {
                    offsetMinutes = max(minMinutes, offsetMinutes - 5)
                }

                VStack(spacing: 1) {
                    Text(targetDate.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 8.5, weight: .semibold))
                        Text(relativeLabel)
                            .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                    }
                    .foregroundStyle(.orange)
                }
                .frame(maxWidth: .infinity)

                adjustCircleButton(symbol: "plus", label: "Sumar 5 minutos") {
                    offsetMinutes = min(maxMinutes, offsetMinutes + 5)
                }
            }

            VStack(spacing: 3) {
                Slider(value: $offsetMinutes, in: minMinutes...maxMinutes, step: 5)
                    .tint(.orange)
                    .controlSize(.mini)
                HStack {
                    Text("5m")
                    Spacer()
                    Text("6h")
                    Spacer()
                    Text("12h")
                }
                .font(.system(size: 8, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.32))
            }

            HStack(spacing: 4) {
                ForEach(quickPresets, id: \.label) { preset in
                    let active = Int(offsetMinutes.rounded()) == Int(preset.minutes)
                    Button {
                        withAnimation(Motion.quick) {
                            offsetMinutes = preset.minutes
                        }
                    } label: {
                        Text(preset.label)
                            .font(.system(size: 9, weight: active ? .bold : .medium).monospacedDigit())
                            .foregroundStyle(active ? Color.black : Color.white.opacity(0.68))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(active ? Color.orange : Color.white.opacity(0.07))
                            )
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private func adjustCircleButton(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.white.opacity(0.1)))
                .contentShape(Circle())
        }
        .buttonStyle(IslandButtonStyle())
        .accessibilityLabel(label)
    }

    private func submit() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        reminders.add(title: trimmed, date: targetDate)
        title = ""
        offsetMinutes = 30
    }

    // MARK: - Right Card: List

    private var listCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                CardTitle("Próximos", symbol: "checklist", tint: .white.opacity(0.8))
                if pendingCount > 0 {
                    Text("\(pendingCount)")
                        .font(.system(size: 9, weight: .bold).monospacedDigit())
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Color.orange.opacity(0.16)))
                }
                Spacer()
                if hasCompleted {
                    Button {
                        withAnimation(Motion.quick) {
                            reminders.clearCompleted()
                        }
                    } label: {
                        Text("Limpiar hechos")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(Capsule().fill(Color.white.opacity(0.07)))
                    }
                    .buttonStyle(.plain)
                }
            }

            if reminders.reminders.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.1))
                            .frame(width: 44, height: 44)
                        Image(systemName: "bell.badge")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.orange.opacity(0.75))
                    }
                    Text("Sin recordatorios pendientes")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    Text("Avisa 15 min antes al costado del notch y vuelve fijo a la hora exacta hasta que lo saques.")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.38))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 6) {
                        ForEach(reminders.reminders) { item in
                            ReminderCardRow(
                                item: item,
                                accent: prefs.accentColor,
                                onToggle: { reminders.toggleCompleted(item.id) },
                                onDelete: { reminders.remove(item.id) }
                            )
                        }
                    }
                }
            }
        }
        .islandCard()
    }

    static func formatRelative(minutes: Int) -> String {
        let clamped = max(minutes, 0)
        let h = clamped / 60
        let m = clamped % 60
        if h == 0 { return "en \(m) min" }
        if m == 0 { return "en \(h) h" }
        return "en \(h) h \(m) min"
    }
}

private struct ReminderCardRow: View {
    let item: ReminderItem
    let accent: Color
    let onToggle: () -> Void
    let onDelete: () -> Void
    @State private var hovering = false

    private var remainingMinutes: Int {
        Int(ceil(item.scheduledDate.timeIntervalSinceNow / 60))
    }

    private var isPast: Bool {
        !item.isCompleted && item.scheduledDate < Date()
    }

    private var statusColor: Color {
        if item.isCompleted { return accent }
        return isPast ? .red : .orange
    }

    var body: some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 2)
                .fill(statusColor.opacity(item.isCompleted ? 0.4 : 0.9))
                .frame(width: 3, height: 28)

            Button(action: onToggle) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(item.isCompleted ? accent : .white.opacity(0.45))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2.5) {
                Text(item.title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(item.isCompleted ? .white.opacity(0.35) : .white.opacity(0.92))
                    .strikethrough(item.isCompleted)
                    .lineLimit(2)

                HStack(spacing: 5) {
                    Text(item.scheduledDate.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 9.5, weight: .bold).monospacedDigit())
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 5.5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(statusColor.opacity(0.14)))

                    if !item.isCompleted {
                        Text(isPast ? "Vencido" : RemindersTabView.formatRelative(minutes: remainingMinutes))
                            .font(.system(size: 9, weight: .medium).monospacedDigit())
                            .foregroundStyle(isPast ? .red.opacity(0.85) : .white.opacity(0.48))
                    } else {
                        Text("Completado")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(hovering ? .red.opacity(0.85) : .white.opacity(0.28))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(hovering ? Color.red.opacity(0.12) : Color.clear))
            }
            .buttonStyle(.plain)
            .help("Eliminar recordatorio")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(item.isCompleted ? 0.025 : (hovering ? 0.08 : 0.05)))
        )
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
    }
}
