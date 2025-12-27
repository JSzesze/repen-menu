import SwiftUI
import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover = NSPopover()
    private var menuBarView: MenuBarRecordingView!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register defaults (for first launch)
        UserDefaults.standard.register(defaults: ["showInDock": true])
        
        let showInDock = UserDefaults.standard.bool(forKey: "showInDock")
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
        
        // Start Global Hotkey Manager
        HotKeyManager.shared.start()
        
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
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 260, height: 200) // Updated size estimation
        popover.contentViewController = NSHostingController(rootView: MenuPopoverView())
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        
        let event = NSApp.currentEvent
        
        if event?.type == .rightMouseUp {
            // Show Context Menu
            let menu = NSMenu()
            
            menu.addItem(withTitle: "Open Repen", action: #selector(openMainWindow), keyEquivalent: "")
            menu.addItem(withTitle: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit", action: #selector(quitApp), keyEquivalent: "q")
            
            statusItem.menu = menu // Temporarily attach menu
            statusItem.button?.performClick(nil) // Trigger menu
            statusItem.menu = nil // Detach immediately to keep custom behavior
        } else {
            // Show/Hide Popover
            if popover.isShown {
                popover.performClose(sender)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                popover.contentViewController?.view.window?.makeKey() // Ensure window is key
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
    
    @objc private func openMainWindow() {
        MainWindowController.shared.showWindow()
    }
    
    @objc private func openSettings() {
        // Placeholder for settings
        MainWindowController.shared.showWindow()
        // Ideally navigate to settings tab if it exists
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            MainWindowController.shared.showWindow()
        }
        return true
    }
}
