import SwiftUI
import ImageIO

/// Clipboard history: the last 20 copied items, tap any of them to copy again.
struct ClipboardView: View {
    @EnvironmentObject private var clipboard: ClipboardManager
    @State private var copiedID: UUID?

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                CardTitle(
                    "Portapapeles · \(clipboard.items.count)/\(clipboard.maxItems)",
                    symbol: "doc.on.clipboard.fill"
                )
                Spacer()
                if !clipboard.items.isEmpty {
                    ConfirmingButton(title: "Limpiar", systemImage: "trash") {
                        clipboard.clearAll()
                    }
                }
            }
            if clipboard.items.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 30))
                        .foregroundStyle(.white.opacity(0.2))
                    Text("Todavía no copiaste nada")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.5))
                    Text("Acá se guardan tus últimos \(clipboard.maxItems) elementos copiados")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.3))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 5) {
                        ForEach(clipboard.items) { item in
                            ClipboardRow(
                                item: item,
                                copied: copiedID == item.id,
                                onCopy: { copy(item) },
                                onDelete: { withAnimation(Motion.standard) { clipboard.remove(item) } }
                            )
                            .transition(.opacity)
                        }
                    }
                    .animation(Motion.standard, value: clipboard.items)
                }
            }
        }
        .islandCard()
    }

    private func copy(_ item: ClipboardItem) {
        clipboard.copyToPasteboard(item)
        withAnimation(.easeOut(duration: 0.15)) {
            copiedID = item.id
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation { if copiedID == item.id { copiedID = nil } }
        }
    }
}

private struct ClipboardRow: View {
    let item: ClipboardItem
    let copied: Bool
    let onCopy: () -> Void
    let onDelete: () -> Void
    @State private var hovering = false
    @State private var thumbnail: NSImage?

    /// Küçük resimler yol başına bir kez yüklenip önbelleğe alınır; her satır
    /// yeniden çiziminde disk okumayı önler. ~128px'e küçültülür ve sayı sınırlıdır,
    /// böylece tam çözünürlüklü ekran görüntüleri belleği şişirmez.
    private static let thumbnailCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 60
        return cache
    }()

    var body: some View {
        HStack(spacing: 8) {
            preview
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(primaryText)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 4) {
                    Text(kindLabel)
                    Text("·")
                    Text(item.date, format: .dateTime.hour().minute())
                }
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.35))
            }
            Spacer(minLength: 4)
            if copied {
                Label("Copiado", systemImage: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
                    .transition(.opacity.combined(with: .scale))
            } else if hovering {
                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Volver a copiar")
                .accessibilityLabel("Volver a copiar")
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .help("Eliminar")
                .accessibilityLabel("Eliminar")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(hovering ? 0.09 : 0.045))
        )
        .contentShape(RoundedRectangle(cornerRadius: 9))
        .onHover { hovering = $0 }
        .onTapGesture(perform: onCopy)
        .contextMenu {
            Button("Copiar") { onCopy() }
            Button("Eliminar") { onDelete() }
        }
    }

    @ViewBuilder
    private var preview: some View {
        Group {
            switch item.kind {
            case .image:
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 30, height: 30)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    iconPreview("photo", tint: .purple)
                }
            case .file:
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .frame(width: 26, height: 26)
                } else {
                    iconPreview("doc.fill", tint: .white.opacity(0.6))
                }
            case .link:
                iconPreview("link", tint: .blue)
            case .text:
                iconPreview("text.alignleft", tint: .white.opacity(0.6))
            }
        }
        .task(id: item.id) { await loadThumbnail() }
    }

    private func loadThumbnail() async {
        guard item.kind == .image || item.kind == .file else { return }
        let key = item.value as NSString
        if let cached = Self.thumbnailCache.object(forKey: key) {
            thumbnail = cached
            return
        }
        switch item.kind {
        case .image:
            let url = URL(fileURLWithPath: item.value)
            let image = await Task.detached(priority: .utility) {
                ImageThumbnail.make(url: url, maxPixel: 128)
            }.value
            guard !Task.isCancelled, let image else { return }
            Self.thumbnailCache.setObject(image, forKey: key)
            thumbnail = image
        case .file:
            // Dosya ikonu sistem önbelleğinden gelir, ucuz — doğrudan main'de.
            let image = NSWorkspace.shared.icon(forFile: item.value)
            Self.thumbnailCache.setObject(image, forKey: key)
            thumbnail = image
        default:
            break
        }
    }

    private func iconPreview(_ symbol: String, tint: Color) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.white.opacity(0.07))
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: 12))
                    .foregroundStyle(tint)
            )
    }

    private var primaryText: String {
        switch item.kind {
        case .file:
            return URL(fileURLWithPath: item.value).lastPathComponent
        case .image:
            return "Imagen"
        case .text, .link:
            return String(item.value.prefix(512))
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ")
        }
    }

    private var kindLabel: String {
        switch item.kind {
        case .text: return "Texto"
        case .link: return "Link"
        case .file: return "Archivo"
        case .image: return "Imagen"
        }
    }
}
