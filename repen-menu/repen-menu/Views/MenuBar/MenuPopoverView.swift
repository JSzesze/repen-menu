import SwiftUI
import AppKit

struct MenuPopoverView: View {
    @StateObject private var recorder = AudioRecorder.shared

    var body: some View {
        VStack(spacing: 16) {
            sourcePicker
            recordingControls
        }
        .padding(20)
        .frame(width: 260)
        .background(.ultraThinMaterial)
    }

    private var sourcePicker: some View {
        Menu {
            ForEach(RecordingSource.allCases) { source in
                Button(action: { recorder.recordingSource = source }) {
                    HStack {
                        if recorder.recordingSource == source {
                            Image(systemName: "checkmark")
                        }
                        Text(source.rawValue)
                        Image(systemName: source.icon)
                    }
                }
            }
        } label: {
            HStack {
                Image(systemName: "mic.fill")
                    .foregroundStyle(.secondary)
                Text(recorder.recordingSource.rawValue)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .menuStyle(.borderlessButton)
        .disabled(recorder.isRecording)
    }

    private var recordingControls: some View {
        VStack(spacing: 12) {
            if recorder.isRecording {
                // Recording State
                VStack(spacing: 8) {
                    Text(recorder.elapsedDisplay)
                        .font(.system(.title, design: .monospaced))
                        .fontWeight(.light)
                        .foregroundStyle(.primary)
                    
                    AudioVisualizer(amplitude: recorder.audioLevel)
                        .frame(height: 40)
                        
                    Button(action: { Task { await recorder.stopRecording() } }) {
                        Image(systemName: "stop.fill")
                            .font(.title2)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(Color.red.gradient)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .shadow(color: .red.opacity(0.3), radius: 5, x: 0, y: 3)
                    .shadow(color: .red.opacity(0.3), radius: 5, x: 0, y: 3)
                }
            } else {
                // Idle State
                Button(action: { Task { await recorder.startRecording() } }) {
                    HStack(spacing: 8) {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                        Text("Start Recording")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(Color.primary.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }
}

struct AudioVisualizer: View {
    let amplitude: Double
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<20) { i in
                let sensitivity = 1.0 + sin(Double(i) * 0.4) * 0.3
                let height = CGFloat(amplitude * 120.0 * sensitivity)
                let clampedHeight = max(4.0, min(35.0, height))
                
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.primary.opacity(0.8))
                    .frame(width: 3, height: clampedHeight)
            }
        }
        .frame(height: 40)
        .animation(.interactiveSpring(response: 0.1, dampingFraction: 0.5), value: amplitude)
    }
}

extension URL {
    var creationString: String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: self.path),
              let date = attrs[.creationDate] as? Date else {
            return "Unknown"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
