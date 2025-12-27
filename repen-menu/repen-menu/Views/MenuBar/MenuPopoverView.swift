import SwiftUI
import AppKit

struct MenuPopoverView: View {
    @StateObject private var recorder = AudioRecorder.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            
            VStack(spacing: 16) {
                sourcePicker
                recordingControls
            }
            .padding()
            
            footer
        }
        .frame(width: 280)
        .background(VisualEffectView(material: .popover, blendingMode: .withinWindow).ignoresSafeArea())
    }

    private var header: some View {
        HStack {
            Image(systemName: "waveform.circle.fill")
                .font(.title3)
                .foregroundStyle(.blue)
            Text("Repen")
                .font(.headline)
            Spacer()
            if recorder.isRecording {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 6, height: 6)
                    Text(recorder.elapsedDisplay)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color.primary.opacity(0.03))
    }

    private var sourcePicker: some View {
        Picker("Source", selection: $recorder.recordingSource) {
            ForEach(RecordingSource.allCases) { source in
                Label(source.rawValue, systemImage: source.icon)
                    .tag(source)
            }
        }
        .pickerStyle(.menu)
        .disabled(recorder.isRecording)
    }

    private var recordingControls: some View {
        VStack(spacing: 12) {
            if recorder.isRecording {
                AudioVisualizer(amplitude: recorder.audioLevel)
                    .frame(height: 32)

                Button(action: { Task { await recorder.stopRecording() } }) {
                    Label("Stop Recording", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
            } else {
                Button(action: { Task { await recorder.startRecording() } }) {
                    Label("Start Recording", systemImage: "mic.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button(action: { 
                MainWindowController.shared.showWindow()
            }) { 
                Label("Open Repen", systemImage: "rectangle.on.rectangle")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            
            Spacer()
            
            Button("Quit") { 
                NSApplication.shared.terminate(nil) 
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.red.opacity(0.8))
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.03))
    }
}

struct AudioVisualizer: View {
    let amplitude: Double
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<15) { i in
                let sensitivity = 1.0 + sin(Double(i) * 0.5) * 0.2
                let height = CGFloat(amplitude * 150.0 * sensitivity)
                RoundedRectangle(cornerRadius: 2).fill(Color.blue.gradient).frame(width: 4, height: max(CGFloat(4.0), min(CGFloat(40.0), height)))
            }
        }
        .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.6), value: amplitude)
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material; v.blendingMode = blendingMode; v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) { }
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
