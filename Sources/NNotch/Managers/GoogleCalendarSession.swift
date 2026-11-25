import AppKit
import Combine
import WebKit

/// Gestiona el inicio de sesión directo con Google Calendar mediante una sesión WebKit persistente.
/// El usuario inicia sesión una sola vez con su cuenta de Google (como en un cliente de correo)
/// y la sesión queda guardada en disco para sincronizar sus calendarios automáticamente en segundo plano.
@MainActor
final class GoogleCalendarSession: NSObject, ObservableObject {
    @Published private(set) var isSignedIn: Bool
    @Published private(set) var connectedEmail: String?
    @Published private(set) var isSyncing = false

    var onEventsSynced: (([CalendarEventItem], String?) -> Void)?

    private var loginWindow: NSWindow?
    private var loginWebView: WKWebView?
    private var backgroundWebView: WKWebView?
    private var loginDetected = false

    private static let signedInKey = "google.calendar.isSignedIn"
    private static let emailKey = "google.calendar.email"
    private static let safariUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    override init() {
        let savedSignedIn = UserDefaults.standard.bool(forKey: Self.signedInKey)
        let savedEmail = UserDefaults.standard.string(forKey: Self.emailKey)
        self.isSignedIn = savedSignedIn
        self.connectedEmail = savedEmail
        super.init()
    }

    // MARK: - Interactive Sign-In Window

    func startInteractiveSignIn() {
        loginDetected = false
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 620), configuration: config)
        webView.customUserAgent = Self.safariUserAgent
        webView.navigationDelegate = self
        self.loginWebView = webView

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 620),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Iniciar sesión con Google — nnotch"
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = webView
        window.center()
        self.loginWindow = window

        if let url = URL(string: "https://accounts.google.com/ServiceLogin?service=cl&passive=true&continue=https://calendar.google.com/calendar/u/0/r") {
            webView.load(URLRequest(url: url))
        }

        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func signOut() {
        isSignedIn = false
        connectedEmail = nil
        UserDefaults.standard.set(false, forKey: Self.signedInKey)
        UserDefaults.standard.removeObject(forKey: Self.emailKey)

        let dataStore = WKWebsiteDataStore.default()
        dataStore.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            let googleRecords = records.filter {
                $0.displayName.contains("google") || $0.displayName.contains("youtube") || $0.displayName.contains("gstatic")
            }
            dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: googleRecords) {}
        }
        onEventsSynced?([], nil)
    }

    // MARK: - Background Sync via Persisted Session Cookies

    func syncInBackground() {
        guard isSignedIn, !isSyncing else { return }
        isSyncing = true

        let cookieStore = WKWebsiteDataStore.default().httpCookieStore
        cookieStore.getAllCookies { [weak self] cookies in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let googleCookies = cookies.filter {
                    $0.domain.contains("google.com")
                }
                guard !googleCookies.isEmpty else {
                    self.isSyncing = false
                    return
                }
                await self.downloadAndParseGoogleExport(cookies: googleCookies)
            }
        }
    }

    private func downloadAndParseGoogleExport(cookies: [HTTPCookie]) async {
        guard let exportURL = URL(string: "https://calendar.google.com/calendar/u/0/export") else {
            isSyncing = false
            return
        }

        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.httpShouldSetCookies = true
        sessionConfig.httpCookieAcceptPolicy = .always
        let storage = HTTPCookieStorage()
        for cookie in cookies {
            storage.setCookie(cookie)
        }
        sessionConfig.httpCookieStorage = storage

        var request = URLRequest(url: exportURL)
        request.timeoutInterval = 15
        request.setValue(Self.safariUserAgent, forHTTPHeaderField: "User-Agent")
        let headerFields = HTTPCookie.requestHeaderFields(with: cookies)
        for (k, v) in headerFields {
            request.setValue(v, forHTTPHeaderField: k)
        }

        do {
            let session = URLSession(configuration: sessionConfig)
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse,
               let finalHost = http.url?.host,
               finalHost.contains("accounts.google.com") {
                // La sesión expiró
                isSyncing = false
                onEventsSynced?([], "La sesión de Google expiró. Volvé a iniciar sesión.")
                return
            }

            let events = await Task.detached(priority: .utility) {
                Self.extractAndParseZipOrICS(data: data, accountLabel: "Google Calendar")
            }.value

            isSyncing = false
            onEventsSynced?(events, nil)
        } catch {
            isSyncing = false
            onEventsSynced?([], "No se pudo sincronizar Google Calendar")
        }
    }

    /// Descomprime el ZIP de exportación de Google Calendar (o lee un .ics directo) y parsea todos los calendarios.
    nonisolated private static func extractAndParseZipOrICS(data: Data, accountLabel: String) -> [CalendarEventItem] {
        guard data.count > 4 else { return [] }

        // Si empieza con "BEGIN:VCALENDAR", es un .ics directo
        if let prefix = String(data: data.prefix(32), encoding: .utf8),
           prefix.contains("BEGIN:VCALENDAR") {
            let text = String(data: data, encoding: .utf8) ?? ""
            let feed = ExternalCalendarFeed(
                id: UUID(),
                name: accountLabel,
                urlString: "google://session",
                provider: .google,
                colorHex: "#0A84FF"
            )
            return CalendarManager.parseICS(text: text, feed: feed)
        }

        // Si empieza con "PK" (0x50, 0x4B), es el archivo ZIP con los .ics de cada calendario de la cuenta Google
        let bytes = [UInt8](data.prefix(2))
        guard bytes == [0x50, 0x4B] else { return [] }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nnotch-gcal-\(UUID().uuidString)", isDirectory: true)
        let zipURL = tempDir.appendingPathComponent("export.zip")
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            try data.write(to: zipURL)

            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            proc.arguments = ["-qq", "-o", zipURL.path, "-d", tempDir.path]
            try proc.run()
            proc.waitUntilExit()

            let contents = (try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)) ?? []
            let palette = ["#0A84FF", "#30D158", "#BF5AF2", "#FF9F0A", "#64D2FF", "#FF375F"]
            var allParsed: [CalendarEventItem] = []

            for (idx, fileURL) in contents.enumerated() where fileURL.pathExtension.lowercased() == "ics" {
                guard let rawData = try? Data(contentsOf: fileURL),
                      let text = String(data: rawData, encoding: .utf8) ?? String(data: rawData, encoding: .isoLatin1) else {
                    continue
                }
                let rawName = fileURL.deletingPathExtension().lastPathComponent
                    .replacingOccurrences(of: "_gmail.com", with: "@gmail.com")
                let calName = extractCalendarName(from: text) ?? rawName
                let feed = ExternalCalendarFeed(
                    id: UUID(),
                    name: "Google · \(calName)",
                    urlString: "google://\(calName)",
                    provider: .google,
                    colorHex: palette[idx % palette.count]
                )
                allParsed.append(contentsOf: CalendarManager.parseICS(text: text, feed: feed))
            }
            return allParsed
        } catch {
            return []
        }
    }

    nonisolated private static func extractCalendarName(from icsText: String) -> String? {
        for line in icsText.prefix(2048).components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.uppercased().hasPrefix("X-WR-CALNAME:") {
                let name = String(trimmed.dropFirst("X-WR-CALNAME:".count)).trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { return name }
            }
        }
        return nil
    }
}

extension GoogleCalendarSession: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url,
              let host = url.host?.lowercased() else { return }

        // Apenas Google redirige a calendar.google.com después del login, guardamos la sesión
        if host == "calendar.google.com" && !url.path.contains("ServiceLogin") && !loginDetected {
            loginDetected = true
            isSignedIn = true
            UserDefaults.standard.set(true, forKey: Self.signedInKey)

            // Intentamos leer el email de la cuenta logueada desde el DOM
            let emailJS = """
            (function(){
              var el = document.querySelector('[data-email]') || document.querySelector('a[aria-label*="@"]');
              if (el) {
                var e = el.getAttribute('data-email') || el.getAttribute('aria-label') || '';
                var m = e.match(/[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}/);
                if (m) return m[0];
              }
              var html = document.documentElement.innerHTML;
              var m2 = html.match(/[a-zA-Z0-9._%+-]+@gmail\\.com/);
              return m2 ? m2[0] : 'Cuenta de Google';
            })()
            """
            webView.evaluateJavaScript(emailJS) { [weak self] result, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let email = result as? String, !email.isEmpty {
                        self.connectedEmail = email
                        UserDefaults.standard.set(email, forKey: Self.emailKey)
                    } else if self.connectedEmail == nil {
                        self.connectedEmail = "Cuenta de Google"
                        UserDefaults.standard.set("Cuenta de Google", forKey: Self.emailKey)
                    }
                    self.loginWindow?.close()
                    self.loginWindow = nil
                    self.loginWebView = nil
                    self.syncInBackground()
                }
            }
        }
    }
}
