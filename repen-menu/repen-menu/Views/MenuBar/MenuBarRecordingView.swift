import SwiftUI
import AppKit
import Combine

/// A custom view for the menu bar that shows a waveform and timer when recording
final class MenuBarRecordingView: NSView {
    private var audioLevelSubscription: AnyCancellable?
    private var elapsedSubscription: AnyCancellable?
    private var isRecordingSubscription: AnyCancellable?
    
    private var audioLevel: Double = 0
    private var elapsedSeconds: Double = 0
    private var isRecording: Bool = false
    
    private let waveformBarCount = 5
    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 2
    private let maxBarHeight: CGFloat = 14
    private let minBarHeight: CGFloat = 4
    
    override var intrinsicContentSize: NSSize {
        if isRecording {
            // Waveform + spacing + time label width + padding
            let waveformWidth = CGFloat(waveformBarCount) * (barWidth + barSpacing)
            return NSSize(width: waveformWidth + 50, height: 22)
        } else {
            // Just the icon
            return NSSize(width: 28, height: 22) // Increased tap target slightly
        }
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupSubscriptions()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupSubscriptions()
    }
    
    private func setupSubscriptions() {
        // Subscribe to audio level changes
        audioLevelSubscription = AudioRecorder.shared.$audioLevel
            .receive(on: RunLoop.main)
            .sink { [weak self] level in
                self?.audioLevel = level
                if self?.isRecording == true {
                    self?.needsDisplay = true
                }
            }
        
        // Subscribe to elapsed time changes
        elapsedSubscription = AudioRecorder.shared.$elapsedSeconds
            .receive(on: RunLoop.main)
            .sink { [weak self] elapsed in
                self?.elapsedSeconds = elapsed
                if self?.isRecording == true {
                    self?.needsDisplay = true
                }
            }
        
        // Subscribe to recording state
        isRecordingSubscription = AudioRecorder.shared.$isRecording
            .receive(on: RunLoop.main)
            .sink { [weak self] recording in
                self?.isRecording = recording
                self?.invalidateIntrinsicContentSize()
                self?.needsDisplay = true
            }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // Use bounds for consistent positioning
        let rect = self.bounds
        
        if isRecording {
            drawRecordingState(in: rect)
        } else {
            drawIdleState(in: rect)
        }
    }
    
    private func drawIdleState(in rect: NSRect) {
        // Draw mic icon with proper menu bar coloring
        guard let image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Recorder") else { return }
        
        // Create a configuration with the menu bar color (adapts to light/dark)
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.labelColor]))
        
        guard let coloredImage = image.withSymbolConfiguration(config) else { return }
        
        let imageSize: CGFloat = 18
        let imageRect = NSRect(x: (rect.width - imageSize) / 2, 
                               y: (rect.height - imageSize) / 2, 
                               width: imageSize, 
                               height: imageSize)
        coloredImage.draw(in: imageRect)
    }
    
    private func drawRecordingState(in rect: NSRect) {
        // Optional: Draw a subtle background pill
        // NSColor.controlBackgroundColor.withAlphaComponent(0.5).setFill()
        // let bgPath = NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: 4, yRadius: 4)
        // bgPath.fill()

        // Draw recording dot
        NSColor.systemRed.setFill()
        let dotDiameter: CGFloat = 8
        let dotRect = NSRect(x: 4, y: (rect.height - dotDiameter) / 2, width: dotDiameter, height: dotDiameter)
        let dotPath = NSBezierPath(ovalIn: dotRect)
        dotPath.fill()
        
        // Draw waveform bars
        let waveformStartX: CGFloat = 16
        let baseLevel = max(0.02, audioLevel) // Minimum visible level
        
        for i in 0..<waveformBarCount {
            // Vary each bar slightly for visual interest
            let variation = sin(Double(i) * 0.8 + elapsedSeconds * 3) * 0.3 + 0.7
            let height = min(maxBarHeight, max(minBarHeight, CGFloat(baseLevel * 80 * variation)))
            
            let x = waveformStartX + CGFloat(i) * (barWidth + barSpacing)
            let y = (rect.height - height) / 2
            
            let barRect = NSRect(x: x, y: y, width: barWidth, height: height)
            let barPath = NSBezierPath(roundedRect: barRect, xRadius: 1.5, yRadius: 1.5)
            
            NSColor.labelColor.setFill() // Use label color for bars for better visibility, or keep red? User image showed red bars. Let's stick to red or maybe label color is cleaner. User has red dot. Let's make bars red too for now.
            NSColor.systemRed.setFill()
            barPath.fill()
        }
        
        // Draw elapsed time
        let timeString = formatTime(elapsedSeconds)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium), // Increased font size
            .foregroundColor: NSColor.labelColor
        ]
        
        let timeRect = NSRect(x: waveformStartX + CGFloat(waveformBarCount) * (barWidth + barSpacing) + 6,
                              y: (rect.height - 15) / 2, // Adjusted y for larger font
                              width: 40,
                              height: 15)
        timeString.draw(in: timeRect, withAttributes: attributes)
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
