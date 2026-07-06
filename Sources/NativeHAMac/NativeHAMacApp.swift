import AppKit
import SwiftUI

@main
struct NativeHAMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

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

        DispatchQueue.main.async {
            guard let window = NSApp.windows.first else {
                return
            }

            window.title = "NativeHA"
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)

            if let visibleFrame = NSScreen.main?.visibleFrame {
                window.setFrame(visibleFrame, display: true)
            }
        }
    }
}
