import SwiftUI
import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover = NSPopover()
    private var menuBarView: MenuBarRecordingView!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        // Create status item with variable length to accommodate waveform
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            // Create and add custom recording view
            menuBarView = MenuBarRecordingView(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
            menuBarView.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(menuBarView)
            
            NSLayoutConstraint.activate([
                menuBarView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                menuBarView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                menuBarView.topAnchor.constraint(equalTo: button.topAnchor),
                menuBarView.bottomAnchor.constraint(equalTo: button.bottomAnchor)
            ])
            
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 320, height: 450)
        popover.contentViewController = NSHostingController(rootView: MenuPopoverView())
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
