import SwiftUI
import ServiceManagement

// MARK: - Settings window

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, appearance, modules, data, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Apariencia"
        case .modules: return "Módulos"
        case .data: return "Datos"
        case .about: return "Acerca de"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .appearance: return "paintbrush.fill"
        case .modules: return "square.grid.2x2.fill"
        case .data: return "externaldrive.fill"
        case .about: return "info.circle.fill"
        }
    }
}

/// Modern, sidebar'lı ayarlar penceresi.
struct SettingsView: View {
    @EnvironmentObject private var prefs: Preferences
    @State private var section: SettingsSection = .general

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(section.title)
                        .font(.title2.weight(.bold))
                        .padding(.top, 8)
                    sectionContent
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 640, height: 480)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                MiniIslandGlyph(tint: prefs.accentColor)
                    .frame(width: 34, height: 24)
                VStack(alignment: .leading, spacing: 0) {
                    Text("JNotch")
                        .font(.headline)
                    Text("v\(AppInfo.version) · Personalizado")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 28)
            .padding(.bottom, 14)

            ForEach(SettingsSection.allCases) { item in
                Button {
                    section = item
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 12))
                            .frame(width: 18)
                            .foregroundStyle(section == item ? prefs.accentColor : .secondary)
                        Text(item.title)
                            .font(.callout.weight(section == item ? .semibold : .regular))
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(section == item ? Color.primary.opacity(0.08) : .clear)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(width: 185)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch section {
        case .general: GeneralSettings()
        case .appearance: AppearanceSettings()
        case .modules: ModuleSettings()
        case .data: DataSettings()
        case .about: AboutSettings()
        }
    }
}

// MARK: - Section: Genel

private struct GeneralSettings: View {
    @EnvironmentObject private var prefs: Preferences
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        SettingsCard("Inicio") {
            Toggle("Iniciar al abrir sesión", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { enabled in
                    do {
                        if enabled {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                        loginError = nil
                    } catch {
                        loginError = error.localizedDescription
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
            if let loginError {
                Text(loginError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }

        SettingsCard("Apertura") {
            Picker("¿Cómo abrir JNotch?", selection: $prefs.hoverToExpand) {
                Text("Al pasar el cursor (hover)").tag(true)
                Text("Al hacer click").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if prefs.hoverToExpand {
                LabeledSlider(
                    label: "Demora al abrir",
                    value: $prefs.hoverDelay,
                    range: 0...0.6,
                    format: "%.1f s"
                )
            }
            LabeledSlider(
                label: "Demora al cerrar",
                value: $prefs.collapseDelay,
                range: 0.1...1.5,
                format: "%.1f s"
            )
            Text("Queda abierto este tiempo tras sacar el cursor. Con ESC se cierra al instante.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        SettingsCard("Animación") {
            Picker("Velocidad de animación", selection: $prefs.animationSpeed) {
                ForEach(Preferences.AnimationSpeed.allCases) { speed in
                    Text(speed.title).tag(speed)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text("Controla el ritmo de rebote al expandir y contraer.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        SettingsCard("Respuesta") {
            Toggle("Respuesta háptica (vibración suave del trackpad)", isOn: $prefs.hapticsEnabled)
        }
    }
}

// MARK: - Section: Apariencia

private struct AppearanceSettings: View {
    @EnvironmentObject private var prefs: Preferences

    var body: some View {
        SettingsCard("Vista Previa") {
            HStack {
                Spacer()
                CollapsedPreview()
                Spacer()
            }
        }

        SettingsCard("Color de Acento") {
            AccentSwatchRow()
            Text("Se aplica en pestañas activas, ecualizador, barras de progreso y zonas de arrastre.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        SettingsCard("Tamaño del Panel") {
            Picker("Tamaño", selection: $prefs.islandSizeMode) {
                ForEach(Preferences.IslandSizeMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if prefs.islandSizeMode == .custom {
                LabeledSlider(
                    label: "Ancho",
                    value: $prefs.customPanelWidth,
                    range: Preferences.panelWidthRange,
                    format: "%.0f pt",
                    valueWidth: 52
                )
                LabeledSlider(
                    label: "Alto",
                    value: $prefs.customPanelHeight,
                    range: Preferences.panelHeightRange,
                    format: "%.0f pt",
                    valueWidth: 52
                )
                Text("El cambio se refleja en tiempo real.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LabeledSlider(
                label: "Redondeo de esquinas",
                value: $prefs.expandedCornerRadius,
                range: Preferences.cornerRadiusRange,
                format: "%.0f",
                valueWidth: 52
            )
        }

        SettingsCard("Modo Contraído") {
            HStack {
                Text("Izquierda").frame(width: 70, alignment: .leading)
                Picker("Izquierda", selection: $prefs.collapsedLeft) {
                    ForEach(Preferences.CollapsedLeftContent.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            HStack {
                Text("Derecha").frame(width: 70, alignment: .leading)
                Picker("Derecha", selection: $prefs.collapsedRight) {
                    ForEach(Preferences.CollapsedRightContent.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            Text("Auto muestra la música cuando está sonando, y si no, la batería.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Animar ecualizador mientras suena música", isOn: $prefs.showEqualizer)
        }

        SettingsCard("Pantalla") {
            Toggle("Mostrar en monitores sin notch físico", isOn: $prefs.showOnNotchlessScreens)
            Text("Si lo desactivás, solo aparece en pantallas con notch integrado.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Section: Módulos

private struct ModuleSettings: View {
    @EnvironmentObject private var prefs: Preferences

    var body: some View {
        SettingsCard("Pestañas Visibles") {
            Text("Podés apagar los módulos que no uses para dejar tu notch bien limpio.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(IslandTab.allCases) { tab in
                HStack {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 12))
                        .frame(width: 20)
                        .foregroundStyle(prefs.isTabEnabled(tab) ? prefs.accentColor : .secondary)
                    Text(tab.title)
                    Spacer()
                    if Preferences.lockedTabs.contains(tab.rawValue) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .help("Esta pestaña siempre está activa")
                    } else {
                        Toggle("", isOn: Binding(
                            get: { prefs.isTabEnabled(tab) },
                            set: { prefs.setTab(tab, enabled: $0) }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

// MARK: - Section: Datos

private struct DataSettings: View {
    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var shelf: ShelfManager
    @EnvironmentObject private var clipboard: ClipboardManager
    @State private var confirmClearClipboard = false
    @State private var confirmClearShelf = false

    var body: some View {
        SettingsCard("Historial del Portapapeles") {
            HStack {
                Text("Cantidad máxima guardada").frame(maxWidth: .infinity, alignment: .leading)
                Picker("Cantidad máxima guardada", selection: $prefs.clipboardLimit) {
                    ForEach(Preferences.clipboardLimitOptions, id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 160)
            }
            Text("Se guardan localmente los últimos \(prefs.clipboardLimit) elementos. Las contraseñas de gestores seguros se ignoran automáticamente.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Limpiar portapapeles (\(clipboard.items.count))") {
                confirmClearClipboard = true
            }
            .disabled(clipboard.items.isEmpty)
            .confirmationDialog(
                "¿Eliminar los \(clipboard.items.count) elementos del portapapeles?",
                isPresented: $confirmClearClipboard
            ) {
                Button("Limpiar", role: .destructive) { clipboard.clearAll() }
            } message: {
                Text("Esta acción no se puede deshacer.")
            }
        }

        SettingsCard("Bandeja de Archivos") {
            Toggle("Vaciar bandeja al cerrar JNotch", isOn: $prefs.clearShelfOnQuit)
            Button("Vaciar bandeja ahora (\(shelf.items.count))") {
                confirmClearShelf = true
            }
            .disabled(shelf.items.isEmpty)
            .confirmationDialog(
                "¿Vaciar los \(shelf.items.count) archivos de la bandeja?",
                isPresented: $confirmClearShelf
            ) {
                Button("Vaciar", role: .destructive) { shelf.removeAll() }
            } message: {
                Text("Se eliminan las copias guardadas en la bandeja.")
            }
        }
    }
}

// MARK: - Section: Acerca de

private struct AboutSettings: View {
    @EnvironmentObject private var prefs: Preferences

    var body: some View {
        SettingsCard("JNotch") {
            HStack(spacing: 12) {
                MiniIslandGlyph(tint: prefs.accentColor)
                    .frame(width: 48, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Versión \(AppInfo.version)")
                        .font(.callout.weight(.semibold))
                    Text("Tu centro de control personalizado en el notch")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text("Basado en Swift + SwiftUI nativo (derivado MIT de sayweer/dynamicIsland), adaptado como base modular propia para sumar tus integraciones.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        SettingsCard("Enlaces") {
            Link("Repositorio JNotch", destination: URL(string: "https://github.com/joacodelfino/j-notch")!)
        }
    }
}

// MARK: - Shared building blocks

private struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .kerning(0.5)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }
}

private struct LabeledSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String
    var valueWidth: CGFloat = 44

    var body: some View {
        HStack {
            Text(label)
            Slider(value: $value, in: range)
            Text(String(format: format, value))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: valueWidth, alignment: .trailing)
        }
    }
}

/// Palet swatch'ları + serbest ColorPicker — tam ayarlar ve hızlı ayarlarda ortak.
struct AccentSwatchRow: View {
    @EnvironmentObject private var prefs: Preferences
    var swatchSize: CGFloat = 24
    var showsRing: Bool = true

    var body: some View {
        HStack(spacing: swatchSize > 18 ? 10 : 8) {
            ForEach(Preferences.accentPalette) { option in
                Button {
                    prefs.accentHex = option.hex
                } label: {
                    Circle()
                        .fill(option.color)
                        .frame(width: swatchSize, height: swatchSize)
                        .overlay {
                            if prefs.accentHex == option.hex {
                                Image(systemName: "checkmark")
                                    .font(.system(size: swatchSize * 0.38, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .overlay(
                            Circle().strokeBorder(
                                showsRing && prefs.accentHex == option.hex
                                    ? Color.primary.opacity(0.8) : .clear,
                                lineWidth: 2
                            )
                            .padding(-3)
                        )
                }
                .buttonStyle(.plain)
                .help(option.name)
            }
            // Serbest renk seçimi — koyu paneldeki accent tüketicilerine yansır.
            ColorPicker("", selection: Binding(
                get: { prefs.accentColor },
                set: { prefs.accentHex = $0.hexString }
            ), supportsOpacity: false)
            .labelsHidden()
            .frame(width: swatchSize, height: swatchSize)
            .help("Color personalizado")
            Spacer()
        }
    }
}

/// Ayarlardaki canlı kapalı-mod önizlemesi.
private struct CollapsedPreview: View {
    @EnvironmentObject private var prefs: Preferences

    var body: some View {
        HStack(spacing: 0) {
            Group {
                switch prefs.collapsedLeft {
                case .clock:
                    Text(Date(), format: .dateTime.hour().minute())
                case .date:
                    Text(Date(), format: .dateTime.day().month(.abbreviated))
                case .hidden:
                    Color.clear
                }
            }
            .font(.caption.monospacedDigit().weight(.medium))
            .foregroundStyle(.white.opacity(0.85))
            .frame(width: 64)

            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .frame(width: 110, height: 18)
                .overlay(
                    Text("notch")
                        .font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.2))
                )
                .padding(.vertical, 3)

            Group {
                switch prefs.collapsedRight {
                case .auto:
                    HStack(spacing: 4) {
                        Image(systemName: "music.note")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.85))
                        if prefs.showEqualizer {
                            EqualizerBars(playing: true, tint: prefs.accentColor)
                        }
                    }
                case .battery:
                    // Gerçek kapalı moddaki batteryMini ile aynı görsel dil.
                    HStack(spacing: 3) {
                        Text("%84")
                            .font(.caption.monospacedDigit().weight(.medium))
                        Image(systemName: "battery.75")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(.white.opacity(0.85))
                case .network:
                    Text("↓ 1.2 MB/s")
                        .font(.system(size: 8).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.75))
                case .hidden:
                    Color.clear
                }
            }
            .frame(width: 64)
        }
        .frame(height: 30)
        .background(
            NotchShape(bottomRadius: 12).fill(Color.black)
        )
        .overlay(
            NotchShape(bottomRadius: 12)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

/// Küçük ada glifi (sidebar ve hakkında bölümü için).
struct MiniIslandGlyph: View {
    var tint: Color = Color(hex: "#30D158")

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: geo.size.height * 0.28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "#34345A"), Color(hex: "#0C0C14")],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                Capsule()
                    .fill(Color.black)
                    .frame(width: geo.size.width * 0.62, height: geo.size.height * 0.34)
                    .overlay(
                        HStack(spacing: geo.size.width * 0.04) {
                            Capsule().frame(width: 1.5, height: geo.size.height * 0.14)
                            Capsule().frame(width: 1.5, height: geo.size.height * 0.2)
                            Capsule().frame(width: 1.5, height: geo.size.height * 0.11)
                        }
                        .foregroundStyle(tint)
                    )
                    .overlay(
                        Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
                    )
            }
        }
    }
}

// MARK: - Quick settings inside the island

struct SettingsQuickView: View {
    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var clipboard: ClipboardManager
    @EnvironmentObject private var shelf: ShelfManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle("Ajustes Rápidos", symbol: "gearshape.fill")
            HStack(spacing: 16) {
                Toggle("Abrir al pasar", isOn: $prefs.hoverToExpand)
                Toggle("Ecualizador", isOn: $prefs.showEqualizer)
                Toggle("Háptico", isOn: $prefs.hapticsEnabled)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .font(.caption)
            .foregroundStyle(.white.opacity(0.85))

            HStack(spacing: 8) {
                Text("Acento:")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
                AccentSwatchRow(swatchSize: 15, showsRing: false)
            }

            Divider().overlay(Color.white.opacity(0.1))
            HStack(spacing: 10) {
                ConfirmingButton(title: "Limpiar portapapeles", systemImage: "trash", tint: .white.opacity(0.6)) {
                    clipboard.clearAll()
                }
                ConfirmingButton(title: "Vaciar bandeja", systemImage: "tray", tint: .white.opacity(0.6)) {
                    shelf.removeAll()
                }
            }
            Spacer()
            HStack {
                Text("JNotch v\(AppInfo.version)")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.3))
                Spacer()
                Button {
                    NSApp.sendAction(#selector(AppDelegate.openSettings), to: nil, from: nil)
                } label: {
                    Label("Todos los ajustes…", systemImage: "arrow.up.forward.square")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(prefs.accentColor)
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Label("Salir", systemImage: "power")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red.opacity(0.8))
            }
        }
        .islandCard()
    }
}
