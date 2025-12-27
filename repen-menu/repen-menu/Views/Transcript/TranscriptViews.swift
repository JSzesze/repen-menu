import SwiftUI
import AppKit

// MARK: - Transcript Sheet View

struct TranscriptSheetView: View {
    let content: String
    let recordingName: String
    @ObservedObject var player: AudioPlayerController
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Transcript")
                        .font(.headline)
                    Text(recordingName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: copyTranscript) {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Transcript content
            ScrollView {
                TranscriptTextView(content: content)
                    .padding(24)
            }
            
            // Player Footer
            MiniPlayerView(player: player)
        }
        .frame(minWidth: 500, minHeight: 400)
    }
    
    private func copyTranscript() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
    }
}

// MARK: - Transcript Text View

struct TranscriptTextView: View {
    let content: String
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(parseSegments(), id: \.id) { segment in
                VStack(alignment: .leading, spacing: 6) {
                    Text(segment.timestamp)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(4)
                    
                    Text(segment.text)
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                        .lineSpacing(4)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(colorScheme == .dark ? Color(white: 0.15) : Color.white)
                .cornerRadius(10)
            }
        }
    }
    
    private func parseSegments() -> [TranscriptSegmentDisplay] {
        var segments: [TranscriptSegmentDisplay] = []
        let lines = content.components(separatedBy: "\n\n")
        
        var currentTimestamp = ""
        var currentText = ""
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            
            // Check for timestamp pattern **[xx:xx - xx:xx]**
            if trimmed.hasPrefix("**[") && trimmed.contains("]**") {
                // Save previous segment
                if !currentText.isEmpty {
                    segments.append(TranscriptSegmentDisplay(
                        id: UUID(),
                        timestamp: currentTimestamp.isEmpty ? "Full" : currentTimestamp,
                        text: currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                    ))
                }
                
                // Parse new timestamp
                if let range = trimmed.range(of: "\\*\\*\\[(.+?)\\]\\*\\*", options: .regularExpression) {
                    let match = String(trimmed[range])
                    currentTimestamp = match
                        .replacingOccurrences(of: "**[", with: "")
                        .replacingOccurrences(of: "]**", with: "")
                }
                
                // Get text after timestamp
                if let closingRange = trimmed.range(of: "]**") {
                    let afterTimestamp = String(trimmed[closingRange.upperBound...])
                    currentText = afterTimestamp.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } else if !trimmed.hasPrefix("---") && !trimmed.hasPrefix("##") && !trimmed.hasPrefix("- **") && !trimmed.hasPrefix("# ") {
                // Regular text, append to current segment
                if !currentText.isEmpty {
                    currentText += "\n"
                }
                currentText += trimmed
            }
        }
        
        // Add last segment
        if !currentText.isEmpty {
            segments.append(TranscriptSegmentDisplay(
                id: UUID(),
                timestamp: currentTimestamp.isEmpty ? "Full" : currentTimestamp,
                text: currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        }
        
        // If no segments were parsed, show full content
        if segments.isEmpty && !content.isEmpty {
            segments.append(TranscriptSegmentDisplay(
                id: UUID(),
                timestamp: "Full Transcript",
                text: content.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        }
        
        return segments
    }
}

struct TranscriptSegmentDisplay: Identifiable {
    let id: UUID
    let timestamp: String
    let text: String
}
