import SwiftUI

/// Dedicated tab for personal reminders with 2-stage notch alerts (15m before + sticky at exact time).
struct RemindersTabView: View {
    @EnvironmentObject private var reminders: ReminderStore
    @EnvironmentObject private var vm: NotchViewModel
    @EnvironmentObject private var prefs: Preferences

    @State private var title = ""
    @State private var scheduledDate = RemindersTabView.defaultDate()

    private static func defaultDate() -> Date {
        let cal = Calendar.current
        let next = cal.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: next)
        return cal.date(from: comps) ?? next
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
                .frame(width: 245)

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

            TextField("Ej: Mandar informe, llamar…", text: $title)
                .textFieldStyle(.plain)
                .font(.caption)
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                .onSubmit { submit() }

            DatePicker(
                "Hora",
                selection: $scheduledDate,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.compact)
            .labelsHidden()
            .controlSize(.small)
            .environment(\.locale, Locale(identifier: "es_UY"))

            HStack(spacing: 4) {
                quickTimeChip("+20m") { scheduledDate = Date().addingTimeInterval(20 * 60) }
                quickTimeChip("+1h") { scheduledDate = Date().addingTimeInterval(60 * 60) }
                quickTimeChip("+3h") { scheduledDate = Date().addingTimeInterval(3 * 60 * 60) }
                Spacer(minLength: 0)
            }

            Button {
                submit()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Agregar recordatorio")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(title.trimmingCharacters(in: .whitespaces).isEmpty ? Color.white.opacity(0.15) : Color.orange))
            }
            .buttonStyle(.plain)
            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)

            Text("Avisa 15 min antes al costado derecho del notch y vuelve fijo a la hora exacta hasta que lo saques.")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Button("Probar 15m") {
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

                Button("Probar fijo") {
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

    private func quickTimeChip(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.75))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    private func submit() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        reminders.add(title: trimmed, date: scheduledDate)
        title = ""
        scheduledDate = Self.defaultDate()
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
                    Text("Creá uno con fecha y hora para recibir el aviso al lado derecho del notch")
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
                    Text(item.scheduledDate.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(Locale(identifier: "es_UY"))))
                        .font(.system(size: 9.5).monospacedDigit())
                        .foregroundStyle(isPast ? .red.opacity(0.85) : .white.opacity(0.5))
                    if isPast {
                        Text("Vencido")
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
