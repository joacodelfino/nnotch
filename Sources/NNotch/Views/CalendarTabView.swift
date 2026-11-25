import AppKit
import SwiftUI

/// Calendario mensual con selector de origen:
/// Todos, Mac (EventKit), Google Calendar y Otros (.ics / Outlook / Notion).
struct CalendarTabView: View {
    @EnvironmentObject private var calendar: CalendarManager
    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var vm: NotchViewModel
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
                eventsColumn
            }
        }
        .islandCard()
        .onAppear { calendar.refresh() }
        .onChange(of: vm.isExpanded) { _, expanded in
            if expanded { calendar.refresh() }
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

            Button {
                calendar.alertsEnabled.toggle()
            } label: {
                Image(systemName: calendar.alertsEnabled ? "bell.badge.fill" : "bell.slash")
                    .foregroundStyle(calendar.alertsEnabled ? prefs.accentColor : .white.opacity(0.45))
            }
            .buttonStyle(.plain)
            .help(calendar.alertsEnabled ? "Avisos al comenzar: activados" : "Avisos al comenzar: desactivados")
            .accessibilityLabel("Avisos de eventos")

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

    @ViewBuilder
    private var eventsColumn: some View {
        switch calendar.selectedProvider {
        case .mac where calendar.eventAccess == .unknown:
            macPermissionRequestView
        case .mac where calendar.eventAccess == .denied:
            macPermissionDeniedView
        case .google where calendar.eventAccess != .granted && !calendar.hasGoogleSourceConfigured:
            macPermissionRequestView
        case .google where !calendar.hasGoogleSourceConfigured && calendar.filteredEvents.isEmpty:
            googleSignInPrompt
        case .custom where !calendar.hasCustomSourceConfigured && calendar.filteredEvents.isEmpty:
            externalSetupPrompt(
                provider: .custom,
                title: "Conectá cualquier calendario (.ics)",
                subtitle: "Agregá un link iCal (.ics) de Outlook, Teams, Notion Calendar, facultad o trabajo."
            )
        case .all where calendar.eventAccess != .granted && !calendar.hasGoogleAccountOnMac && calendar.externalFeeds.isEmpty:
            macPermissionRequestView
        default:
            CalendarMonthView()
        }
    }

    // MARK: - Inline Accounts & Sources Configurator

    private var configPanel: some View {
        HStack(alignment: .top, spacing: 14) {
            // Cuenta de Google mediante macOS y links .ics opcionales
            VStack(alignment: .leading, spacing: 7) {
                CardTitle("Cuenta de Google", symbol: "globe", tint: .blue)

                Text(calendar.hasGoogleAccountOnMac
                     ? "Google conectado mediante macOS. Elegí los calendarios de la lista."
                     : "Agregá Google en Cuentas de Internet y activá Calendarios. Después permití el acceso a nnotch.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.65))
                Button("Abrir Cuentas de Internet…") {
                    vm.collapseNow()
                    calendar.openMacInternetAccounts()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                if calendar.eventAccess != .granted {
                    calendarAccessButton
                }

                HStack {
                    Toggle("Avisar al comenzar", isOn: $calendar.alertsEnabled)
                        .toggleStyle(.switch).controlSize(.mini)
                    Button("Probar aviso") {
                        let now = Date()
                        vm.showCalendarAlerts([CalendarEventItem(
                            id: "notification-preview", title: "Así se verá tu próximo evento",
                            startDate: now, endDate: now.addingTimeInterval(1800), isAllDay: false,
                            colorHex: "#0A84FF", sourceLabel: "Aviso de prueba", provider: .mac, meetingURL: nil
                        )])
                    }
                    .buttonStyle(.plain).foregroundStyle(.blue)
                }
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.75))
                Text("Con nnotch abierto, avisa al inicio de los eventos con hora de los calendarios habilitados.")
                    .font(.system(size: 9)).foregroundStyle(.white.opacity(0.4))

                Divider().overlay(Color.white.opacity(0.08))

                CardTitle("Calendarios externos por link (.ics)", symbol: "link", tint: prefs.accentColor)

                HStack(spacing: 6) {
                    TextField("Nombre (ej. Outlook, Facultad)", text: $feedName)
                        .textFieldStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.07)))

                    TextField("URL iCal (.ics)…", text: $feedURL)
                        .textFieldStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.07)))
                        .onSubmit { submitFeed() }

                    Button {
                        submitFeed()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(prefs.accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(feedURL.trimmingCharacters(in: .whitespaces).isEmpty)
                }

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
                            calendar.requestCalendarAccessAndRefresh()
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

    private var calendarAccessButton: some View {
        Button(calendar.eventAccess == .denied ? "Habilitar permiso en Ajustes…" : "Permitir Calendario a nnotch") {
            if calendar.eventAccess == .denied {
                vm.collapseNow()
                SystemSettingsPane.calendars.open()
            } else {
                vm.collapseNow()
                NSApp.activate(ignoringOtherApps: true)
                calendar.requestCalendarAccessAndRefresh()
            }
        }
        .foregroundStyle(.white)
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
    }

    private var googleSignInPrompt: some View {
        VStack(spacing: 9) {
            Spacer()
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 26))
                .foregroundStyle(.blue)
            Text("Conectá Google mediante macOS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
            Text("En Cuentas de Internet, agregá Google y activá Calendarios. Luego permití el acceso a nnotch. La sesión web anterior no conecta los eventos.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
            HStack(spacing: 8) {
                Button {
                    vm.collapseNow()
                    calendar.openMacInternetAccounts()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "globe")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Abrir Cuentas de Internet…")
                            .font(.caption.weight(.semibold))
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                if calendar.eventAccess != .granted {
                    calendarAccessButton
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var macPermissionRequestView: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 26))
                .foregroundStyle(.blue)
            Text("Primero, permití el acceso al calendario")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
            Text("nnotch necesita tu permiso para detectar las cuentas de macOS. Si ya agregaste Google y activaste Calendarios, no tenés que conectar la cuenta otra vez.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
            calendarAccessButton
            Text("Solo si todavía no agregaste tu cuenta:")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.45))
            Button("Abrir Cuentas de Internet…") {
                vm.collapseNow()
                calendar.openMacInternetAccounts()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
            .font(.caption)
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

}
