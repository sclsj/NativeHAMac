import AppKit
import SwiftUI
import NativeHACore

@main
struct NativeHAMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    #if DEBUG
    init() {
        activeLoggingPolicy = AppConfig.loggingPolicy
        _ = AppLogger.shared
    }
    #endif

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .frame(minWidth: 1200, minHeight: 760)
                .preferredColorScheme(.dark)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        AppLog("Application launched, SQLite logger initialized", category: .lifecycle)

        DispatchQueue.main.async {
            guard let window = NSApp.windows.first else {
                return
            }

            window.title = "NativeHA"
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)

            if let visibleFrame = NSScreen.main?.visibleFrame {
                window.setFrame(visibleFrame, display: true)
                AppLog("Main window configured with visible frame \(visibleFrame)", category: .lifecycle)
            }
        }
    }

    #if DEBUG
    func applicationWillTerminate(_ notification: Notification) {
        AppLog("Application will terminate", category: .lifecycle)
        AppLogger.shared.flushAndWait()
    }
    #endif
}
