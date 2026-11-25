import AppKit
import Combine
import CoreAudio
import CoreGraphics
import os

struct NowPlaying: Equatable {
    var sourceLabel: String
    var bundleID: String?
    var title: String
    var artist: String
    var isPlaying: Bool
    var duration: Double
    var position: Double
    var isWeb: Bool = false
    var artworkURL: String? = nil
    var webBrowserApp: String? = nil
    var webWindowIndex: Int? = nil
    var webTabIndex: Int? = nil
    var webTabURL: String? = nil

    var trackKey: String { "\(sourceLabel)|\(title)|\(artist)|\(artworkURL ?? "")" }
}

/// Motor multimedia universal: detecta Spotify, Apple Music, YouTube y cualquier pestaña web
/// o aplicación reproduciendo sonido (Brave, Chrome, Safari, Arc, Edge, Vivaldi, Zen, Firefox, etc.)
/// combinando CoreAudio (estado real de salida de audio por proceso) + AppleScript + oEmbed.
@MainActor
final class MusicManager: ObservableObject {
    @Published private(set) var nowPlaying: NowPlaying?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var webJSPermissionMissing = false
    @Published private(set) var automationDenied = false

    private var timer: Timer?
    private var pollInFlight = false
    private var lastArtworkKey = ""
    private let scriptQueue = DispatchQueue(label: "nnotch.music", qos: .utility)
    private let artworkCache = NSCache<NSString, NSImage>()
    nonisolated(unsafe) private static let ytMetaCache = NSCache<NSString, NSDictionary>()
    private var seekGeneration = 0
    private var lastSeek: (trackKey: String, position: Double, generation: Int)?
    /// Evita que el drenaje del buffer de CoreAudio (~0.8s al pausar en Safari/Brave) pise el estado recién alternado.
    private var manualPlayStateOverride: (isPlaying: Bool, until: Date)?
    /// Historial de URLs de YouTube reproducidas para que el botón "Anterior" vuelva al video previo.
    private var youtubeHistoryStack: [String] = []
    private var visitedYouTubeIDs: [String] = []
    nonisolated private static let log = Logger(subsystem: "com.joacodelfino.nnotch", category: "Music")

    private let activeInterval: TimeInterval = 1.5
    private let idleInterval: TimeInterval = 4.0
    private var pollInterval: TimeInterval = 1.5

    private struct BrowserSpec: Sendable {
        let bundleID: String
        let appName: String
        let shortName: String
        let kind: Kind

        enum Kind: Sendable {
            case chromium
            case safari
            case windowTitleOnly // Zen, Firefox
        }
    }

    nonisolated private static let spotifyBundleID = "com.spotify.client"
    nonisolated private static let musicBundleID = "com.apple.Music"

    nonisolated private static let browsers: [BrowserSpec] = [
        BrowserSpec(bundleID: "com.brave.Browser", appName: "Brave Browser", shortName: "Brave", kind: .chromium),
        BrowserSpec(bundleID: "com.google.Chrome", appName: "Google Chrome", shortName: "Chrome", kind: .chromium),
        BrowserSpec(bundleID: "company.thebrowser.Browser", appName: "Arc", shortName: "Arc", kind: .chromium),
        BrowserSpec(bundleID: "com.microsoft.edgemac", appName: "Microsoft Edge", shortName: "Edge", kind: .chromium),
        BrowserSpec(bundleID: "com.vivaldi.Vivaldi", appName: "Vivaldi", shortName: "Vivaldi", kind: .chromium),
        BrowserSpec(bundleID: "com.apple.Safari", appName: "Safari", shortName: "Safari", kind: .safari),
        BrowserSpec(bundleID: "app.zen-browser.zen", appName: "Zen", shortName: "Zen", kind: .windowTitleOnly),
        BrowserSpec(bundleID: "org.mozilla.firefox", appName: "Firefox", shortName: "Firefox", kind: .windowTitleOnly),
    ]

    /// Procesos del sistema que ignoramos en el fallback genérico de CoreAudio.
    nonisolated private static let ignoredAudioBundlePrefixes: [String] = [
        "com.apple.systemsound",
        "com.apple.corespeechd",
        "com.apple.Siri",
        "com.apple.loginwindow",
        "com.apple.finder",
        "com.apple.NotificationCenter",
        "com.joacodelfino.nnotch",
    ]

    init() {
        artworkCache.countLimit = 48
        Self.ytMetaCache.countLimit = 64
        scheduleTimer(interval: activeInterval)
        poll()
    }

    func refresh() { poll() }

    deinit { timer?.invalidate() }

    private func scheduleTimer(interval: TimeInterval) {
        timer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        pollInterval = interval
    }

    private func applyPollInterval(active: Bool) {
        let desired = active ? activeInterval : idleInterval
        guard desired != pollInterval else { return }
        scheduleTimer(interval: desired)
    }

    nonisolated private static func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    // MARK: - CoreAudio Active Output Detection

    private struct ActiveAudioApp: Sendable {
        let pid: pid_t
        let bundleID: String
        let localizedName: String
    }

    /// Devuelve las aplicaciones que están emitiendo sonido real en este instante vía CoreAudio.
    nonisolated private static func activeAudioApps() -> [ActiveAudioApp] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        ) == noErr, dataSize > 0 else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var objectIDs = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &objectIDs
        ) == noErr else { return [] }

        var results: [ActiveAudioApp] = []
        for objID in objectIDs {
            var outAddr = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyIsRunningOutput,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var isRunning: UInt32 = 0
            var runSize = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(objID, &outAddr, 0, nil, &runSize, &isRunning) == noErr,
                  isRunning != 0 else { continue }

            var pidAddr = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyPID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var pid: pid_t = 0
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            _ = AudioObjectGetPropertyData(objID, &pidAddr, 0, nil, &pidSize, &pid)

            var bidAddr = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyBundleID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var unmanagedStr: Unmanaged<CFString>?
            var bidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var rawBundleID = ""
            if AudioObjectGetPropertyData(objID, &bidAddr, 0, nil, &bidSize, &unmanagedStr) == noErr,
               let cf = unmanagedStr?.takeRetainedValue() {
                rawBundleID = cf as String
            }

            let resolved = normalizeAudioSource(pid: pid, rawBundleID: rawBundleID)
            if !resolved.bundleID.isEmpty,
               !results.contains(where: { $0.bundleID == resolved.bundleID }) {
                results.append(resolved)
            }
        }
        return results
    }

    /// Mapea procesos helper (Brave Helper, Chrome Helper, WebKit.GPU, plugin-container) a su app principal.
    nonisolated private static func normalizeAudioSource(pid: pid_t, rawBundleID: String) -> ActiveAudioApp {
        for b in browsers {
            if rawBundleID == b.bundleID || rawBundleID.hasPrefix(b.bundleID + ".") {
                return ActiveAudioApp(pid: pid, bundleID: b.bundleID, localizedName: b.shortName)
            }
        }
        if rawBundleID.hasPrefix("com.apple.WebKit") && isRunning("com.apple.Safari") {
            return ActiveAudioApp(pid: pid, bundleID: "com.apple.Safari", localizedName: "Safari")
        }
        if rawBundleID.hasPrefix("org.mozilla.plugincontainer") {
            if isRunning("app.zen-browser.zen") {
                return ActiveAudioApp(pid: pid, bundleID: "app.zen-browser.zen", localizedName: "Zen")
            }
            if isRunning("org.mozilla.firefox") {
                return ActiveAudioApp(pid: pid, bundleID: "org.mozilla.firefox", localizedName: "Firefox")
            }
        }
        if let app = NSRunningApplication(processIdentifier: pid) {
            let bid = app.bundleIdentifier ?? rawBundleID
            let name = app.localizedName ?? bid
            return ActiveAudioApp(pid: pid, bundleID: bid, localizedName: name)
        }
        return ActiveAudioApp(pid: pid, bundleID: rawBundleID, localizedName: rawBundleID)
    }

    // MARK: - Polling

    private func poll() {
        guard !pollInFlight else { return }
        pollInFlight = true
        let startGen = seekGeneration

        scriptQueue.async { [weak self] in
            Self.sawAutomationDenied = false
            let audioApps = Self.activeAudioApps()
            let audioBundleIDs = Set(audioApps.map(\.bundleID))

            let spotifyRunning = Self.isRunning(Self.spotifyBundleID)
            let musicRunning = Self.isRunning(Self.musicBundleID)
            let runningBrowsers = Self.browsers.filter { Self.isRunning($0.bundleID) }

            var candidates: [NowPlaying] = []
            var webJSMissingForChosen = false

            // 1. Spotify nativo
            if spotifyRunning, let sp = Self.querySpotify() {
                candidates.append(sp)
            }

            // 2. Apple Music nativo
            if musicRunning, let am = Self.queryAppleMusic() {
                candidates.append(am)
            }

            // 3. Navegadores Web (YouTube, Spotify Web, SoundCloud, Twitch, Netflix, cursos, o cualquier tab con audio)
            var missingJSBundles = Set<String>()
            for browser in runningBrowsers {
                let browserHasAudio = audioBundleIDs.contains(browser.bundleID)
                if let result = Self.queryBrowser(browser, isOutputtingAudio: browserHasAudio) {
                    candidates.append(result.nowPlaying)
                    if result.jsPermissionMissing {
                        missingJSBundles.insert(browser.bundleID)
                    }
                } else if browserHasAudio {
                    // El navegador emite sonido, pero no pudimos identificar su pestaña.
                    missingJSBundles.insert(browser.bundleID)
                    candidates.append(
                        NowPlaying(
                            sourceLabel: browser.shortName,
                            bundleID: browser.bundleID,
                            title: "Reproduciendo en \(browser.shortName)",
                            artist: "Audio web activo",
                            isPlaying: true,
                            duration: 0,
                            position: 0,
                            isWeb: true,
                            webBrowserApp: browser.appName
                        )
                    )
                }
            }

            // 4. Otras apps nativas emitiendo audio (ej. Prime Video, VLC, IINA, QuickTime, etc.)
            for audioApp in audioApps {
                let bid = audioApp.bundleID
                if bid == Self.spotifyBundleID || bid == Self.musicBundleID { continue }
                if Self.browsers.contains(where: { $0.bundleID == bid }) { continue }
                if Self.ignoredAudioBundlePrefixes.contains(where: { bid.hasPrefix($0) }) { continue }
                if candidates.contains(where: { $0.bundleID == bid }) { continue }

                candidates.append(
                    NowPlaying(
                        sourceLabel: audioApp.localizedName,
                        bundleID: bid,
                        title: audioApp.localizedName,
                        artist: "Reproduciendo audio",
                        isPlaying: true,
                        duration: 0,
                        position: 0,
                        isWeb: false
                    )
                )
            }

            // Prioridad: primero lo que esté activamente sonando; si todo está en pausa, el primero disponible.
            let chosen = candidates.first(where: { $0.isPlaying }) ?? candidates.first
            if let bid = chosen?.bundleID, chosen?.isWeb == true, missingJSBundles.contains(bid) {
                webJSMissingForChosen = true
            }
            let denied = Self.sawAutomationDenied && chosen == nil

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.pollInFlight = false
                self.automationDenied = denied

                var final = chosen
                if let s = self.lastSeek, var f = final,
                   f.trackKey == s.trackKey, startGen < s.generation {
                    f.position = s.position
                    final = f
                }
                if let override = self.manualPlayStateOverride {
                    if Date() < override.until {
                        final?.isPlaying = override.isPlaying
                    } else {
                        self.manualPlayStateOverride = nil
                    }
                }
                if let prevURL = self.nowPlaying?.webTabURL,
                   let newURL = final?.webTabURL,
                   prevURL != newURL,
                   Self.extractYouTubeID(from: prevURL) != nil {
                    if self.youtubeHistoryStack.last != prevURL {
                        self.youtubeHistoryStack.append(prevURL)
                        if self.youtubeHistoryStack.count > 25 {
                            self.youtubeHistoryStack.removeFirst()
                        }
                    }
                }
                if let ytID = final?.webTabURL.flatMap({ Self.extractYouTubeID(from: $0) }) {
                    if !self.visitedYouTubeIDs.contains(ytID) {
                        self.visitedYouTubeIDs.append(ytID)
                        if self.visitedYouTubeIDs.count > 30 {
                            self.visitedYouTubeIDs.removeFirst()
                        }
                    }
                }

                self.nowPlaying = final
                self.webJSPermissionMissing = webJSMissingForChosen
                self.applyPollInterval(active: final != nil)
                self.refreshArtworkIfNeeded(for: final)
            }
        }
    }

    // MARK: - Native Spotify & Apple Music

    nonisolated private static func querySpotify() -> NowPlaying? {
        let result = runScript(
            """
            tell application "Spotify"
                if player state is stopped then return "stopped"
                set t to current track
                return (player state as string) & "|~|" & (name of t) & "|~|" & (artist of t) & "|~|" & ((duration of t) / 1000) & "|~|" & player position & "|~|" & (artwork url of t)
            end tell
            """
        )
        guard let parts = split(result), parts.count >= 6 else { return nil }
        return NowPlaying(
            sourceLabel: "Spotify",
            bundleID: spotifyBundleID,
            title: parts[1],
            artist: parts[2],
            isPlaying: parts[0] == "playing",
            duration: Double(parts[3]) ?? 0,
            position: Double(parts[4]) ?? 0,
            artworkURL: parts[5].isEmpty ? nil : parts[5]
        )
    }

    nonisolated private static func queryAppleMusic() -> NowPlaying? {
        let result = runScript(
            """
            tell application "Music"
                if player state is stopped then return "stopped"
                try
                    set t to current track
                    return (player state as string) & "|~|" & (name of t) & "|~|" & (artist of t) & "|~|" & (duration of t) & "|~|" & player position
                on error
                    return "stopped"
                end try
            end tell
            """
        )
        guard let parts = split(result), parts.count >= 5 else { return nil }
        return NowPlaying(
            sourceLabel: "Apple Music",
            bundleID: musicBundleID,
            title: parts[1],
            artist: parts[2],
            isPlaying: parts[0] == "playing",
            duration: Double(parts[3]) ?? 0,
            position: Double(parts[4]) ?? 0
        )
    }

    // MARK: - Universal Browser Media Query

    private struct BrowserMediaResult {
        var nowPlaying: NowPlaying
        var jsPermissionMissing: Bool
    }

    private struct RawTab {
        let windowIndex: Int
        let tabIndex: Int
        let isActive: Bool
        let title: String
        let url: String
    }

    nonisolated private static func queryBrowser(
        _ browser: BrowserSpec,
        isOutputtingAudio: Bool
    ) -> BrowserMediaResult? {
        switch browser.kind {
        case .windowTitleOnly:
            return queryWindowTitleBrowser(browser, isOutputtingAudio: isOutputtingAudio)
        case .chromium, .safari:
            let tabs = listTabs(for: browser)
            guard !tabs.isEmpty else { return nil }

            // Clasificar pestañas multimedia conocidas (YouTube, YT Music, Spotify, Twitch, SoundCloud, etc.)
            let scored: [(tab: RawTab, score: Int, siteName: String?)] = tabs.compactMap { tab in
                let site = classifyMediaSite(url: tab.url, title: tab.title)
                if let site {
                    // Priorizamos la pestaña activa si hay varias multimedia abiertas
                    let base = site.priority + (tab.isActive ? 15 : 0)
                    return (tab, base, site.name)
                } else if isOutputtingAudio && tab.isActive && !tab.title.isEmpty && !tab.url.hasPrefix("chrome://") && !tab.url.hasPrefix("brave://") && !tab.url.hasPrefix("about:") {
                    // Cualquier otra web app abierta en la pestaña activa cuando este navegador emite sonido
                    return (tab, 10, hostLabel(from: tab.url))
                }
                return nil
            }

            guard let best = scored.max(by: { $0.score < $1.score }) else { return nil }
            let target = best.tab
            let siteName = best.siteName

            // Intentamos leer estado HTML5 / MediaSession vía JS si el navegador lo tiene habilitado
            var jsMissing = false
            var playing = isOutputtingAudio
            var duration: Double = 0
            var position: Double = 0
            var parsed = cleanTabTitle(target.title, siteName: siteName)
            var artworkURL: String? = nil

            if let jsRaw = executeTabJS(browser: browser, windowIndex: target.windowIndex, tabIndex: target.tabIndex, js: mediaProbeJS),
               jsRaw != "no-media" {
                let fields = jsRaw.components(separatedBy: "|~|")
                if fields.count >= 6 {
                    let domPlaying = fields[0] == "1"
                    // Si CoreAudio o el DOM reportan reproducción activa
                    playing = domPlaying || isOutputtingAudio
                    position = Double(fields[1]) ?? 0
                    duration = Double(fields[2]) ?? 0
                    let msTitle = fields[3].trimmingCharacters(in: .whitespacesAndNewlines)
                    let msArtist = fields[4].trimmingCharacters(in: .whitespacesAndNewlines)
                    let msArt = fields[5].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !msTitle.isEmpty { parsed.title = msTitle }
                    if !msArtist.isEmpty { parsed.artist = msArtist }
                    if !msArt.isEmpty { artworkURL = msArt }
                }
            } else {
                jsMissing = true
            }

            // Enriquecimiento automático para YouTube sin requerir JS (miniatura HD + canal vía oEmbed)
            if let ytID = extractYouTubeID(from: target.url) {
                if artworkURL == nil {
                    artworkURL = "https://i.ytimg.com/vi/\(ytID)/hqdefault.jpg"
                }
                let meta = fetchYouTubeMeta(videoID: ytID)
                let genericTitles = ["youtube", "youtube music", ""]
                if genericTitles.contains(parsed.title.lowercased()), let realTitle = meta.title {
                    parsed.title = realTitle
                }
                if parsed.artist.isEmpty || parsed.artist == siteName || parsed.artist == browser.shortName {
                    if let author = meta.author {
                        parsed.artist = author
                    }
                }
            }

            // Si es una pestaña que NO es de música/video dedicada y tampoco está sonando, no ensuciar el notch
            if !playing && siteName == nil {
                return nil
            }
            // En Spotify Web pausado, el título queda solo "Spotify"
            if parsed.title.isEmpty || (siteName == "Spotify" && parsed.title == "Spotify" && !playing) {
                return nil
            }

            let sourceLabel = siteName != nil ? "\(siteName!) · \(browser.shortName)" : browser.shortName
            let artistLabel = parsed.artist.isEmpty ? (siteName ?? browser.shortName) : parsed.artist

            let np = NowPlaying(
                sourceLabel: sourceLabel,
                bundleID: browser.bundleID,
                title: parsed.title,
                artist: artistLabel,
                isPlaying: playing,
                duration: duration,
                position: position,
                isWeb: true,
                artworkURL: artworkURL,
                webBrowserApp: browser.appName,
                webWindowIndex: target.windowIndex,
                webTabIndex: target.tabIndex,
                webTabURL: target.url
            )
            return BrowserMediaResult(nowPlaying: np, jsPermissionMissing: jsMissing)
        }
    }

    nonisolated private static func listTabs(for browser: BrowserSpec) -> [RawTab] {
        let script: String
        switch browser.kind {
        case .chromium:
            script = """
            tell application "\(browser.appName)"
                set out to ""
                set wIdx to 0
                repeat with w in windows
                    set wIdx to wIdx + 1
                    set actIdx to active tab index of w
                    set tIdx to 0
                    repeat with t in tabs of w
                        set tIdx to tIdx + 1
                        set isAct to "0"
                        if tIdx is actIdx then set isAct to "1"
                        set out to out & wIdx & "|^|" & tIdx & "|^|" & isAct & "|^|" & (title of t) & "|^|" & (URL of t) & "\\n"
                    end repeat
                end repeat
                return out
            end tell
            """
        case .safari:
            script = """
            tell application "Safari"
                set out to ""
                set wIdx to 0
                repeat with w in windows
                    set wIdx to wIdx + 1
                    try
                        set curTab to current tab of w
                    on error
                        set curTab to missing value
                    end try
                    set tIdx to 0
                    repeat with t in tabs of w
                        set tIdx to tIdx + 1
                        set isAct to "0"
                        try
                            if t is curTab then set isAct to "1"
                        end try
                        try
                            set tabURL to URL of t
                            set tabTitle to name of t
                            if tabTitle is missing value then set tabTitle to ""
                            if tabURL is not missing value then
                                set out to out & wIdx & "|^|" & tIdx & "|^|" & isAct & "|^|" & tabTitle & "|^|" & tabURL & "\\n"
                            end if
                        end try
                    end repeat
                end repeat
                return out
            end tell
            """
        case .windowTitleOnly:
            return []
        }

        guard let raw = runScript(script), !raw.isEmpty else { return [] }
        var tabs: [RawTab] = []
        for line in raw.components(separatedBy: "\n") where !line.isEmpty {
            let parts = line.components(separatedBy: "|^|")
            guard parts.count >= 5,
                  let wIdx = Int(parts[0]),
                  let tIdx = Int(parts[1]) else { continue }
            tabs.append(
                RawTab(
                    windowIndex: wIdx,
                    tabIndex: tIdx,
                    isActive: parts[2] == "1",
                    title: parts[3],
                    url: parts[4]
                )
            )
        }
        return tabs
    }

    /// Soporte para Zen Browser / Firefox leyendo el título de su ventana cuando emite audio o muestra YouTube.
    nonisolated private static func queryWindowTitleBrowser(
        _ browser: BrowserSpec,
        isOutputtingAudio: Bool
    ) -> BrowserMediaResult? {
        // Solo consultamos System Events si realmente está sonando para no molestar en reposo.
        guard isOutputtingAudio else { return nil }
        let script = """
        tell application "System Events"
            tell process "\(browser.appName)"
                if (count of windows) is 0 then return ""
                return name of window 1
            end tell
        end tell
        """
        guard let rawTitle = runScript(script)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawTitle.isEmpty else { return nil }

        var cleaned = rawTitle
        for suffix in [" — Zen Browser", " - Zen Browser", " — Zen", " — Mozilla Firefox", " - Mozilla Firefox"] {
            if cleaned.hasSuffix(suffix) {
                cleaned = String(cleaned.dropLast(suffix.count))
            }
        }
        let site: String? = cleaned.contains("YouTube") ? "YouTube" : nil
        let parsed = cleanTabTitle(cleaned, siteName: site)
        let label = site != nil ? "\(site!) · \(browser.shortName)" : browser.shortName
        let np = NowPlaying(
            sourceLabel: label,
            bundleID: browser.bundleID,
            title: parsed.title.isEmpty ? cleaned : parsed.title,
            artist: parsed.artist.isEmpty ? browser.shortName : parsed.artist,
            isPlaying: true,
            duration: 0,
            position: 0,
            isWeb: true,
            webBrowserApp: browser.appName
        )
        return BrowserMediaResult(nowPlaying: np, jsPermissionMissing: false)
    }

    private struct MediaSiteInfo {
        let name: String
        let priority: Int
    }

    nonisolated private static func classifyMediaSite(url: String, title: String) -> MediaSiteInfo? {
        let u = url.lowercased()
        if u.contains("music.youtube.com") {
            return MediaSiteInfo(name: "YT Music", priority: 95)
        }
        if u.contains("youtube.com/watch") || u.contains("youtube.com/shorts/") || u.contains("youtube.com/live/") || u.contains("youtu.be/") {
            return MediaSiteInfo(name: "YouTube", priority: 90)
        }
        if u.contains("open.spotify.com") {
            return MediaSiteInfo(name: "Spotify", priority: 92)
        }
        if u.contains("soundcloud.com/") && u != "https://soundcloud.com/" && !u.hasSuffix("soundcloud.com/discover") {
            return MediaSiteInfo(name: "SoundCloud", priority: 85)
        }
        if u.contains("twitch.tv/") && u != "https://www.twitch.tv/" {
            return MediaSiteInfo(name: "Twitch", priority: 84)
        }
        if u.contains("kick.com/") && u != "https://kick.com/" {
            return MediaSiteInfo(name: "Kick", priority: 82)
        }
        if u.contains("music.apple.com") {
            return MediaSiteInfo(name: "Apple Music", priority: 88)
        }
        if u.contains("netflix.com/watch") {
            return MediaSiteInfo(name: "Netflix", priority: 85)
        }
        if u.contains("primevideo.com") && (u.contains("detail") || u.contains("watch")) {
            return MediaSiteInfo(name: "Prime Video", priority: 80)
        }
        if u.contains("disneyplus.com") && u.contains("video") {
            return MediaSiteInfo(name: "Disney+", priority: 80)
        }
        if u.contains("play.max.com/video") {
            return MediaSiteInfo(name: "Max", priority: 80)
        }
        if u.contains("deezer.com") || u.contains("tidal.com") || u.contains("bandcamp.com") {
            return MediaSiteInfo(name: hostLabel(from: u), priority: 80)
        }
        return nil
    }

    nonisolated private static func hostLabel(from urlString: String) -> String {
        guard let host = URL(string: urlString)?.host?.lowercased() else { return "Web" }
        let stripped = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let first = stripped.split(separator: ".").first.map(String.init) ?? stripped
        return first.prefix(1).uppercased() + first.dropFirst()
    }

    nonisolated private static func cleanTabTitle(_ raw: String, siteName: String?) -> (title: String, artist: String) {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Quitar prefijo de notificaciones tipo "(3) Video..." o "🔊 "
        if let regex = try? NSRegularExpression(pattern: #"^(\(\d+\)\s*|🔊\s*|▶\s*)+"#) {
            let range = NSRange(t.startIndex..<t.endIndex, in: t)
            t = regex.stringByReplacingMatches(in: t, range: range, withTemplate: "")
        }

        let suffixes = [
            " - YouTube Music",
            " - YouTube",
            " - Twitch",
            " | Kick",
            " - SoundCloud",
            " | Spotify",
        ]
        for suffix in suffixes where t.hasSuffix(suffix) {
            t = String(t.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
        }

        // Spotify Web usa "Canción • Artista"
        if siteName == "Spotify", t.contains(" • ") {
            let parts = t.components(separatedBy: " • ")
            return (parts[0].trimmingCharacters(in: .whitespaces), parts.dropFirst().joined(separator: " • "))
        }
        // SoundCloud usa "Track by Artist" o "Artist - Track"
        if siteName == "SoundCloud", let range = t.range(of: " by ", options: .backwards) {
            let track = String(t[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let artist = String(t[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            return (track, artist)
        }
        return (t, siteName ?? "")
    }

    nonisolated private static func extractYouTubeID(from urlString: String) -> String? {
        guard let url = URL(string: urlString) else { return nil }
        let host = (url.host ?? "").lowercased()
        if host.contains("youtu.be") {
            let id = url.pathComponents.dropFirst().first ?? ""
            return id.isEmpty ? nil : id
        }
        if host.contains("youtube.com") {
            if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let v = comps.queryItems?.first(where: { $0.name == "v" })?.value, !v.isEmpty {
                return v
            }
            let parts = url.pathComponents
            if let idx = parts.firstIndex(where: { $0 == "shorts" || $0 == "live" }),
               idx + 1 < parts.count {
                return parts[idx + 1]
            }
        }
        return nil
    }

    /// Obtiene título real y canal de un video de YouTube vía oEmbed público (con caché).
    nonisolated private static func fetchYouTubeMeta(videoID: String) -> (author: String?, title: String?) {
        let key = videoID as NSString
        if let cached = ytMetaCache.object(forKey: key) {
            let a = cached["author"] as? String ?? ""
            let t = cached["title"] as? String ?? ""
            return (a.isEmpty ? nil : a, t.isEmpty ? nil : t)
        }
        guard let oembedURL = URL(string: "https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=\(videoID)&format=json") else {
            return (nil, nil)
        }
        var request = URLRequest(url: oembedURL)
        request.timeoutInterval = 2.0
        let sem = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var authorResult: String?
        nonisolated(unsafe) var titleResult: String?
        URLSession.shared.dataTask(with: request) { data, _, _ in
            defer { sem.signal() }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            authorResult = json["author_name"] as? String
            titleResult = json["title"] as? String
        }.resume()
        _ = sem.wait(timeout: .now() + 2.0)
        ytMetaCache.setObject(
            ["author": authorResult ?? "", "title": titleResult ?? ""] as NSDictionary,
            forKey: key
        )
        return (authorResult, titleResult)
    }

    // MARK: - Browser JS Probe & Execution

    /// Lee cualquier elemento `<video>` o `<audio>` + `navigator.mediaSession.metadata` en la pestaña.
    nonisolated private static var mediaProbeJS: String {
        """
        (function(){
          var els = Array.from(document.querySelectorAll('video,audio'));
          var m = els.find(function(e){ return !e.paused && !e.ended; }) || els.sort(function(a,b){ return (b.duration||0)-(a.duration||0); })[0];
          var ms = navigator.mediaSession && navigator.mediaSession.metadata;
          if (!m && !ms) return 'no-media';
          var playing = (m && !m.paused && !m.ended) ? '1' : '0';
          var pos = (m && isFinite(m.currentTime)) ? m.currentTime : 0;
          var dur = (m && isFinite(m.duration) && m.duration > 0) ? m.duration : 0;
          var title = ms && ms.title ? ms.title : '';
          var artist = ms && ms.artist ? ms.artist : '';
          var art = (ms && ms.artwork && ms.artwork.length) ? ms.artwork[ms.artwork.length-1].src : '';
          return [playing, pos, dur, title, artist, art].join('|~|');
        })()
        """
    }

    nonisolated private static func executeTabJS(
        browser: BrowserSpec,
        windowIndex: Int,
        tabIndex: Int,
        js: String
    ) -> String? {
        let escaped = js
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")

        let script: String
        switch browser.kind {
        case .chromium:
            script = """
            tell application "\(browser.appName)"
                if (count of windows) < \(windowIndex) then return ""
                set w to window \(windowIndex)
                if (count of tabs of w) < \(tabIndex) then return ""
                return execute (tab \(tabIndex) of w) javascript "\(escaped)"
            end tell
            """
        case .safari:
            script = """
            tell application "Safari"
                if (count of windows) < \(windowIndex) then return ""
                set w to window \(windowIndex)
                if (count of tabs of w) < \(tabIndex) then return ""
                return do JavaScript "\(escaped)" in (tab \(tabIndex) of w)
            end tell
            """
        case .windowTitleOnly:
            return nil
        }
        guard let out = runScript(script), !out.isEmpty else { return nil }
        return out
    }

    // MARK: - Artwork Loading

    private func refreshArtworkIfNeeded(for playing: NowPlaying?) {
        guard let playing else {
            artwork = nil
            lastArtworkKey = ""
            return
        }
        guard playing.trackKey != lastArtworkKey else { return }
        lastArtworkKey = playing.trackKey
        let key = playing.trackKey

        if let cached = artworkCache.object(forKey: key as NSString) {
            artwork = cached
            return
        }

        // 1. Si tenemos URL de imagen (Spotify, YouTube thumbnail, MediaSession artwork)
        if let raw = playing.artworkURL, let url = URL(string: raw) {
            let fallbackIcon = appIcon(for: playing.bundleID)
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                let loaded = data.flatMap { NSImage(data: $0) }
                Task { @MainActor in
                    guard let self else { return }
                    let finalImage = loaded ?? fallbackIcon
                    if let finalImage {
                        self.artworkCache.setObject(finalImage, forKey: key as NSString)
                    }
                    guard self.lastArtworkKey == key else { return }
                    self.artwork = finalImage
                }
            }.resume()
            return
        }

        // 2. Apple Music nativo
        if playing.bundleID == Self.musicBundleID && !playing.isWeb {
            scriptQueue.async { [weak self] in
                let descriptor = Self.runScriptDescriptor(
                    """
                    tell application "Music"
                        try
                            return data of artwork 1 of current track
                        on error
                            return ""
                        end try
                    end tell
                    """
                )
                let img: NSImage?
                if let data = descriptor?.data, data.count > 32, let decoded = NSImage(data: data) {
                    img = decoded
                } else {
                    img = nil
                }
                Task { @MainActor in
                    guard let self else { return }
                    let finalImg = img ?? self.appIcon(for: playing.bundleID)
                    if let finalImg {
                        self.artworkCache.setObject(finalImg, forKey: key as NSString)
                    }
                    guard self.lastArtworkKey == key else { return }
                    self.artwork = finalImg
                }
            }
            return
        }

        // 3. Fallback: ícono real de la aplicación o navegador que está sonando
        let icon = appIcon(for: playing.bundleID)
        if let icon {
            artworkCache.setObject(icon, forKey: key as NSString)
        }
        artwork = icon
    }

    private func appIcon(for bundleID: String?) -> NSImage? {
        guard let bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    // MARK: - Playback & Focus Controls

    private enum Playback {
        case playPause, next, previous

        var appleScriptCommand: String {
            switch self {
            case .playPause: return "playpause"
            case .next: return "next track"
            case .previous: return "previous track"
            }
        }

        var mediaRemoteCommand: UInt32 {
            switch self {
            case .playPause: return 2 // kMRTogglePlayPause
            case .next: return 4      // kMRNextTrack
            case .previous: return 5  // kMRPreviousTrack
            }
        }

        var mediaKey: Int32 {
            switch self {
            case .playPause: return 16
            case .next: return 17
            case .previous: return 18
            }
        }
    }

    func playPause() { control(.playPause) }
    func nextTrack() { control(.next) }
    func previousTrack() { control(.previous) }

    /// Envía comandos multimedia directos al daemon del sistema vía MediaRemote.framework.
    /// No requiere permisos de Accesibilidad ni habilitar JavaScript en Safari/Brave.
    nonisolated private static func sendMediaRemoteCommand(_ command: UInt32) -> Bool {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW),
              let sym = dlsym(handle, "MRMediaRemoteSendCommand") else {
            return false
        }
        typealias SendCmdFn = @convention(c) (UInt32, UnsafeRawPointer?) -> Bool
        let fn = unsafeBitCast(sym, to: SendCmdFn.self)
        return fn(command, nil)
    }

    /// Lleva al frente la aplicación o pestaña exacta que está sonando al tocar la carátula.
    func activateSource() {
        guard let playing = nowPlaying else { return }
        if playing.isWeb,
           let appName = playing.webBrowserApp,
           let wIdx = playing.webWindowIndex,
           let tIdx = playing.webTabIndex,
           let spec = Self.browsers.first(where: { $0.appName == appName }) {
            scriptQueue.async {
                let script: String
                switch spec.kind {
                case .chromium:
                    script = """
                    tell application "\(appName)"
                        if (count of windows) >= \(wIdx) then
                            set active tab index of window \(wIdx) to \(tIdx)
                            set index of window \(wIdx) to 1
                        end if
                        activate
                    end tell
                    """
                case .safari:
                    script = """
                    tell application "Safari"
                        if (count of windows) >= \(wIdx) then
                            set current tab of window \(wIdx) to tab \(tIdx) of window \(wIdx)
                            set index of window \(wIdx) to 1
                        end if
                        activate
                    end tell
                    """
                case .windowTitleOnly:
                    script = "tell application \"\(appName)\" to activate"
                }
                _ = Self.runScript(script)
            }
            return
        }
        if let bid = playing.bundleID,
           let app = NSRunningApplication.runningApplications(withBundleIdentifier: bid).first {
            app.activate()
        }
    }

    func seek(toFraction fraction: Double) {
        guard let playing = nowPlaying, playing.duration > 0 else { return }
        let clamped = min(max(fraction, 0), 1)
        let targetSec = clamped * playing.duration

        if playing.isWeb,
           let appName = playing.webBrowserApp,
           let wIdx = playing.webWindowIndex,
           let tIdx = playing.webTabIndex,
           let spec = Self.browsers.first(where: { $0.appName == appName }) {
            let js = """
            (function(){
              var els = Array.from(document.querySelectorAll('video,audio'));
              var m = els.find(function(e){ return !e.paused; }) || els[0];
              if (m && isFinite(m.duration)) { m.currentTime = \(targetSec); return 'ok'; }
              return 'missing';
            })()
            """
            scriptQueue.async {
                _ = Self.executeTabJS(browser: spec, windowIndex: wIdx, tabIndex: tIdx, js: js)
            }
        } else if playing.bundleID == Self.spotifyBundleID || playing.bundleID == Self.musicBundleID {
            let app = playing.bundleID == Self.spotifyBundleID ? "Spotify" : "Music"
            let position = Int(targetSec)
            scriptQueue.async {
                _ = Self.runScript("tell application \"\(app)\" to set player position to \(position)")
            }
        }
        seekGeneration += 1
        lastSeek = (playing.trackKey, targetSec, seekGeneration)
        nowPlaying?.position = targetSec
    }

    private func control(_ playback: Playback) {
        guard let playing = nowPlaying else {
            if !Self.sendMediaRemoteCommand(playback.mediaRemoteCommand) {
                Self.postMediaKey(playback.mediaKey)
            }
            return
        }

        if playback == .playPause {
            let newState = !playing.isPlaying
            nowPlaying?.isPlaying = newState
            manualPlayStateOverride = (newState, Date().addingTimeInterval(1.1))
        }

        if playing.isWeb {
            let previousURLFromHistory: String? = (playback == .previous) ? youtubeHistoryStack.popLast() : nil
            let recentIDs = visitedYouTubeIDs
            scriptQueue.async {
                var handled = false
                if let appName = playing.webBrowserApp,
                   let wIdx = playing.webWindowIndex,
                   let tIdx = playing.webTabIndex,
                   let spec = Self.browsers.first(where: { $0.appName == appName }) {
                    // 1. Intentar control directo por JS si está habilitado en el navegador
                    let js = Self.webControlJS(for: playback)
                    if Self.executeTabJS(browser: spec, windowIndex: wIdx, tabIndex: tIdx, js: js) == "ok" {
                        handled = true
                    }

                    // 2. Si JS está desactivado y es Siguiente/Anterior en YouTube, navegar la pestaña por URL via AppleScript
                    if !handled, playback != .playPause,
                       let tabURL = playing.webTabURL,
                       let currentYTID = Self.extractYouTubeID(from: tabURL) {
                        if playback == .next {
                            if let nextID = Self.resolveNextYouTubeVideoID(
                                currentVideoID: currentYTID,
                                browser: spec,
                                windowIndex: wIdx,
                                tabIndex: tIdx,
                                excluding: recentIDs
                            ) {
                                let nextURL = "https://www.youtube.com/watch?v=\(nextID)"
                                handled = Self.navigateBrowserTab(
                                    browser: spec,
                                    windowIndex: wIdx,
                                    tabIndex: tIdx,
                                    toURL: nextURL
                                )
                            }
                        } else if playback == .previous {
                            if let prevURL = previousURLFromHistory {
                                handled = Self.navigateBrowserTab(
                                    browser: spec,
                                    windowIndex: wIdx,
                                    tabIndex: tIdx,
                                    toURL: prevURL
                                )
                            } else if spec.kind == .chromium {
                                let backScript = """
                                tell application "\(spec.appName)"
                                    if (count of windows) >= \(wIdx) then
                                        set w to window \(wIdx)
                                        if (count of tabs of w) >= \(tIdx) then
                                            go back (tab \(tIdx) of w)
                                            return "ok"
                                        end if
                                    end if
                                end tell
                                """
                                handled = (Self.runScript(backScript) == "ok")
                            }
                        }
                    }
                }

                // 3. Para Play/Pause (o sitios con MediaSession como YT Music / Spotify Web), usar MediaRemote del sistema
                if !handled {
                    if !Self.sendMediaRemoteCommand(playback.mediaRemoteCommand) {
                        Self.postMediaKey(playback.mediaKey)
                    }
                }

                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 450_000_000)
                    self?.poll()
                }
            }
            return
        }

        if playing.bundleID == Self.spotifyBundleID || playing.bundleID == Self.musicBundleID {
            let app = playing.bundleID == Self.spotifyBundleID ? "Spotify" : "Music"
            scriptQueue.async { [weak self] in
                _ = Self.runScript("tell application \"\(app)\" to \(playback.appleScriptCommand)")
                Task { @MainActor in self?.poll() }
            }
            return
        }

        // Otras apps nativas con audio → MediaRemote del sistema
        if !Self.sendMediaRemoteCommand(playback.mediaRemoteCommand) {
            Self.postMediaKey(playback.mediaKey)
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            self?.poll()
        }
    }

    /// Cambia la URL de una pestaña en Safari o navegadores Chromium vía AppleScript (no requiere permiso de JavaScript).
    nonisolated private static func navigateBrowserTab(
        browser: BrowserSpec,
        windowIndex: Int,
        tabIndex: Int,
        toURL urlString: String
    ) -> Bool {
        let script: String
        switch browser.kind {
        case .safari:
            script = """
            tell application "Safari"
                if (count of windows) < \(windowIndex) then return ""
                set w to window \(windowIndex)
                if (count of tabs of w) < \(tabIndex) then return ""
                set URL of (tab \(tabIndex) of w) to "\(urlString)"
                return "ok"
            end tell
            """
        case .chromium:
            script = """
            tell application "\(browser.appName)"
                if (count of windows) < \(windowIndex) then return ""
                set w to window \(windowIndex)
                if (count of tabs of w) < \(tabIndex) then return ""
                set URL of (tab \(tabIndex) of w) to "\(urlString)"
                return "ok"
            end tell
            """
        case .windowTitleOnly:
            return false
        }
        return runScript(script) == "ok"
    }

    /// Obtiene el ID del siguiente video recomendado/autoplay de YouTube para poder avanzar sin JavaScript de Apple Events.
    nonisolated private static func resolveNextYouTubeVideoID(
        currentVideoID: String,
        browser: BrowserSpec,
        windowIndex: Int,
        tabIndex: Int,
        excluding visited: [String]
    ) -> String? {
        // 1. En Safari podemos leer el HTML ya cargado en la pestaña con `source of tab` sin hacer request de red
        if browser.kind == .safari {
            let sourceScript = """
            tell application "Safari"
                if (count of windows) < \(windowIndex) then return ""
                set w to window \(windowIndex)
                if (count of tabs of w) < \(tabIndex) then return ""
                return source of (tab \(tabIndex) of w)
            end tell
            """
            if let html = runScript(sourceScript), !html.isEmpty,
               let nextID = extractUpNextIDFromYouTubeHTML(html, currentID: currentVideoID, excluding: visited) {
                return nextID
            }
        }

        // 2. Fallback universal: consultar el HTML de la página del video actual vía URLSession
        guard let url = URL(string: "https://www.youtube.com/watch?v=\(currentVideoID)") else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 3.0
        req.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        let sem = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var htmlResult: String?
        URLSession.shared.dataTask(with: req) { data, _, _ in
            defer { sem.signal() }
            guard let data else { return }
            htmlResult = String(data: data, encoding: .utf8)
        }.resume()
        _ = sem.wait(timeout: .now() + 3.2)

        guard let html = htmlResult else { return nil }
        return extractUpNextIDFromYouTubeHTML(html, currentID: currentVideoID, excluding: visited)
    }

    nonisolated private static func extractUpNextIDFromYouTubeHTML(
        _ html: String,
        currentID: String,
        excluding visited: [String]
    ) -> String? {
        let excluded = Set(visited + [currentID])
        // Primero buscamos el video oficial de Autoplay ("autoplayVideo" -> "watchEndpoint" -> "videoId")
        let patterns = [
            #""autoplayVideo":\{[^{}]*(?:\{[^{}]*\}[^{}]*)*"watchEndpoint":\{"videoId":"([a-zA-Z0-9_-]{11})""#,
            #""compactVideoRenderer":\{"videoId":"([a-zA-Z0-9_-]{11})""#,
            #""playlistPanelVideoRenderer":\{[^{}]*"videoId":"([a-zA-Z0-9_-]{11})""#,
            #""watchEndpoint":\{"videoId":"([a-zA-Z0-9_-]{11})""#,
        ]

        // Recortar desde "secondaryResults" si existe para priorizar la columna "Siguiente"
        let searchScope: String
        if let secRange = html.range(of: "\"secondaryResults\"") {
            searchScope = String(html[secRange.lowerBound...])
        } else {
            searchScope = html
        }

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let scope = pattern.contains("autoplayVideo") ? html : searchScope
            let nsRange = NSRange(scope.startIndex..<scope.endIndex, in: scope)
            let matches = regex.matches(in: scope, options: [], range: nsRange)
            var firstDifferent: String?
            for match in matches where match.numberOfRanges > 1 {
                if let r = Range(match.range(at: 1), in: scope) {
                    let candidate = String(scope[r])
                    guard candidate != currentID else { continue }
                    if firstDifferent == nil { firstDifferent = candidate }
                    if !excluded.contains(candidate) {
                        return candidate
                    }
                }
            }
            if let firstDifferent { return firstDifferent }
        }
        return nil
    }

    nonisolated private static func webControlJS(for playback: Playback) -> String {
        switch playback {
        case .playPause:
            return """
            (function(){
              var b = document.querySelector('[data-testid="control-button-playpause"], .ytp-play-button, .playControl');
              var els = Array.from(document.querySelectorAll('video,audio'));
              var m = els.find(function(e){ return !e.paused; }) || els[0];
              if (m) { if (m.paused) m.play(); else m.pause(); return 'ok'; }
              if (b) { b.click(); return 'ok'; }
              return 'missing';
            })()
            """
        case .next:
            return """
            (function(){
              var b = Array.from(document.querySelectorAll('[data-testid="control-button-skip-forward"], ytmusic-player-bar .next-button, .ytp-next-button, .skipControl__next')).find(function(e) {
                return !e.disabled && e.getAttribute("aria-disabled") !== "true" && e.getClientRects().length > 0 && getComputedStyle(e).visibility !== "hidden";
              });
              if (b) { b.click(); return 'ok'; }
              return 'missing';
            })()
            """
        case .previous:
            return """
            (function(){
              var b = Array.from(document.querySelectorAll('[data-testid="control-button-skip-back"], ytmusic-player-bar .previous-button, .ytp-prev-button, .skipControl__previous')).find(function(e) {
                return !e.disabled && e.getAttribute("aria-disabled") !== "true" && e.getClientRects().length > 0 && getComputedStyle(e).visibility !== "hidden";
              });
              if (b) { b.click(); return 'ok'; }
              return 'missing';
            })()
            """
        }
    }

    nonisolated private static func postMediaKey(_ key: Int32) {
        for keyDown in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: keyDown ? 0xa00 : 0xb00)
            let data1 = (Int(key) << 16) | ((keyDown ? 0xa : 0xb) << 8)
            guard let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero, modifierFlags: flags,
                timestamp: 0, windowNumber: 0, context: nil,
                subtype: Int16(8), data1: data1, data2: -1
            ), let cgEvent = event.cgEvent else { continue }
            cgEvent.post(tap: CGEventTapLocation.cghidEventTap)
        }
    }

    // MARK: - AppleScript Helpers

    nonisolated private static func split(_ result: String?) -> [String]? {
        guard let result, result != "stopped", !result.isEmpty else { return nil }
        return result.components(separatedBy: "|~|")
    }

    nonisolated(unsafe) private static var sawAutomationDenied = false

    nonisolated private static func runScript(_ source: String) -> String? {
        runScriptDescriptor(source)?.stringValue
    }

    nonisolated private static func runScriptDescriptor(_ source: String) -> NSAppleEventDescriptor? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let descriptor = script.executeAndReturnError(&error)
        if let error {
            if (error[NSAppleScript.errorNumber] as? Int) == -1743 {
                sawAutomationDenied = true
            }
            return nil
        }
        return descriptor
    }
}
