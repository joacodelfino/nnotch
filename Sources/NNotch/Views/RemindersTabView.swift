import SwiftUI

/// Dedicated tab for short personal reminders (up to 12 hours ahead) with 2-stage notch alerts
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
        let total = Int(offsetMinutes.rounded())
        let h = total / 60
        let m = total % 60
        if h == 0 { return "en \(m) min" }
        if m == 0 { return "en \(h) h" }
        return "en \(h) h \(m) min"
    }

    private var pendingCount: Int {
        reminders.reminders.filter { !$0.isCompleted }.count
    }

    private var hasCompleted: Bool {
        reminders.reminders.contains(where: \.isCompleted)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            composerColumn
                .frame(width: 256)

            Divider().overlay(Color.white.opacity(0.08))

            listColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .islandCard()
    }

    // MARK: - Left: Composer

    private var composerColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardTitle("Nuevo recordatorio", symbol: "bell.badge.fill", tint: .orange)

            TextField("¿Qué te recuerdo?", text: $title)
                .textFieldStyle(.plain)
                .font(.caption)
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                        )
                )
                .onSubmit { submit() }

            timeSelectorCard

            Button {
                submit()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Programar aviso")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(title.trimmingCharacters(in: .whitespaces).isEmpty ? Color.white.opacity(0.45) : Color.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6.5)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(title.trimmingCharacters(in: .whitespaces).isEmpty ? Color.white.opacity(0.1) : Color.orange)
                )
            }
            .buttonStyle(.plain)
            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Text("Probar:")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.35))
                Button("15 min antes") {
                    vm.collapseNow()
                    vm.showNotchAlerts([
                        NotchAlertItem(
                            id: "preview-15m-\(UUID().uuidString)",
                            title: "Ejemplo: Reunión de equipo",
                            scheduledDate: Date().addingTimeInterval(15 * 60),
                            stage: .upcoming15m,
                            colorHex: "#FF9F0A",
                            sourceLabel: "Recordatorio",
                            meetingURL: nil,
                            reminderID: nil
                        )
                    ])
                }
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.orange)
                .buttonStyle(.plain)

                Text("·").foregroundStyle(.white.opacity(0.25))

                Button("A la hora (fijo)") {
                    vm.collapseNow()
                    vm.showNotchAlerts([
                        NotchAlertItem(
                            id: "preview-due-\(UUID().uuidString)",
                            title: "Ejemplo: Llamar ahora",
                            scheduledDate: Date(),
                            stage: .dueNow,
                            colorHex: "#FF9F0A",
                            sourceLabel: "Recordatorio",
                            meetingURL: nil,
                            reminderID: nil
                        )
                    ])
                }
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(prefs.accentColor)
                .buttonStyle(.plain)
            }
        }
    }

    private var timeSelectorCard: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                adjustButton(symbol: "minus", label: "Restar 5 minutos") {
                    offsetMinutes = max(minMinutes, offsetMinutes - 5)
                }

                VStack(spacing: 1) {
                    Text(targetDate.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 24, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                    Text(relativeLabel)
                        .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(.orange)
                }
                .frame(maxWidth: .infinity)

                adjustButton(symbol: "plus", label: "Sumar 5 minutos") {
                    offsetMinutes = min(maxMinutes, offsetMinutes + 5)
                }
            }

            Slider(value: $offsetMinutes, in: minMinutes...maxMinutes, step: 5)
                .tint(.orange)
                .controlSize(.mini)

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
                            .foregroundStyle(active ? Color.black : Color.white.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 3.5)
                            .background(
                                Capsule().fill(active ? Color.orange : Color.white.opacity(0.07))
                            )
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private func adjustButton(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 24, height: 24)
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

    // MARK: - Right: List

    private var listColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                CardTitle("Recordatorios · \(pendingCount)", symbol: "checklist", tint: .white.opacity(0.75))
                Spacer()
                if hasCompleted {
                    Button("Limpiar hechos") {
                        reminders.clearCompleted()
                    }
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
                    .buttonStyle(.plain)
                }
            }

            if reminders.reminders.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "bell.badge")
                        .font(.system(size: 26))
                        .foregroundStyle(.white.opacity(0.22))
                    Text("Sin recordatorios pendientes")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.5))
                    Text("Elegí un lapso de hasta 12 h para recibir aviso 15 min antes y fijo a la hora exacta")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.32))
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 6) {
                        ForEach(reminders.reminders) { item in
                            reminderRow(item)
                        }
                    }
                }
            }
        }
    }

    private func reminderRow(_ item: ReminderItem) -> some View {
        let isPast = !item.isCompleted && item.scheduledDate < Date()
        return HStack(spacing: 8) {
            Button {
                reminders.toggleCompleted(item.id)
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(item.isCompleted ? prefs.accentColor : .orange)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(item.isCompleted ? .white.opacity(0.38) : .white.opacity(0.92))
                    .strikethrough(item.isCompleted)
                    .lineLimit(2)

                HStack(spacing: 5) {
                    Text(item.scheduledDate.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(isPast ? .red.opacity(0.85) : .orange.opacity(0.9))
                    if isPast {
                        Text("· Vencido")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(.red)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                reminders.remove(item.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(4)
            }
            .buttonStyle(.plain)
            .help("Eliminar recordatorio")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(item.isCompleted ? 0.025 : 0.055))
        )
    }
}
