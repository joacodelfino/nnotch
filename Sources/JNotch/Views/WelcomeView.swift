import SwiftUI
import ServiceManagement

/// İlk açılışta tek seferlik karşılama. Uygulama accessory olduğu için normalde
/// hiçbir pencere görünmez — ada nerede yaşar, nasıl açılır, nasıl çıkılır
/// burada öğretilir; yoksa kullanıcı uygulamanın çalıştığını fark edemeyebilir.
struct WelcomeView: View {
    @EnvironmentObject private var prefs: Preferences
    let onStart: () -> Void

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(spacing: 18) {
            MiniIslandGlyph(tint: prefs.accentColor)
                .frame(width: 76, height: 52)

            VStack(spacing: 4) {
                Text("Bienvenido a JNotch")
                    .font(.title3.weight(.bold))
                Text("Vive arriba de todo en tu pantalla, integrado en el notch.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                row(
                    symbol: "cursorarrow.motionlines",
                    title: "Acercá el cursor al notch",
                    detail: "Se expande solo; ESC o hacer click afuera lo cierra."
                )
                row(
                    symbol: "tray.and.arrow.down",
                    title: "Arrastrá archivos al notch",
                    detail: "Se abre la bandeja para guardarlos temporalmente o enviarlos por AirDrop."
                )
                row(
                    symbol: "sparkles.rectangle.stack",
                    title: "Ícono en la barra de menú",
                    detail: "Desde ahí siempre tenés acceso rápido a Ajustes y Salir."
                )
            }
            .padding(.vertical, 4)

            Toggle("Iniciar al abrir sesión", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { enabled in
                    do {
                        if enabled {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }

            Button("Empezar") { onStart() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(28)
        .frame(width: 420)
    }

    private func row(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(prefs.accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
