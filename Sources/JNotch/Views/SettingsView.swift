import AppKit
import SwiftUI
import ServiceManagement

// MARK: - Standalone Settings Window

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

/// Ventana completa de Ajustes con estética oscura coherente con JNotch.
struct SettingsView: View {
    @EnvironmentObject private var prefs: Preferences
    @State private var section: SettingsSection = .general

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().overlay(Color.white.opacity(0.08))
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: section.symbol)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(prefs.accentColor)
                        Text(section.title)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                    }
                    .padding(.bottom, 2)

                    sectionContent
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(hex: "#121216"))
        }
        .frame(width: 680, height: 500)
        .preferredColorScheme(.dark)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                MiniIslandGlyph(tint: prefs.accentColor)
                    .frame(width: 36, height: 25)
                VStack(alignment: .leading, spacing: 1) {
                    Text("JNotch")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("v\(AppInfo.version)")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 38)
            .padding(.bottom, 16)

            ForEach(SettingsSection.allCases) { item in
                Button {
                    withAnimation(Motion.quick) {
                        section = item
                    }
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 18)
                            .foregroundStyle(section == item ? prefs.accentColor : .white.opacity(0.5))
                        Text(item.title)
                            .font(.callout.weight(section == item ? .semibold : .regular))
                            .foregroundStyle(section == item ? .white : .white.opacity(0.75))
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(section == item ? Color.white.opacity(0.1) : .clear)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 14)
        .frame(width: 195)
        .background(Color(hex: "#191920"))
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

// MARK: - Section: General

private struct GeneralSettings: View {
    @EnvironmentObject private var prefs: Preferences
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        SettingsCard("Inicio del Sistema") {
            SettingsToggleRow(
                title: "Iniciar JNotch al abrir sesión",
                subtitle: "Arranca automáticamente en segundo plano al prender la Mac.",
                isOn: $launchAtLogin
            )
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
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }

        SettingsCard("Apertura y Cierre") {
            SettingsControlRow("Modo de apertura") {
                Picker("", selection: $prefs.hoverToExpand) {
                    Text("Pasar cursor").tag(true)
                    Text("Click").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 200)
            }

            if prefs.hoverToExpand {
                Divider().overlay(Color.white.opacity(0.06))
                LabeledSlider(
                    label: "Demora al abrir",
                    value: $prefs.hoverDelay,
                    range: 0...0.6,
                    format: "%.1f s"
                )
            }

            Divider().overlay(Color.white.opacity(0.06))
            LabeledSlider(
                label: "Demora al cerrar",
                value: $prefs.collapseDelay,
                range: 0.1...1.5,
                format: "%.1f s"
            )
            Text("Tiempo que permanece abierto al sacar el cursor. Con ESC se cierra al instante.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.45))
        }

        SettingsCard("Animación y Respuesta") {
            SettingsControlRow("Velocidad de animación") {
                Picker("", selection: $prefs.animationSpeed) {
                    ForEach(Preferences.AnimationSpeed.allCases) { speed in
                        Text(speed.title).tag(speed)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 210)
            }

            Divider().overlay(Color.white.opacity(0.06))

            SettingsToggleRow(
                title: "Respuesta háptica",
                subtitle: "Vibración sutil en el trackpad al expandir o cambiar pestañas.",
                isOn: $prefs.hapticsEnabled
            )
        }
    }
}

// MARK: - Section: Apariencia

private struct AppearanceSettings: View {
    @EnvironmentObject private var prefs: Preferences

    var body: some View {
        SettingsCard("Vista Previa (Modo Contraído)") {
            HStack {
                Spacer()
                CollapsedPreview()
                Spacer()
            }
            .padding(.vertical, 4)
        }

        SettingsCard("Color de Acento") {
            AccentSwatchRow(swatchSize: 24, showsRing: true, includeCustomPicker: true)
            Text("Se aplica en pestañas activas, ecualizador, barras de progreso y zonas de arrastre.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.45))
        }

        SettingsCard("Tamaño del Panel") {
            SettingsControlRow("Preset") {
                Picker("", selection: $prefs.islandSizeMode) {
                    ForEach(Preferences.IslandSizeMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 270)
            }

            if prefs.islandSizeMode == .custom {
                Divider().overlay(Color.white.opacity(0.06))
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
            }

            Divider().overlay(Color.white.opacity(0.06))
            LabeledSlider(
                label: "Redondeo inferior",
                value: $prefs.expandedCornerRadius,
                range: Preferences.cornerRadiusRange,
                format: "%.0f pt",
                valueWidth: 52
            )
        }

        SettingsCard("Indicadores al Lado del Notch") {
            SettingsControlRow("Lado izquierdo") {
                Picker("", selection: $prefs.collapsedLeft) {
                    ForEach(Preferences.CollapsedLeftContent.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 210)
            }

            Divider().overlay(Color.white.opacity(0.06))

            SettingsControlRow("Lado derecho") {
                Picker("", selection: $prefs.collapsedRight) {
                    ForEach(Preferences.CollapsedRightContent.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 250)
            }

            Divider().overlay(Color.white.opacity(0.06))

            SettingsToggleRow(
                title: "Ecualizador animado",
                subtitle: "Muestra barras en movimiento junto a la carátula cuando suena música.",
                isOn: $prefs.showEqualizer
            )
        }

        SettingsCard("Monitores Externos") {
            SettingsToggleRow(
                title: "Mostrar en pantallas sin notch físico",
                subtitle: "Si lo apagás, JNotch solo aparece en la pantalla integrada de la MacBook.",
                isOn: $prefs.showOnNotchlessScreens
            )
        }
    }
}

// MARK: - Section: Módulos

private struct ModuleSettings: View {
    @EnvironmentObject private var prefs: Preferences

    var body: some View {
        SettingsCard("Pestañas Activas") {
            Text("Encendé solo los módulos que uses para mantener la barra bien limpia.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.45))
                .padding(.bottom, 2)

            ForEach(Array(IslandTab.allCases.enumerated()), id: \.element.id) { index, tab in
                if index > 0 {
                    Divider().overlay(Color.white.opacity(0.06))
                }
                HStack(spacing: 10) {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 22)
                        .foregroundStyle(prefs.isTabEnabled(tab) ? prefs.accentColor : .white.opacity(0.35))
                    Text(tab.title)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.9))
                    Spacer()
                    if Preferences.lockedTabs.contains(tab.rawValue) {
                        Text("Fija")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.35))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.white.opacity(0.06)))
                    } else {
                        Toggle("", isOn: Binding(
                            get: { prefs.isTabEnabled(tab) },
                            set: { prefs.setTab(tab, enabled: $0) }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                        .tint(prefs.accentColor)
                    }
                }
                .padding(.vertical, 3)
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
            SettingsControlRow("Máximo de elementos") {
                Picker("", selection: $prefs.clipboardLimit) {
                    ForEach(Preferences.clipboardLimitOptions, id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 170)
            }

            Text("Todo queda guardado localmente en tu Mac. El contenido sensible de gestores de contraseñas se ignora.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.45))

            HStack {
                Spacer()
                Button("Vaciar portapapeles (\(clipboard.items.count))") {
                    confirmClearClipboard = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(clipboard.items.isEmpty)
            }
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
            SettingsToggleRow(
                title: "Vaciar bandeja al salir de JNotch",
                subtitle: "Borra automáticamente los archivos temporales al cerrar la app.",
                isOn: $prefs.clearShelfOnQuit
            )

            HStack {
                Spacer()
                Button("Vaciar bandeja ahora (\(shelf.items.count))") {
                    confirmClearShelf = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(shelf.items.isEmpty)
            }
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
                    Text("JNotch v\(AppInfo.version)")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Centro de control nativo y modular en el notch")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            Text("Construido 100% en Swift + SwiftUI para macOS, diseñado para ser liviano, rápido y personalizable.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.45))
        }

        SettingsCard("Repositorio") {
            Link(destination: URL(string: "https://github.com/joacodelfino/j-notch")!) {
                HStack {
                    Label("github.com/joacodelfino/j-notch", systemImage: "link")
                        .font(.caption)
                        .foregroundStyle(prefs.accentColor)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
        }
    }
}

// MARK: - Shared Building Blocks

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
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
                .kerning(0.6)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
        )
    }
}

private struct SettingsControlRow<Control: View>: View {
    let label: String
    @ViewBuilder let control: Control

    init(_ label: String, @ViewBuilder control: () -> Control) {
        self.label = label
        self.control = control()
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.9))
            Spacer()
            control
        }
    }
}

private struct SettingsToggleRow: View {
    @EnvironmentObject private var prefs: Preferences
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.9))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .tint(prefs.accentColor)
        }
    }
}

private struct LabeledSlider: View {
    @EnvironmentObject private var prefs: Preferences
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String
    var valueWidth: CGFloat = 46

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 130, alignment: .leading)
            Slider(value: $value, in: range)
                .tint(prefs.accentColor)
            Text(String(format: format, value))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: valueWidth, alignment: .trailing)
        }
    }
}

struct AccentSwatchRow: View {
    @EnvironmentObject private var prefs: Preferences
    var swatchSize: CGFloat = 22
    var showsRing: Bool = true
    var includeCustomPicker: Bool = true

    var body: some View {
        HStack(spacing: swatchSize > 18 ? 10 : 7) {
            ForEach(Preferences.accentPalette) { option in
                Button {
                    prefs.accentHex = option.hex
                } label: {
                    Circle()
                        .fill(option.color)
                        .frame(width: swatchSize, height: swatchSize)
                        .overlay {
                            if prefs.accentHex.uppercased() == option.hex.uppercased() {
                                Image(systemName: "checkmark")
                                    .font(.system(size: swatchSize * 0.4, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .overlay(
                            Circle().strokeBorder(
                                showsRing && prefs.accentHex.uppercased() == option.hex.uppercased()
                                    ? Color.white.opacity(0.85) : .clear,
                                lineWidth: 1.5
                            )
                            .padding(-3)
                        )
                }
                .buttonStyle(.plain)
                .help(option.name)
            }

            if includeCustomPicker {
                ColorPicker("", selection: Binding(
                    get: { prefs.accentColor },
                    set: { prefs.accentHex = $0.hexString }
                ), supportsOpacity: false)
                .labelsHidden()
                .frame(width: swatchSize, height: swatchSize)
                .help("Color personalizado")
            }
            Spacer(minLength: 0)
        }
    }
}

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
            .frame(width: 68)

            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .frame(width: 110, height: 18)
                .overlay(
                    Text("notch")
                        .font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.25))
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
            .frame(width: 68)
        }
        .frame(height: 30)
        .background(
            NotchShape(bottomRadius: 12).fill(Color.black)
        )
        .overlay(
            NotchShape(bottomRadius: 12)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
    }
}

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

// MARK: - In-Notch Settings Tab (2-column balanced layout)

struct SettingsQuickView: View {
    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var clipboard: ClipboardManager
    @EnvironmentObject private var shelf: ShelfManager

    private var toggleableTabs: [IslandTab] {
        IslandTab.allCases.filter { !Preferences.lockedTabs.contains($0.rawValue) }
    }

    private var sizePresets: [Preferences.IslandSizeMode] {
        [.compact, .normal, .large]
    }

    var body: some View {
        HStack(spacing: 10) {
            leftColumn
            rightColumn
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle("Apariencia y Comportamiento", symbol: "slider.horizontal.3", tint: prefs.accentColor)

            // Apertura
            quickSegmentRow(title: "Abrir") {
                quickPill("Hover", active: prefs.hoverToExpand) { prefs.hoverToExpand = true }
                quickPill("Click", active: !prefs.hoverToExpand) { prefs.hoverToExpand = false }
            }

            // Tamaño
            quickSegmentRow(title: "Tamaño") {
                ForEach(sizePresets) { mode in
                    quickPill(mode.title, active: prefs.islandSizeMode == mode) {
                        prefs.islandSizeMode = mode
                    }
                }
            }

            // Velocidad
            quickSegmentRow(title: "Ritmo") {
                ForEach(Preferences.AnimationSpeed.allCases) { speed in
                    quickPill(speed.title, active: prefs.animationSpeed == speed) {
                        prefs.animationSpeed = speed
                    }
                }
            }

            // Color de acento (sin NSColorPanel flotante que robe foco)
            HStack(spacing: 8) {
                Text("Acento")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 48, alignment: .leading)
                AccentSwatchRow(swatchSize: 17, showsRing: true, includeCustomPicker: false)
            }

            Spacer(minLength: 0)

            Divider().overlay(Color.white.opacity(0.08))

            HStack(spacing: 14) {
                quickToggle("Ecualizador", isOn: $prefs.showEqualizer)
                quickToggle("Háptico", isOn: $prefs.hapticsEnabled)
                Spacer(minLength: 0)
            }
        }
        .islandCard()
    }

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                CardTitle("Módulos Visibles", symbol: "square.grid.2x2.fill", tint: prefs.accentColor)
                Spacer()
                ConfirmingButton(title: "Limpiar datos", systemImage: "trash", tint: .white.opacity(0.45)) {
                    clipboard.clearAll()
                    shelf.removeAll()
                }
            }

            VStack(spacing: 5) {
                ForEach(toggleableTabs) { tab in
                    let enabled = prefs.isTabEnabled(tab)
                    Button {
                        withAnimation(Motion.standard) {
                            prefs.setTab(tab, enabled: !enabled)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: tab.symbol)
                                .font(.system(size: 11, weight: .semibold))
                                .frame(width: 18)
                                .foregroundStyle(enabled ? prefs.accentColor : .white.opacity(0.3))
                            Text(tab.title)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(enabled ? .white.opacity(0.9) : .white.opacity(0.4))
                            Spacer()
                            Image(systemName: enabled ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 12))
                                .foregroundStyle(enabled ? prefs.accentColor : .white.opacity(0.2))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(enabled ? 0.07 : 0.03))
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 0)

            Divider().overlay(Color.white.opacity(0.08))

            HStack {
                Button {
                    JNotchApp.delegate?.openSettings()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "macwindow")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Más ajustes…")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(prefs.accentColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(prefs.accentColor.opacity(0.14)))
                }
                .buttonStyle(IslandButtonStyle())

                Spacer()

                Text("v\(AppInfo.version)")
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.28))

                Spacer()

                Button {
                    NSApp.terminate(nil)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "power")
                            .font(.system(size: 9, weight: .bold))
                        Text("Salir")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(.red.opacity(0.85))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.red.opacity(0.12)))
                }
                .buttonStyle(IslandButtonStyle())
            }
        }
        .islandCard()
    }

    private func quickSegmentRow<Buttons: View>(
        title: String,
        @ViewBuilder buttons: () -> Buttons
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 48, alignment: .leading)
            HStack(spacing: 4) {
                buttons()
            }
            .padding(2)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            Spacer(minLength: 0)
        }
    }

    private func quickPill(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? .black : .white.opacity(0.65))
                .padding(.horizontal, 9)
                .padding(.vertical, 3.5)
                .background(
                    Capsule().fill(active ? prefs.accentColor : Color.clear)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func quickToggle(_ label: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isOn.wrappedValue ? "checkmark.square.fill" : "square")
                    .font(.system(size: 11))
                    .foregroundStyle(isOn.wrappedValue ? prefs.accentColor : .white.opacity(0.35))
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.75))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
