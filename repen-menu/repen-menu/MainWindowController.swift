import SwiftUI
import AppKit

final class MainWindowController {
    static let shared = MainWindowController()
    
    private var window: NSWindow?
    
    private init() {}
    
    func showWindow() {
        if window == nil {
            let hostingController = NSHostingController(rootView: MainWindowView())
            
            let win = NSWindow(contentViewController: hostingController)
            win.title = ""
            win.setContentSize(NSSize(width: 900, height: 600))
            win.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            win.titlebarAppearsTransparent = true
            win.titleVisibility = .hidden
            win.isReleasedWhenClosed = false
            
            // Ensure the window uses the unified toolbar style for modern macOS look
            // We rely on SwiftUI to populate the toolbar content natively
            win.toolbarStyle = .unified
            
            self.window = win
        }
        
        guard let window = self.window else { return }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
