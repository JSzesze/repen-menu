import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreMedia
import Combine

/// A modular component to handle system audio capture via ScreenCaptureKit.
/// Simpler and more robust than Core Audio Taps.
@MainActor
final class SystemAudioTap: NSObject, ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    
    private var stream: SCStream?
    private var streamOutput: SystemAudioStreamOutput?
    
    private(set) var format: AVAudioFormat?
    private var audioCallback: ((AVAudioPCMBuffer) -> Void)?
    
    private var isRunning = false
    
    override init() {
        super.init()
    }
    
    /// Starts the system audio capture.
    func start(callback: @escaping (AVAudioPCMBuffer) -> Void) async throws {
        guard !isRunning else {
            print("[SystemAudioTap] Already running")
            return
        }
        
        self.audioCallback = callback
        
        // Get available content to capture
        let availableContent = try await SCShareableContent.current
        
        guard let display = availableContent.displays.first else {
            throw SystemAudioError.noDisplaysAvailable
        }
        
        // Create filter for what we want to capture (just need a display for audio)
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        
        // Configure stream settings
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true  // Prevents feedback loop!
        configuration.sampleRate = 48000
        configuration.channelCount = 2
        
        // Create the stream
        stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        
        // Create stream output handler
        streamOutput = SystemAudioStreamOutput { [weak self] sampleBuffer in
            self?.processSampleBuffer(sampleBuffer)
        }
        
        // Add output to stream with dispatch queue
        try stream?.addStreamOutput(
            streamOutput!,
            type: .audio,
            sampleHandlerQueue: DispatchQueue(label: "SystemAudioTap.audio", qos: .userInteractive)
        )
        
        // Start capture
        try await stream?.startCapture()
        isRunning = true
        
        print("[SystemAudioTap] Started via ScreenCaptureKit")
    }
    
    func stop() {
        guard isRunning else { return }
        
        Task {
            try? await stream?.stopCapture()
            stream = nil
            streamOutput = nil
            isRunning = false
            audioCallback = nil
            print("[SystemAudioTap] Stopped")
        }
    }
    
    private func processSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let callback = audioCallback else { return }
        
        // Get format description
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return
        }
        
        // Create AVAudioFormat if we don't have one yet
        if format == nil {
            var streamDesc = asbd.pointee
            format = AVAudioFormat(streamDescription: &streamDesc)
            print("[SystemAudioTap] Format: \(format?.description ?? "unknown")")
        }
        
        guard let audioFormat = format else { return }
        
        // Get the number of frames
        let numFrames = CMSampleBufferGetNumSamples(sampleBuffer)
        guard numFrames > 0 else { return }
        
        // Create PCM buffer with the correct format
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: AVAudioFrameCount(numFrames)) else {
            return
        }
        pcmBuffer.frameLength = AVAudioFrameCount(numFrames)
        
        // First, query the required buffer list size
        var bufferListSizeNeeded: Int = 0
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &bufferListSizeNeeded,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: nil
        )
        
        guard bufferListSizeNeeded > 0 else { return }
        
        // Allocate buffer list with correct size
        let audioBufferListData = UnsafeMutableRawPointer.allocate(byteCount: bufferListSizeNeeded, alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { audioBufferListData.deallocate() }
        let audioBufferListPtr = audioBufferListData.assumingMemoryBound(to: AudioBufferList.self)
        
        var blockBuffer: CMBlockBuffer?
        
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: audioBufferListPtr,
            bufferListSize: bufferListSizeNeeded,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        
        guard status == noErr else {
            print("[SystemAudioTap] Failed to get audio buffer list: \(status)")
            return
        }
        
        // Copy data from AudioBufferList to AVAudioPCMBuffer
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferListPtr)

        if audioFormat.isInterleaved {
            // Interleaved: single buffer with all channels
            if let srcData = buffers[0].mData,
               let destData = pcmBuffer.floatChannelData?[0] {
                let byteCount = Int(buffers[0].mDataByteSize)
                memcpy(destData, srcData, byteCount)
            }
        } else {
            // Non-interleaved: each channel in separate buffer
            for i in 0..<min(Int(audioFormat.channelCount), buffers.count) {
                if let srcData = buffers[i].mData,
                   let destData = pcmBuffer.floatChannelData?[i] {
                    let byteCount = Int(buffers[i].mDataByteSize)
                    memcpy(destData, srcData, byteCount)
                }
            }
        }
        
        callback(pcmBuffer)
    }
    
    enum SystemAudioError: Error, LocalizedError {
        case noDisplaysAvailable
        
        var errorDescription: String? {
            switch self {
            case .noDisplaysAvailable:
                return "No displays available for capture. Please grant Screen Recording permission."
            }
        }
    }
}

// MARK: - Stream Output Handler

private class SystemAudioStreamOutput: NSObject, SCStreamOutput {
    private let handler: (CMSampleBuffer) -> Void
    
    init(handler: @escaping (CMSampleBuffer) -> Void) {
        self.handler = handler
        super.init()
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        handler(sampleBuffer)
    }
}

