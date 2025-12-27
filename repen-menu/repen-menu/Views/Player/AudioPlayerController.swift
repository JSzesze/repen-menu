import SwiftUI
import AVFoundation
import Combine

// MARK: - Audio Player Controller

@MainActor
class AudioPlayerController: ObservableObject {
    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var playbackSpeed: Float = 1.0
    
    private var player: AVAudioPlayer?
    private var timer: Timer?
    
    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }
    
    var currentTimeDisplay: String {
        formatTime(currentTime)
    }
    
    var durationDisplay: String {
        formatTime(duration)
    }
    
    var remainingTimeDisplay: String {
        formatTime(max(0, duration - currentTime))
    }
    
    func skip(by seconds: Double) {
        guard let player = player else { return }
        let newTime = max(0, min(duration, player.currentTime + seconds))
        player.currentTime = newTime
        currentTime = newTime
    }
    
    func load(url: URL) {
        stop()
        
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
            duration = player?.duration ?? 0
            currentTime = 0
        } catch {
            print("Failed to load audio: \(error)")
        }
    }
    
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    func play() {
        player?.play()
        isPlaying = true
        startTimer()
    }
    
    func pause() {
        player?.pause()
        isPlaying = false
        stopTimer()
    }
    
    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        stopTimer()
        currentTime = 0
    }
    
    func seek(to progress: Double) {
        let newTime = progress * duration
        player?.currentTime = newTime
        currentTime = newTime
    }
    
    func setSpeed(_ speed: Float) {
        playbackSpeed = speed
        player?.rate = speed
        player?.enableRate = true
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let player = self.player else { return }
                self.currentTime = player.currentTime
                
                if !player.isPlaying && self.isPlaying {
                    self.isPlaying = false
                    self.stopTimer()
                }
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func formatTime(_ time: Double) -> String {
        let mins = Int(time) / 60
        let secs = Int(time) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
