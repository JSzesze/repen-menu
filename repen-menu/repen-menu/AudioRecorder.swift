import Foundation
import AVFoundation
import SwiftUI
import Combine

enum RecordingSource: String, CaseIterable, Identifiable {
    case mic = "Microphone"
    case system = "System Audio"
    case both = "Mic + System"
    
    var id: String { self.rawValue }
    var icon: String {
        switch self {
        case .mic: return "mic.fill"
        case .system: return "speaker.wave.2.fill"
        case .both: return "person.wave.2.fill"
        }
    }
}

@MainActor
final class AudioRecorder: ObservableObject {
    static let shared = AudioRecorder()
    
    @Published var isRecording: Bool = false
    @Published var statusMessage: String?
    @Published var lastTranscript: String?
    @Published var audioLevel: Double = 0.0
    @Published var elapsedSeconds: Double = 0.0
    @Published var recordedURLs: [URL] = []
    @Published var recordingSource: RecordingSource = .mic
    @Published var currentRecordingURL: URL?  // Final destination path for active recording

    private var startDate: Date?
    private var timerCancellable: AnyCancellable?
    
    // Mic Engine
    private let engine = AVAudioEngine()
    
    // System Tap (Modular Component)
    private let systemTap = SystemAudioTap()
    
    private var audioFile: AVAudioFile?
    private var fileURL: URL?
    private let writeQueue = DispatchQueue(label: "AudioRecorder.write", qos: .userInitiated)

    init() {
        refreshRecordings()
    }

    func requestPermissions() async -> Bool {
        // Microphone permission
        let mic = await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
        
        // Note: System Audio (Taps) will prompt automatically on first capture.
        return mic
    }

    func startRecording() async {
        guard !isRecording else { return }

        let granted = await requestPermissions()
        guard granted else {
            statusMessage = "Microphone access denied."
            return
        }

        do {
            // Create temp file for recording
            let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            let name = "recording-\(UUID().uuidString).wav"
            let url = tmp.appendingPathComponent(name)
            fileURL = url
            
            // Generate final destination path and create notes file immediately
            let finalURL = try createRecordingEntry()
            currentRecordingURL = finalURL
            refreshRecordings()
            
            if recordingSource == .mic {
                // High Quality Format: 48kHz, 2CH, 32-bit Float
                let settings: [String: Any] = [
                    AVFormatIDKey: Int(kAudioFormatLinearPCM),
                    AVSampleRateKey: 48000.0,
                    AVNumberOfChannelsKey: 2,
                    AVLinearPCMBitDepthKey: 32,
                    AVLinearPCMIsFloatKey: true,
                    AVLinearPCMIsBigEndianKey: false
                ]
                audioFile = try AVAudioFile(forWriting: url, settings: settings)
                let writeFormat = audioFile!.processingFormat
                try startMicRecording(format: writeFormat)
            } else if recordingSource == .system {
                // Start tap first to get its format
                try await systemTap.start { [weak self] buffer in
                    self?.processAudioBuffer(buffer)
                }
                
                // Wait a moment for the first buffer to arrive and set the format
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                
                // Now create file with the tap's actual format
                guard let tapFormat = systemTap.format else {
                    throw NSError(domain: "AudioRecorder", code: -1, userInfo: [NSLocalizedDescriptionKey: "Tap format not available"])
                }
                
                let settings: [String: Any] = [
                    AVFormatIDKey: Int(kAudioFormatLinearPCM),
                    AVSampleRateKey: tapFormat.sampleRate,
                    AVNumberOfChannelsKey: tapFormat.channelCount,
                    AVLinearPCMBitDepthKey: 32,
                    AVLinearPCMIsFloatKey: true,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: !tapFormat.isInterleaved
                ]
                audioFile = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: tapFormat.isInterleaved)
            } else {
                // .both - Start both mic and system tap
                try await startBothRecording(fileURL: url)
            }

            startDate = Date()
            startTimer()
            isRecording = true
            statusMessage = "Recording \(recordingSource.rawValue)…"
        } catch {
            statusMessage = "Failed to start: \(error.localizedDescription)"
        }
    }

    private func startMicRecording(format: AVAudioFormat) throws {
        if engine.isRunning { engine.stop() }
        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)
        
        let mixer = AVAudioMixerNode()
        engine.attach(mixer)
        engine.connect(input, to: mixer, format: inputFormat)
        
        // DO NOT connect mixer to mainMixerNode to avoid feedback Loop
        
        mixer.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }
        
        engine.prepare()
        try engine.start()
    }
    
    private func startBothRecording(fileURL url: URL) async throws {
        // Use 48kHz stereo non-interleaved format for mixing
        let mixFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 2, interleaved: false)!
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 48000.0,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: true
        ]
        audioFile = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        
        // Start mic engine with tap
        if engine.isRunning { engine.stop() }
        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)
        
        let mixer = AVAudioMixerNode()
        engine.attach(mixer)
        engine.connect(input, to: mixer, format: inputFormat)
        
        // Mic tap - write mic audio directly (we'll interleave later if needed)
        mixer.installTap(onBus: 0, bufferSize: 2048, format: mixFormat) { [weak self] buffer, _ in
            self?.processMixedBuffer(buffer, source: .mic)
        }
        
        engine.prepare()
        try engine.start()
        
        // Start system tap
        try await systemTap.start { [weak self] buffer in
            self?.processMixedBuffer(buffer, source: .system)
        }
    }
    
    private func processMixedBuffer(_ buffer: AVAudioPCMBuffer, source: RecordingSource) {
        guard let file = self.audioFile else { return }
        
        // Calculate Level
        let frameCount = Int(buffer.frameLength)
        var rms: Float = 0
        if frameCount > 0, let data = buffer.floatChannelData?[0] {
            var sum: Float = 0
            for i in 0..<frameCount {
                let sample = data[i]
                sum += sample * sample
            }
            rms = sqrt(sum / Float(frameCount))
        }
        
        // Write to file (both sources write to the same file - they'll be mixed in sequence)
        writeQueue.async {
            do { try file.write(from: buffer) } catch { print("Write error (\(source.rawValue)): \(error)") }
        }
        
        Task { @MainActor in
            let smoothing: Double = 0.4
            let current: Double = 0.6
            self.audioLevel = (self.audioLevel * smoothing) + (Double(rms) * current)
        }
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let file = self.audioFile else { return }
        
        // Calculate Level (quick operation, OK on audio thread)
        let frameCount = Int(buffer.frameLength)
        var rms: Float = 0
        if frameCount > 0, let data = buffer.floatChannelData?[0] {
            var sum: Float = 0
            for i in 0..<frameCount {
                let sample = data[i]
                sum += sample * sample
            }
            rms = sqrt(sum / Float(frameCount))
        }
        
        // Dispatch file write to background queue to avoid blocking audio thread
        writeQueue.async {
            do { try file.write(from: buffer) } catch { print("Write error: \(error)") }
        }

        Task { @MainActor in
            let smoothing: Double = 0.4
            let current: Double = 0.6
            self.audioLevel = (self.audioLevel * smoothing) + (Double(rms) * current)
        }
    }

    func stopRecording() async {
        guard isRecording else { return }
        
        if recordingSource == .mic {
            engine.stop()
        } else if recordingSource == .system {
            systemTap.stop()
        } else {
            // .both - stop both sources
            engine.stop()
            systemTap.stop()
        }
        
        stopTimer()
        isRecording = false
        audioLevel = 0.0
        statusMessage = "Finalizing..."

        guard let tempURL = fileURL, let finalURL = currentRecordingURL else { return }
        audioFile = nil

        do {
            // Move temp audio to the pre-created final destination
            let fm = FileManager.default
            if fm.fileExists(atPath: finalURL.path) {
                try fm.removeItem(at: finalURL)
            }
            try fm.moveItem(at: tempURL, to: finalURL)
            
            currentRecordingURL = nil
            refreshRecordings()
            statusMessage = "Ready"
            
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                self.lastTranscript = "Captured \(recordingSource.rawValue) successfully."
            }
        } catch {
            statusMessage = "Save failed: \(error.localizedDescription)"
            currentRecordingURL = nil
        }
    }

    func refreshRecordings() {
        do {
            let fm = FileManager.default
            let docs = try fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let folder = docs.appendingPathComponent("Repen Menu/Recordings", isDirectory: true)
            
            if fm.fileExists(atPath: folder.path) {
                let allFiles = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles)
                
                // Build set of unique base names (without extension)
                var uniqueBases = Set<URL>()
                for file in allFiles {
                    let base = file.deletingPathExtension()
                    uniqueBases.insert(base)
                }
                
                // Convert bases to .wav URLs (even if .wav doesn't exist yet)
                let urls = uniqueBases.map { $0.appendingPathExtension("wav") }
                
                recordedURLs = urls.sorted { (u1, u2) -> Bool in
                    let d1 = (try? u1.deletingPathExtension().appendingPathExtension("notes").resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                    let d2 = (try? u2.deletingPathExtension().appendingPathExtension("notes").resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                    return d1 > d2
                }
            }
        } catch { print("Refresh error: \(error)") }
    }

    private func startTimer() {
        timerCancellable?.cancel()
        guard let start = startDate else { return }
        timerCancellable = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor in self?.elapsedSeconds = Date().timeIntervalSince(start) }
            }
    }

    private func stopTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }
    
    /// Creates the recording entry (final path + notes file) before recording starts
    private func createRecordingEntry() throws -> URL {
        let fm = FileManager.default
        let docs = try fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let folder = docs.appendingPathComponent("Repen Menu/Recordings", isDirectory: true)
        if !fm.fileExists(atPath: folder.path) {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "Recording_\(formatter.string(from: Date())).wav"
        let audioURL = folder.appendingPathComponent(filename)
        
        // Create empty notes file so entry appears in list
        let notesURL = audioURL.deletingPathExtension().appendingPathExtension("notes")
        try "".write(to: notesURL, atomically: true, encoding: .utf8)
        
        return audioURL
    }

    private func saveToDocuments(tempURL: URL) throws -> URL {
        let fm = FileManager.default
        let docs = try fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let folder = docs.appendingPathComponent("Repen Menu/Recordings", isDirectory: true)
        if !fm.fileExists(atPath: folder.path) {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "Recording_\(formatter.string(from: Date())).wav"
        let dest = folder.appendingPathComponent(filename)
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.moveItem(at: tempURL, to: dest)
        return dest
    }

    var elapsedDisplay: String {
        let s = Int(elapsedSeconds.rounded())
        let m = (s % 3600) / 60
        let sec = s % 60
        return String(format: "%02d:%02d", m, sec)
    }
}
