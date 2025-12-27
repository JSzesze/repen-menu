import SwiftUI

/// Renders markdown text with strong visual hierarchy
struct MarkdownView: View {
    let markdown: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(parseLines().enumerated()), id: \.offset) { index, line in
                renderLine(line, isFirst: index == 0)
            }
        }
        .textSelection(.enabled)
    }
    
    private func parseLines() -> [String] {
        markdown.components(separatedBy: "\n").filter { !$0.isEmpty }
    }
    
    @ViewBuilder
    private func renderLine(_ line: String, isFirst: Bool) -> some View {
        Group {
            // H1 - Large title
            if line.hasPrefix("# ") {
                Text(line.dropFirst(2))
                    .font(.system(size: 22, weight: .bold))
                    .padding(.top, isFirst ? 0 : 20)
                    .padding(.bottom, 10)
            }
            // H2 - Section header  
            else if line.hasPrefix("## ") {
                Text(line.dropFirst(3))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
                    .padding(.top, isFirst ? 0 : 16)
                    .padding(.bottom, 8)
            }
            // Checklist items
            else if line.hasPrefix("- [ ] ") {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "square")
                        .foregroundColor(.secondary)
                        .font(.system(size: 13))
                    Text(attributedText(from: String(line.dropFirst(6))))
                        .font(.system(size: 14))
                }
                .padding(.leading, 4)
                .padding(.vertical, 3)
            }
            else if line.hasPrefix("- [x] ") {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "checkmark.square.fill")
                        .foregroundColor(.accentColor)
                        .font(.system(size: 13))
                    Text(attributedText(from: String(line.dropFirst(6))))
                        .font(.system(size: 14))
                        .strikethrough()
                        .foregroundColor(.secondary)
                }
                .padding(.leading, 4)
                .padding(.vertical, 3)
            }
            // Bullet list
            else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("•")
                        .foregroundColor(.accentColor)
                        .font(.system(size: 14, weight: .bold))
                    Text(attributedText(from: String(line.dropFirst(2))))
                        .font(.system(size: 14))
                }
                .padding(.leading, 4)
                .padding(.vertical, 3)
            }
            // Regular paragraph
            else {
                Text(attributedText(from: line))
                    .font(.system(size: 14))
                    .foregroundColor(.primary.opacity(0.85))
                    .padding(.vertical, 4)
                    .lineSpacing(4)
            }
        }
    }
    
    private func attributedText(from text: String) -> AttributedString {
        do {
            return try AttributedString(markdown: text)
        } catch {
            return AttributedString(text)
        }
    }
}
