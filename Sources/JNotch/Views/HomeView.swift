import SwiftUI
import UniformTypeIdentifiers

/// Landing tab: music player, AirDrop + shelf drop zones, app shortcuts, quick stats.
struct HomeView: View {
    var body: some View {
        HStack(spacing: 12) {
            MusicCard()
                .frame(width: 262)
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    AirDropZone()
                    ShelfDropZone()
                }
                ShortcutsRow()
                StatsRow()
            }
        }
    }
}

// MARK: - Music

struct MusicCard: View {
    @EnvironmentObject private var music: MusicManager
    @EnvironmentObject private var prefs: Preferences
    @State private var dragFraction: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let playing = music.nowPlaying {
                HStack(alignment: .top, spacing: 10) {
                    artworkView
                    VStack(alignment: .leading, spacing: 3) {
                        Text(playing.title)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        Text(playing.artist)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        HStack(spacing: 4) {
                            Image(systemName: playing.isWeb ? "globe" : "waveform")
                                .font(.system(size: 8, weight: .semibold))
                            Text(playing.sourceLabel)
                                .font(.system(size: 9, weight: .semibold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(prefs.accentColor.opacity(0.85))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                progressBar(playing)
                controls
            } else if music.automationDenied {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "lock.shield")
                        .font(.system(size: 26))
                        .foregroundStyle(.white.opacity(0.25))
                    Text("Se requiere permiso de Automatización")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.5))
                    Text("Permití a JNotch leer el estado de reproducción")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.3))
                        .multilineTextAlignment(.center)
                    Button("Abrir Configuración del Sistema") {
                        SystemSettingsPane.automation.open()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "music.note.list")
                        .font(.system(size: 26))
                        .foregroundStyle(.white.opacity(0.25))
                    Text("Sin audio en reproducción")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.5))
                    Text("YouTube, navegador, Spotify o Apple Music")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.3))
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .islandCard()
    }

    @ViewBuilder
    private var artworkView: some View {
        Button {
            music.activateSource()
        } label: {
            if let artwork = music.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 84, height: 84)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 24))
                            .foregroundStyle(.white.opacity(0.3))
                    )
            }
        }
        .buttonStyle(.plain)
        .help("Ir a la aplicación o pestaña en reproducción")
    }

    private func progressBar(_ playing: NowPlaying) -> some View {
        // Web Spotify'da süre yalnızca Chrome/Safari "Allow JavaScript from Apple Events" açıkken
        // okunabiliyor; duration <= 0 bunun kapalı olduğu anlamına gelir — o durumda çubuğu
        // yanıltıcı "0:00" yerine devre dışı gösteriyoruz.
        let canSeek = playing.duration > 0
        let liveFraction = dragFraction ?? (canSeek ? min(playing.position / playing.duration, 1) : 0)
        return VStack(spacing: 3) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(prefs.accentColor)
                        .frame(width: geo.size.width * liveFraction)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard canSeek, geo.size.width > 0 else { return }
                            dragFraction = min(max(value.location.x / geo.size.width, 0), 1)
                        }
                        .onEnded { value in
                            guard canSeek, geo.size.width > 0 else { return }
                            music.seek(toFraction: min(max(value.location.x / geo.size.width, 0), 1))
                            dragFraction = nil
                        }
                )
            }
            .frame(height: 3)
            if canSeek {
                HStack {
                    Text(TimerCenter.format(playing.position))
                    Spacer()
                    Text(TimerCenter.format(playing.duration))
                }
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(.white.opacity(0.4))
            }
        }
    }

    private var controls: some View {
        HStack {
            Spacer()
            Button { music.previousTrack() } label: {
                Image(systemName: "backward.fill").font(.system(size: 14))
            }
            .buttonStyle(IslandButtonStyle())
            .foregroundStyle(.white.opacity(0.8))
            .accessibilityLabel("Canción anterior")
            Button { music.playPause() } label: {
                Image(systemName: (music.nowPlaying?.isPlaying ?? false) ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 30))
            }
            .buttonStyle(IslandButtonStyle())
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .accessibilityLabel((music.nowPlaying?.isPlaying ?? false) ? "Pausar" : "Reproducir")
            Button { music.nextTrack() } label: {
                Image(systemName: "forward.fill").font(.system(size: 14))
            }
            .buttonStyle(IslandButtonStyle())
            .foregroundStyle(.white.opacity(0.8))
            .accessibilityLabel("Siguiente canción")
            Spacer()
        }
    }
}

// MARK: - Drop zones

struct AirDropZone: View {
    @EnvironmentObject private var shelf: ShelfManager
    @EnvironmentObject private var prefs: Preferences
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(isTargeted ? prefs.accentColor : .white.opacity(0.7))
            Text("AirDrop")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.55))
            Text("Soltá archivos acá")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isTargeted ? prefs.accentColor.opacity(0.18) : Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isTargeted ? prefs.accentColor.opacity(0.7) : Color.white.opacity(0.06),
                    style: StrokeStyle(lineWidth: 1, dash: isTargeted ? [4] : [])
                )
        )
        .animation(Motion.quick, value: isTargeted)
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            DropUtilities.loadFileURLs(from: providers) { urls in
                shelf.airDrop(urls: urls)
            }
            return true
        }
    }
}

struct ShelfDropZone: View {
    @EnvironmentObject private var vm: NotchViewModel
    @EnvironmentObject private var shelf: ShelfManager
    @EnvironmentObject private var prefs: Preferences
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 6) {
            if shelf.items.isEmpty {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(isTargeted ? prefs.accentColor : .white.opacity(0.7))
                Text("Bandeja")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.55))
                Text("Guardá archivos al paso")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.3))
            } else {
                HStack(spacing: -8) {
                    ForEach(shelf.items.prefix(3)) { item in
                        Image(nsImage: shelf.icon(for: item))
                            .resizable()
                            .frame(width: 30, height: 30)
                    }
                }
                Text("Bandeja · \(shelf.items.count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isTargeted ? prefs.accentColor.opacity(0.15) : Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isTargeted ? prefs.accentColor.opacity(0.7) : Color.white.opacity(0.06),
                    style: StrokeStyle(lineWidth: 1, dash: isTargeted ? [4] : [])
                )
        )
        .animation(Motion.quick, value: isTargeted)
        .onTapGesture { vm.activeTab = .shelf }
        .onDrop(of: [UTType.fileURL, UTType.image, UTType.plainText], isTargeted: $isTargeted) { providers in
            shelf.handle(providers: providers)
        }
    }
}

// MARK: - Shortcuts

struct ShortcutsRow: View {
    @EnvironmentObject private var shortcuts: AppShortcutsStore
    @EnvironmentObject private var prefs: Preferences
    @State private var isEditing = false
    @State private var isDropTargeted = false

    var body: some View {
        HStack(spacing: 8) {
            CardTitle("Accesos", symbol: "square.grid.2x2")

            if shortcuts.shortcuts.isEmpty {
                Spacer()
                Text("Tocá + o arrastrá una app")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.3))
                Spacer()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(shortcuts.shortcuts) { shortcut in
                            ShortcutItemButton(
                                shortcut: shortcut,
                                icon: shortcuts.icon(for: shortcut),
                                isEditing: isEditing,
                                onLaunch: { shortcuts.launch(shortcut) },
                                onRemove: {
                                    withAnimation(Motion.standard) {
                                        shortcuts.remove(shortcut)
                                        if shortcuts.shortcuts.isEmpty {
                                            isEditing = false
                                        }
                                    }
                                }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 2)
                }
            }

            if !shortcuts.shortcuts.isEmpty {
                Button {
                    withAnimation(Motion.quick) {
                        isEditing.toggle()
                    }
                } label: {
                    Image(systemName: isEditing ? "checkmark" : "minus.circle")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isEditing ? prefs.accentColor : .white.opacity(0.55))
                        .frame(width: 22, height: 22)
                        .background(
                            Circle().fill(isEditing ? prefs.accentColor.opacity(0.18) : Color.white.opacity(0.08))
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(IslandButtonStyle())
                .help(isEditing ? "Terminar edición" : "Quitar accesos")
            }

            Button {
                shortcuts.addViaOpenPanel()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.white.opacity(0.08)))
                    .contentShape(Circle())
            }
            .buttonStyle(IslandButtonStyle())
            .help("Agregar aplicación")
            .accessibilityLabel("Agregar aplicación")
        }
        .padding(.horizontal, 10)
        .frame(height: 46)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isDropTargeted ? prefs.accentColor.opacity(0.14) : Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isDropTargeted ? prefs.accentColor.opacity(0.6) : Color.clear,
                    lineWidth: 1
                )
        )
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
            DropUtilities.loadFileURLs(from: providers) { urls in
                for url in urls where url.pathExtension.lowercased() == "app" {
                    shortcuts.add(url: url)
                }
            }
            return true
        }
    }
}

private struct ShortcutItemButton: View {
    let shortcut: AppShortcut
    let icon: NSImage
    let isEditing: Bool
    let onLaunch: () -> Void
    let onRemove: () -> Void
    @State private var hovering = false

    private var showRemoveBadge: Bool {
        isEditing || hovering
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button {
                if isEditing {
                    onRemove()
                } else {
                    onLaunch()
                }
            } label: {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 26, height: 26)
                    .opacity(isEditing ? 0.78 : 1.0)
            }
            .buttonStyle(IslandButtonStyle())
            .help(isEditing ? "Click para quitar \(shortcut.name)" : shortcut.name)
            .accessibilityLabel("Abrir \(shortcut.name)")

            if showRemoveBadge {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .red)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .offset(x: 5, y: -4)
                .help("Quitar \(shortcut.name)")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 30, height: 30)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Abrir") { onLaunch() }
            Divider()
            Button("Quitar", role: .destructive) { onRemove() }
        }
    }
}

// MARK: - Quick stats

struct StatsRow: View {
    @EnvironmentObject private var network: NetworkMonitor
    @EnvironmentObject private var stats: SystemStats

    var body: some View {
        HStack(spacing: 12) {
            stat(symbol: "arrow.down", text: NetworkMonitor.format(network.downloadBps), tint: .green)
            stat(symbol: "arrow.up", text: NetworkMonitor.format(network.uploadBps), tint: .blue)
            Divider().frame(height: 16).overlay(Color.white.opacity(0.15))
            stat(symbol: "cpu", text: String(format: "%%%.0f", stats.cpuUsage * 100), tint: .orange)
            stat(
                symbol: "memorychip",
                text: String(format: "%.1f GB", stats.memoryUsedGB),
                tint: .purple
            )
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    private func stat(symbol: String, text: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.75))
        }
    }
}
