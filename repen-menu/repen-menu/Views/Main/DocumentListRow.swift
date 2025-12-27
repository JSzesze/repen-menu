import SwiftUI

/// A single row in the document list sidebar
struct DocumentListRow: View {
    let document: Document
    var isRecording: Bool = false
    
    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }
    
    var body: some View {
        HStack(spacing: 10) {
            // Icon based on content
            if isRecording {
                Image(systemName: "record.circle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.red)
                    .symbolEffect(.pulse)
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: document.hasRecording ? "waveform" : "doc.text")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.accentColor)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.accentColor.opacity(0.12))
                    )
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(document.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    if isRecording {
                        Text("Recording...")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.red)
                    } else {
                        Text(dateFormatter.string(from: document.modifiedAt))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    if document.hasTranscript {
                        Image(systemName: "text.bubble.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.green)
                    }
                    
                    if document.hasSummary {
                        Image(systemName: "sparkles")
                            .font(.system(size: 9))
                            .foregroundColor(.purple)
                    }
                }
            }
        }
    }
}
