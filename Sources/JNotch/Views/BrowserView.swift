import SwiftUI

/// Pencere değiştirmeden hızlı arama: çentik içinde mini tarayıcı.
struct BrowserView: View {
    @EnvironmentObject private var browser: BrowserModel
    @FocusState private var addressFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Button { browser.goBack() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(browser.canGoBack ? .white : .white.opacity(0.25))
                .disabled(!browser.canGoBack)

                Button { browser.goForward() } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(browser.canGoForward ? .white : .white.opacity(0.25))
                .disabled(!browser.canGoForward)

                HStack(spacing: 5) {
                    Image(systemName: browser.isLoading ? "arrow.triangle.2.circlepath" : "magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                    TextField("Buscá o escribí una URL…", text: $browser.addressText)
                        .textFieldStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .focused($addressFocused)
                        .onSubmit { browser.submit() }
                        .onChange(of: addressFocused) { browser.isEditingAddress = $0 }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(0.08)))

                Button { browser.reload() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.6))
                .help("Recargar")

                Button { browser.openInDefaultBrowser() } label: {
                    Image(systemName: "safari")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.6))
                .help("Abrir en el navegador predeterminado")
            }

            if browser.loadFailed {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 28))
                        .foregroundStyle(.white.opacity(0.25))
                    Text("No se pudo cargar la página")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.55))
                    Text("Revisá tu conexión y volvé a intentar")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.35))
                    Button("Reintentar") { browser.retry() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
            } else if browser.hasPage {
                WebViewRepresentable(webView: browser.webView)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
            } else {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "globe")
                        .font(.system(size: 28))
                        .foregroundStyle(.white.opacity(0.2))
                    Text("Buscá rápido sin cambiar de ventana")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                    HStack(spacing: 6) {
                        quickLink("Google", "google.com")
                        quickLink("YouTube", "youtube.com")
                        quickLink("Wikipedia", "wikipedia.org")
                        quickLink("ChatGPT", "chatgpt.com")
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
                .onTapGesture { addressFocused = true }
            }
        }
    }

    private func quickLink(_ title: String, _ url: String) -> some View {
        Button {
            browser.load(url)
        } label: {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }
}
