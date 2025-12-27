import SwiftUI
import AppKit

// MARK: - Floating Formatting Bar

struct FloatingFormattingBar: View {
    @Binding var textView: NSTextView?
    var state: RichTextEditorState
    var onAction: () -> Void
    
    var body: some View {
        HStack(spacing: 2) {
            // Paragraph style selector
            Group {
                // Body text button
                textButton(label: "¶", active: state.headingLevel == nil, help: "Body Text") {
                    textView?.applyBodyStyle()
                }
                // Heading 1
                textButton(label: "H1", active: state.headingLevel == 1, help: "Heading 1") {
                    if state.headingLevel == 1 {
                        textView?.applyBodyStyle()
                    } else {
                        textView?.toggleHeading(level: 1)
                    }
                }
                // Heading 2
                textButton(label: "H2", active: state.headingLevel == 2, help: "Heading 2") {
                    if state.headingLevel == 2 {
                        textView?.applyBodyStyle()
                    } else {
                        textView?.toggleHeading(level: 2)
                    }
                }
            }
            
            divider
            
            // Text formatting
            Group {
                formatButton(icon: "bold", active: state.isBold, help: "Bold ⌘B") {
                    textView?.toggleFontTrait(.boldFontMask)
                }
                formatButton(icon: "italic", active: state.isItalic, help: "Italic ⌘I") {
                    textView?.toggleFontTrait(.italicFontMask)
                }
                formatButton(icon: "underline", active: state.isUnderline, help: "Underline ⌘U") {
                    textView?.toggleUnderline()
                }
            }
            
            divider
            
            // Lists
            Group {
                formatButton(icon: "list.bullet", active: state.listType == NSTextList.MarkerFormat.disc.rawValue, help: "Bullet List") {
                    textView?.toggleList(markerFormat: .disc)
                }
                formatButton(icon: "list.number", active: state.listType == NSTextList.MarkerFormat.decimal.rawValue, help: "Numbered List") {
                    textView?.toggleList(markerFormat: .decimal)
                }
            }
            
            divider
            
            // Writing Tools (accent color)
            Button(action: { textView?.showWritingTools(nil) }) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.accentColor)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Writing Tools")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.12), radius: 16, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }
    
    private var divider: some View {
        Divider()
            .frame(height: 18)
            .padding(.horizontal, 4)
    }
    
    private func formatButton(icon: String, active: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: {
            action()
            onAction()
            textView?.window?.toolbar?.validateVisibleItems()
        }) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(active ? .accentColor : .primary.opacity(0.7))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(active ? Color.accentColor.opacity(0.12) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }
    
    private func textButton(label: String, active: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: {
            action()
            onAction()
            textView?.window?.toolbar?.validateVisibleItems()
        }) {
            Text(label)
                .font(.system(size: 12, weight: active ? .bold : .semibold, design: .rounded))
                .foregroundColor(active ? .accentColor : .primary.opacity(0.7))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(active ? Color.accentColor.opacity(0.12) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - Notes Editor with Floating Bar

struct NotesEditorView: View {
    @Binding var attributedText: NSAttributedString
    @Binding var textView: NSTextView?
    @Binding var state: RichTextEditorState
    @Binding var editorHeight: CGFloat
    var onTextChange: (() -> Void)?
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            RichTextEditorView(
                text: $attributedText,
                textView: $textView,
                state: $state,
                calculatedHeight: $editorHeight,
                onTextChange: onTextChange
            )
            
            if attributedText.string.isEmpty {
                Text("Start typing your notes here...")
                    .font(.system(size: 15))
                    .foregroundColor(Color(NSColor.placeholderTextColor))
                    .allowsHitTesting(false)
                    .padding(.leading, 5)
                    .padding(.top, 8)
            }
        }
    }
}
