import SwiftUI

/// Modern pill-shaped player for document header - play/pause, scrubber, speed
struct MiniPlayerView: View {
    @ObservedObject var player: AudioPlayerController
    
    var body: some View {
        VStack(spacing: 8) {
            // Scrubber Row
            HStack(spacing: 8) {
                Text(player.currentTimeDisplay)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundColor(.secondary)
                    .frame(width: 40, alignment: .trailing)
                
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.1))
                            .frame(height: 4)
                        
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: max(0, geo.size.width * player.progress), height: 4)
                    }
                    .frame(height: 12) // Touch target
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let p = min(max(0, value.location.x / geo.size.width), 1)
                                player.seek(to: p)
                            }
                    )
                }
                .frame(height: 12)
                
                Text(player.remainingTimeDisplay)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundColor(.secondary)
                    .frame(width: 40, alignment: .leading)
            }
            .padding(.horizontal, 4)
            
            // Controls Row
            HStack(spacing: 24) {
                // Speed
                Menu {
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                        Button {
                            player.setSpeed(Float(speed))
                        } label: {
                            if abs(player.playbackSpeed - Float(speed)) < 0.01 {
                                Label("\(speed, specifier: "%.2g")x", systemImage: "checkmark")
                            } else {
                                Text("\(speed, specifier: "%.2g")x")
                            }
                        }
                    }
                } label: {
                    Text("\(player.playbackSpeed, specifier: "%.2g")x")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .foregroundColor(.secondary)
                
                Spacer()
                
                // Skip Back
                Button(action: { player.skip(by: -15) }) {
                    Image(systemName: "gobackward.15")
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                
                // Play/Pause
                Button(action: player.togglePlayPause) {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                
                // Skip Forward
                Button(action: { player.skip(by: 15) }) {
                    Image(systemName: "goforward.15")
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                
                Spacer()
                
                // Placeholder for symmetry (could be volume or empty)
                Color.clear
                    .frame(width: 40, height: 20)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.primary.opacity(0.08)),
            alignment: .top
        )
    }
    }
