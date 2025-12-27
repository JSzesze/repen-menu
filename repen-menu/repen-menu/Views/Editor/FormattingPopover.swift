import SwiftUI
import AppKit

// MARK: - Formatting Popover Content

struct FormattingPopoverView: View {
    @Binding var textView: NSTextView?
    @Binding var state: RichTextEditorState
    var onAction: () -> Void
    var updateState: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Inline formatting row
            inlineFormattingRow
            
            Divider()
                .padding(.vertical, 8)
            
            // Paragraph styles
            paragraphStylesSection
            
            Divider()
                .padding(.vertical, 8)
            
            // Block Quote
            blockQuoteRow
        }
        .padding(12)
        .frame(width: 200)
    }
    
    // MARK: - Helper to perform action while keeping text view focus
    
    private func performAction(_ action: @escaping (NSTextView) -> Void) {
        guard let tv = textView else { return }
        // Make sure the text view is first responder before action
        tv.window?.makeFirstResponder(tv)
        action(tv)
        onAction()
        // Update state immediately and after a short delay
        updateState()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            updateState()
            tv.window?.makeFirstResponder(tv)
        }
    }
    
    // MARK: - Inline Formatting Row
    
    private var inlineFormattingRow: some View {
        HStack(spacing: 4) {
            // Bold
            inlineButton(
                label: "B",
                font: .system(size: 16, weight: .bold),
                active: state.isBold
            ) { tv in
                tv.toggleFontTrait(.boldFontMask)
            }
            
            // Italic
            inlineButton(
                label: "I",
                font: .system(size: 16, weight: .regular).italic(),
                active: state.isItalic
            ) { tv in
                tv.toggleFontTrait(.italicFontMask)
            }
            
            // Underline
            inlineButton(
                label: "U",
                font: .system(size: 16, weight: .regular),
                active: state.isUnderline,
                underline: true
            ) { tv in
                tv.toggleUnderline()
            }
            
            // Strikethrough
            inlineButton(
                label: "S",
                font: .system(size: 16, weight: .regular),
                active: false,
                strikethrough: true
            ) { tv in
                tv.toggleStrikethrough()
            }
        }
    }
    
    private func inlineButton(
        label: String,
        font: Font,
        active: Bool,
        underline: Bool = false,
        strikethrough: Bool = false,
        action: @escaping (NSTextView) -> Void
    ) -> some View {
        Button(action: {
            performAction(action)
        }) {
            Text(label)
                .font(font)
                .underline(underline)
                .strikethrough(strikethrough)
                .frame(width: 32, height: 32)
                .foregroundColor(active ? .white : .primary)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(active ? Color.accentColor : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Paragraph Styles Section
    
    private var paragraphStylesSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            paragraphStyleRow(label: "Title", fontSize: 22, weight: .bold, level: 1)
            paragraphStyleRow(label: "Heading", fontSize: 18, weight: .bold, level: 2)
            paragraphStyleRow(label: "Subheading", fontSize: 15, weight: .semibold, level: 3)
            paragraphStyleRow(label: "Body", fontSize: 15, weight: .regular, level: nil)
            
            Divider()
                .padding(.vertical, 6)
            
            // List styles
            listStyleRow(icon: "•", label: "Bulleted List", markerFormat: .disc)
            listStyleRow(icon: "–", label: "Dashed List", markerFormat: .hyphen)
            listStyleRow(icon: "1.", label: "Numbered List", markerFormat: .decimal)
        }
    }
    
    private func paragraphStyleRow(label: String, fontSize: CGFloat, weight: Font.Weight, level: Int?) -> some View {
        let isActive = state.headingLevel == level
        
        return Button(action: {
            performAction { tv in
                if let level = level {
                    tv.toggleHeading(level: level)
                } else {
                    tv.applyBodyStyle()
                }
            }
        }) {
            HStack {
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.accentColor)
                        .frame(width: 16)
                } else {
                    Spacer()
                        .frame(width: 16)
                }
                
                Text(label)
                    .font(.system(size: fontSize, weight: weight))
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private func listStyleRow(icon: String, label: String, markerFormat: NSTextList.MarkerFormat) -> some View {
        let isActive = state.listType == markerFormat.rawValue
        
        return Button(action: {
            performAction { tv in
                tv.toggleList(markerFormat: markerFormat)
            }
        }) {
            HStack(spacing: 8) {
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.accentColor)
                        .frame(width: 16)
                } else {
                    Spacer()
                        .frame(width: 16)
                }
                
                Text(icon)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .frame(width: 20, alignment: .leading)
                
                Text(label)
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Block Quote
    
    private var blockQuoteRow: some View {
        Button(action: {
            performAction { tv in
                tv.insertBlockQuote()
            }
        }) {
            HStack(spacing: 8) {
                Spacer()
                    .frame(width: 16)
                
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 3, height: 16)
                    .cornerRadius(1.5)
                
                Text("Block Quote")
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - NSTextView Extensions for additional formatting

extension NSTextView {
    func toggleStrikethrough() {
        guard let textStorage = self.textStorage else { return }
        let selection = self.selectedRange()
        
        if selection.length == 0 {
            let current = (self.typingAttributes[.strikethroughStyle] as? Int) ?? 0
            if current == 0 {
                self.typingAttributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            } else {
                self.typingAttributes.removeValue(forKey: .strikethroughStyle)
            }
            return
        }
        
        textStorage.beginEditing()
        textStorage.enumerateAttribute(.strikethroughStyle, in: selection, options: []) { value, range, _ in
            let current = (value as? Int) ?? 0
            if current == 0 {
                textStorage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            } else {
                textStorage.removeAttribute(.strikethroughStyle, range: range)
            }
        }
        textStorage.endEditing()
    }
    
    func insertBlockQuote() {
        guard let textStorage = self.textStorage else { return }
        let selection = self.selectedRange()
        let ranges = blockQuoteParagraphRanges(for: selection, in: textStorage.string as NSString)
        
        textStorage.beginEditing()
        for range in ranges {
            let style = blockQuoteParagraphStyle(for: range, in: textStorage)
            style.headIndent = 24
            style.firstLineHeadIndent = 24
            style.paragraphSpacingBefore = 8
            style.paragraphSpacing = 8
            if range.length > 0 {
                textStorage.addAttribute(.paragraphStyle, value: style, range: range)
                textStorage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
            }
        }
        textStorage.endEditing()
        
        if selection.length == 0 {
            var attributes = self.typingAttributes
            let style = NSMutableParagraphStyle()
            style.headIndent = 24
            style.firstLineHeadIndent = 24
            style.paragraphSpacingBefore = 8
            style.paragraphSpacing = 8
            attributes[.paragraphStyle] = style
            attributes[.foregroundColor] = NSColor.secondaryLabelColor
            self.typingAttributes = attributes
        }
    }
    
    private func blockQuoteParagraphRanges(for selection: NSRange, in text: NSString) -> [NSRange] {
        let safeSelection = selection.location == NSNotFound ? NSRange(location: 0, length: 0) : selection
        if text.length == 0 { return [NSRange(location: 0, length: 0)] }
        if safeSelection.length == 0 { return [text.paragraphRange(for: safeSelection)] }
        
        var ranges: [NSRange] = []
        var searchLocation = safeSelection.location
        let endLocation = safeSelection.location + safeSelection.length
        while searchLocation < endLocation {
            let range = text.paragraphRange(for: NSRange(location: searchLocation, length: 0))
            ranges.append(range)
            let nextLocation = NSMaxRange(range)
            if nextLocation <= searchLocation { break }
            searchLocation = nextLocation
        }
        return ranges
    }
    
    private func blockQuoteParagraphStyle(for range: NSRange, in textStorage: NSTextStorage) -> NSMutableParagraphStyle {
        if range.length == 0 || range.location >= textStorage.length {
            if let typingStyle = self.typingAttributes[.paragraphStyle] as? NSParagraphStyle {
                return (typingStyle.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            }
            return NSMutableParagraphStyle()
        }
        if let existingStyle = textStorage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle {
            return (existingStyle.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        }
        return NSMutableParagraphStyle()
    }
}
