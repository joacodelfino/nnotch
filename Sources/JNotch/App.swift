import AppKit

@main
struct JNotchApp {
    @MainActor static var delegate: AppDelegate?
    @MainActor static var appNapToken: NSObjectProtocol?

    @MainActor
    static func main() {
        ProcessInfo.processInfo.disableAutomaticTermination("Utilidad activa permanente en el notch")
        appNapToken = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Mantener actualizados los widgets de JNotch"
        )

        let app = NSApplication.shared
        let appDelegate = AppDelegate()
        delegate = appDelegate
        app.delegate = appDelegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
