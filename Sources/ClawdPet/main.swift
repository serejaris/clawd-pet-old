import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: PetWindow?
    var petView: PetView?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Desktop companion mode (no Dock icon, stays floating across spaces)
        NSApp.setActivationPolicy(.accessory)

        let config = PetConfig.load()
        _ = AssetManager.shared

        let windowWidth: CGFloat = 280.0
        let windowHeight: CGFloat = 280.0

        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            fatalError("No display screen found")
        }

        let visible = screen.visibleFrame
        let initialX = visible.midX - windowWidth / 2.0
        let initialY = visible.minY - 60.0 // 60.0 is crabBottomMargin

        let windowRect = NSRect(x: initialX, y: initialY, width: windowWidth, height: windowHeight)
        let petWin = PetWindow(contentRect: windowRect)

        let view = PetView(frame: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight), config: config)
        view.currentX = initialX
        view.currentY = initialY

        petWin.contentView = view
        petWin.makeKeyAndOrderFront(nil)
        petWin.orderFrontRegardless()

        self.window = petWin
        self.petView = view
    }

    func applicationWillTerminate(_ notification: Notification) {
        petView?.statusBubble.stopMonitoring()
    }
}

// Trap SIGINT and SIGTERM for graceful exit
signal(SIGINT) { _ in
    DispatchQueue.main.async {
        NSApp.terminate(nil)
    }
}
signal(SIGTERM) { _ in
    DispatchQueue.main.async {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
