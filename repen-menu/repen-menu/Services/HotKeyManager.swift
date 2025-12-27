import Cocoa
import SwiftUI

class HotKeyManager {
    static let shared = HotKeyManager()
    
    private var localMonitor: Any?
    private var globalMonitor: Any?
    
    private init() {}
    
    func start() {
        // Local Monitor (When app is active)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.isHotKey(event) == true {
                self?.handleHotKey()
                return nil // Consume event
            }
            return event
        }
        
        // Global Monitor (When app is background)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.isHotKey(event) == true {
                self?.handleHotKey()
            }
        }
    }
    
    private func isHotKey(_ event: NSEvent) -> Bool {
        // Check for Option + Command + R
        // 15 is the key code for 'R'
        return event.modifierFlags.contains([.command, .option]) && event.keyCode == 15
    }
    
    private func handleHotKey() {
        Task { @MainActor in
            await AudioRecorder.shared.toggleRecording()
        }
    }
    
    deinit {
        if let local = localMonitor { NSEvent.removeMonitor(local) }
        if let global = globalMonitor { NSEvent.removeMonitor(global) }
    }
}
