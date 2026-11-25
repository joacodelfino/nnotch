import AppKit
import EventKit
import SwiftUI

/// Pestaña de Calendario y Recordatorios con selector de origen:
/// Todos, Mac (EventKit), Google Calendar y Otros (.ics / Outlook / Notion).
struct CalendarTabView: View {
    @EnvironmentObject private var calendar: CalendarManager
    @EnvironmentObject private var prefs: Preferences
    @State private var showingConfig = false
    @State private var feedName = ""
    @State private var feedURL = ""

    var body: some View {
        VStack(spacing: 8) {
            topBar
            Divider().overlay(Color.white.opacity(0.08))

            if showingConfig {
                configPanel
            } else {
                mainColumns
            }
        }
        .islandCard()
        .onAppear {
            if calendar.eventAccess == .granted || calendar.reminderAccess == .granted || !calendar.externalFeeds.isEmpty {
                calendar.refresh()
            }
        }
    }

    // MARK: - Top Provider Bar

    private var topBar: some View {
        HStack(spacing: 6) {
            // Selector de proveedor (Todos / Mac / Google / Otro)
            HStack(spacing: 3) {
                ForEach(CalendarProvider.allCases) { provider in
                    let active = calendar.selectedProvider == provider
                    Button {
                        withAnimation(Motion.quick) {
                            calendar.selectedProvider = provider
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: provider.symbol)
                                .font(.system(size: 9, weight: .semibold))
                            Text(provider.title)
                                .font(.system(size: 10, weight: active ? .semibold : .medium))
                                .lineLimit(1)
                        }
                        .foregroundStyle(active ? Color.black : Color.white.opacity(0.75))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(
                            Capsule().fill(active ? prefs.accentColor : Color.clear)
                        )
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2.5)
            .background(Capsule().fill(Color.white.opacity(0.07)))

            Spacer()

            if calendar.isSyncingExternal {
                ProgressView()
                    .controlSize(.mini)
            }

            Button {
                withAnimation(Motion.quick) {
                    showingConfig.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: showingConfig ? "checkmark" : "slider.horizontal.3")
                        .font(.system(size: 10, weight: .semibold))
                    Text(showingConfig ? "Listo" : "Cuentas")
                        .font(.system(size: 9.5, weight: .semibold))
                }
                .foregroundStyle(showingConfig ? Color.black : .white.opacity(0.8))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(showingConfig ? prefs.accentColor : Color.white.opacity(0.08))
                )
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Elegir calendarios o conectar Google Calendar / .ics")

            Button {
                calendar.openExternalCalendarApp()
            } label: {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.65))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.white.opacity(0.07)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Abrir aplicación o web de calendario")

            Button {
                calendar.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.65))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.white.opacity(0.07)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Actualizar")
        }
    }

    // MARK: - Main Events + Reminders Columns

    private var mainColumns: some View {
        HStack(alignment: .top, spacing: 14) {
            eventsColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider().overlay(Color.white.opacity(0.08))

            remindersColumn
                .frame(width: 215)
                .frame(maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var eventsColumn: some View {
        switch calendar.selectedProvider {
        case .mac where calendar.eventAccess == .unknown:
            macPermissionRequestView
        case .mac where calendar.eventAccess == .denied:
            macPermissionDeniedView
        case .google where !calendar.hasGoogleSourceConfigured && calendar.filteredEvents.isEmpty:
            externalSetupPrompt(
                provider: .google,
                title: "Conectá tu Google Calendar",
                subtitle: "Podés pegar tu link iCal (.ics) privado de Google Calendar o sincronizar tu cuenta Google en macOS."
            )
        case .custom where !calendar.hasCustomSourceConfigured && calendar.filteredEvents.isEmpty:
            externalSetupPrompt(
                provider: .custom,
                title: "Conectá cualquier calendario (.ics)",
                subtitle: "Agregá un link iCal (.ics) de Outlook, Teams, Notion Calendar, facultad o trabajo."
            )
        case .all where calendar.eventAccess != .granted && calendar.externalFeeds.isEmpty:
            macPermissionRequestView
        default:
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    CardTitle("Próximos Eventos · \(calendar.selectedProvider.title)", symbol: "calendar", tint: .red)
                    Spacer()
                    if let err = calendar.externalError {
                        Text(err)
                            .font(.system(size: 8.5))
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    }
                }

                if calendar.filteredEvents.isEmpty {
                    VStack(spacing: 6) {
                        Spacer()
                        Image(systemName: "calendar.badge.checkmark")
                            .font(.system(size: 24))
                            .foregroundStyle(.white.opacity(0.2))
                        Text("No hay eventos próximos en \(calendar.selectedProvider.title)")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.4))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(calendar.filteredEvents) { event in
                                eventRow(event)
                            }
                        }
                    }
                }
            }
        }
    }

    private var remindersColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            CardTitle("Recordatorios", symbol: "checklist", tint: .orange)
            if calendar.reminderAccess == .unknown {
                VStack(spacing: 8) {
                    Spacer()
                    Text("Sincronizá tus recordatorios de Mac")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.45))
                        .multilineTextAlignment(.center)
                    Button("Dar permiso") {
                        calendar.requestAccessAndRefresh()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if calendar.reminderAccess == .denied {
                VStack(spacing: 6) {
                    Spacer()
                    Text("Acceso a Recordatorios desactivado")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.4))
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if calendar.openReminders.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    Text("Sin pendientes 🎉")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.35))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(calendar.openReminders, id: \.calendarItemIdentifier) { reminder in
                            reminderRow(reminder)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Inline Accounts & Sources Configurator

    private var configPanel: some View {
        HStack(alignment: .top, spacing: 14) {
            // Columna izquierda: agregar link .ics (Google Calendar / Outlook / otro)
            VStack(alignment: .leading, spacing: 7) {
                CardTitle("Conectar Google Calendar u otro (.ics)", symbol: "plus.circle.fill", tint: prefs.accentColor)

                HStack(spacing: 6) {
                    TextField("Nombre (ej. Google Personal, Trabajo)", text: $feedName)
                        .textFieldStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.07)))
                }

                HStack(spacing: 6) {
                    TextField("Pegá la URL iCal (.ics) del calendario…", text: $feedURL)
                        .textFieldStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.07)))
                        .onSubmit { submitFeed() }

                    Button {
                        submitFeed()
                    } label: {
                        Text("Sumar")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(prefs.accentColor))
                    }
                    .buttonStyle(.plain)
                    .disabled(feedURL.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                Text("En Google Calendar: Configuración ▸ tu calendario ▸ \"Dirección secreta en formato iCal (.ics)\".")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.4))
                    .fixedSize(horizontal: false, vertical: true)

                if !calendar.externalFeeds.isEmpty {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 4) {
                            ForEach(calendar.externalFeeds) { feed in
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Color(hex: feed.colorHex))
                                        .frame(width: 7, height: 7)
                                    Text(feed.name)
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.85))
                                        .lineLimit(1)
                                    Text(feed.provider.title)
                                        .font(.system(size: 8.5, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.45))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1.5)
                                        .background(Capsule().fill(Color.white.opacity(0.07)))
                                    Spacer()
                                    Button {
                                        calendar.removeExternalFeed(feed)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.white.opacity(0.35))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.05)))
                            }
                        }
                    }
                } else {
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            Divider().overlay(Color.white.opacity(0.08))

            // Columna derecha: Calendarios del sistema (Mac / iCloud / cuentas Google en macOS)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    CardTitle("Calendarios en tu Mac", symbol: "apple.logo", tint: .white.opacity(0.75))
                    Spacer()
                    if calendar.eventAccess != .granted {
                        Button("Conectar Mac") {
                            calendar.requestAccessAndRefresh()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)
                    }
                }

                if calendar.macCalendars.isEmpty {
                    Text(
                        calendar.eventAccess == .granted
                            ? "No se encontraron calendarios locales."
                            : "Permite el acceso para elegir qué calendarios de tu Mac (iCloud, Google, Exchange) mostrar."
                    )
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
                    Spacer()
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 4) {
                            ForEach(calendar.macCalendars) { cal in
                                let enabled = calendar.isMacCalendarEnabled(cal.id)
                                Button {
                                    calendar.toggleMacCalendar(cal.id)
                                } label: {
                                    HStack(spacing: 7) {
                                        Circle()
                                            .fill(Color(hex: cal.colorHex))
                                            .frame(width: 7, height: 7)
                                        Text(cal.title)
                                            .font(.caption)
                                            .foregroundStyle(enabled ? .white.opacity(0.9) : .white.opacity(0.4))
                                            .lineLimit(1)
                                        if cal.isGoogleAccount {
                                            Text("Google")
                                                .font(.system(size: 8, weight: .semibold))
                                                .foregroundStyle(.blue)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(Capsule().fill(Color.blue.opacity(0.15)))
                                        }
                                        Spacer()
                                        Image(systemName: enabled ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 11))
                                            .foregroundStyle(enabled ? prefs.accentColor : .white.opacity(0.25))
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(enabled ? 0.06 : 0.025)))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .frame(width: 245, alignment: .topLeading)
        }
    }

    private func submitFeed() {
        let urlLower = feedURL.lowercased()
        let detectedProvider: CalendarProvider =
            (calendar.selectedProvider == .google || urlLower.contains("google.com"))
            ? .google : .custom
        calendar.addExternalFeed(name: feedName, urlString: feedURL, provider: detectedProvider)
        feedName = ""
        feedURL = ""
    }

    // MARK: - Prompts & Rows

    private var macPermissionRequestView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 26))
                .foregroundStyle(.white.opacity(0.3))
            Text("Mirá tu Calendario de Mac o conectá Google Calendar")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.75))
            HStack(spacing: 8) {
                Button("Permitir Calendario de Mac") {
                    calendar.requestAccessAndRefresh()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Conectar Google / .ics") {
                    withAnimation(Motion.quick) { showingConfig = true }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var macPermissionDeniedView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 22))
                .foregroundStyle(.white.opacity(0.3))
            Text("Acceso al Calendario de Mac desactivado")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.65))
            HStack(spacing: 8) {
                Button("Abrir Configuración") {
                    SystemSettingsPane.calendars.open()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Usar Google / .ics") {
                    withAnimation(Motion.quick) { showingConfig = true }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func externalSetupPrompt(provider: CalendarProvider, title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: provider.symbol)
                .font(.system(size: 24))
                .foregroundStyle(prefs.accentColor.opacity(0.8))
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
            HStack(spacing: 8) {
                Button("Pegar link .ics") {
                    withAnimation(Motion.quick) { showingConfig = true }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                if provider == .google {
                    Button("Abrir Google Calendar") {
                        calendar.openExternalCalendarApp()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func eventRow(_ event: CalendarEventItem) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: event.colorHex))
                .frame(width: 3.5, height: 28)

            VStack(alignment: .leading, spacing: 1.5) {
                Text(event.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)

                HStack(spacing: 5) {
                    if event.isAllDay {
                        Text("Todo el día")
                    } else {
                        let day = event.startDate.formatted(.dateTime.day().month(.abbreviated))
                        let start = event.startDate.formatted(.dateTime.hour().minute())
                        let end = event.endDate.formatted(.dateTime.hour().minute())
                        Text("\(day) · \(start)–\(end)")
                            .monospacedDigit()
                    }
                    Text("·")
                    Text(event.sourceLabel)
                        .lineLimit(1)
                }
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.42))
            }

            Spacer(minLength: 4)

            if let meetingURL = event.meetingURL {
                Button {
                    NSWorkspace.shared.open(meetingURL)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "video.fill")
                            .font(.system(size: 8))
                        Text("Unirse")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(prefs.accentColor))
                }
                .buttonStyle(.plain)
                .help("Unirse a la videollamada")
            }
        }
        .padding(.vertical, 1)
    }

    private func reminderRow(_ reminder: EKReminder) -> some View {
        HStack(spacing: 7) {
            Button {
                calendar.complete(reminder)
            } label: {
                Image(systemName: "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
            .help("Marcar como completado")

            VStack(alignment: .leading, spacing: 1) {
                Text(reminder.title ?? "Recordatorio")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                if let due = reminder.dueDateComponents?.date {
                    Text(due, format: .dateTime.day().month().hour().minute())
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            Spacer(minLength: 0)
        }
    }
}
