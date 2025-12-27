import SwiftUI
import AppKit

// MARK: - Custom NSTextView with Keyboard Shortcuts

class FormattingTextView: NSTextView {
    weak var coordinator: RichTextEditorView.Coordinator?
    
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }
        
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "b":
            toggleFontTrait(.boldFontMask)
            coordinator?.updateState()
            return true
        case "i":
            toggleFontTrait(.italicFontMask)
            coordinator?.updateState()
            return true
        case "u":
            toggleUnderline()
            coordinator?.updateState()
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }
}
/// State representing the active formatting at the current selection.
struct RichTextEditorState: Equatable {
    var isBold = false
    var isItalic = false
    var isUnderline = false
    var headingLevel: Int? = nil
    var listType: String? = nil
    var alignment: NSTextAlignment = .left
}

struct RichTextEditorWithToolbar: View {
    @Binding var attributedText: NSAttributedString
    var onTextChange: (() -> Void)?
    @Binding var textView: NSTextView?
    @Binding var state: RichTextEditorState
    @State private var editorHeight: CGFloat = 400
    
    var body: some View {
        RichTextEditorView(
            text: $attributedText,
            textView: $textView,
            state: $state,
            calculatedHeight: $editorHeight,
            onTextChange: onTextChange
        )
        .frame(height: editorHeight)
        .background(Color(NSColor.textBackgroundColor))
    }
}

/// The formatting toolbar for the rich text editor.
struct RichTextToolbar: View {
    @Binding var textView: NSTextView?
    var onAction: () -> Void
    
    // Injected state from the editor
    var state: RichTextEditorState = RichTextEditorState()
    
    var body: some View {
        HStack(spacing: 2) {
            // Headers Group
            Group {
                toolbarButton(icon: "h.square.fill", action: { applyHeading(level: 1) }, help: "Heading 1", active: state.headingLevel == 1)
                toolbarButton(icon: "h.square", action: { applyHeading(level: 2) }, help: "Heading 2", active: state.headingLevel == 2)
            }
            
            toolbarDivider
            
            // Formatting Group
            Group {
                toolbarButton(icon: "bold", action: toggleBold, help: "Bold (⌘B)", active: state.isBold)
                    .keyboardShortcut("b", modifiers: .command)
                toolbarButton(icon: "italic", action: toggleItalic, help: "Italic (⌘I)", active: state.isItalic)
                    .keyboardShortcut("i", modifiers: .command)
                toolbarButton(icon: "underline", action: toggleUnderline, help: "Underline (⌘U)", active: state.isUnderline)
                    .keyboardShortcut("u", modifiers: .command)
            }
            
            toolbarDivider
            
            // Alignment Group
            Group {
                toolbarButton(icon: "text.alignleft", action: { textView?.alignLeft(nil) }, help: "Align Left", active: state.alignment == .left)
                toolbarButton(icon: "text.aligncenter", action: { textView?.alignCenter(nil) }, help: "Align Center", active: state.alignment == .center)
                toolbarButton(icon: "text.alignright", action: { textView?.alignRight(nil) }, help: "Align Right", active: state.alignment == .right)
            }
            
            toolbarDivider
            
            // Lists Group
            Group {
                toolbarButton(icon: "list.bullet", action: insertBulletList, help: "Bullet List", active: state.listType == NSTextList.MarkerFormat.disc.rawValue)
                toolbarButton(icon: "list.number", action: insertNumberedList, help: "Numbered List", active: state.listType == NSTextList.MarkerFormat.decimal.rawValue)
                toolbarButton(icon: "checklist", action: insertCheckbox, help: "Checklist")
            }
            
            toolbarDivider
            
            // Writing Tools
            toolbarButton(icon: "sparkles", action: { textView?.showWritingTools(nil) }, help: "Writing Tools")
                .foregroundColor(.accentColor)
        }
    }
    
    private var toolbarDivider: some View {
        Divider()
            .frame(height: 12)
            .padding(.horizontal, 4)
    }
    
    private func toolbarButton(icon: String, action: @escaping () -> Void, help: String, active: Bool = false) -> some View {
        Button(action: {
            action()
            onAction()
        }) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
                .foregroundColor(active ? .accentColor : .primary)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(active ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .help(help)
    }
    
    // MARK: - Actions
    
    private func applyHeading(level: Int) {
        textView?.toggleHeading(level: level)
    }
    
    private func toggleBold() {
        textView?.toggleFontTrait(.boldFontMask)
    }
    
    private func toggleItalic() {
        textView?.toggleFontTrait(.italicFontMask)
    }
    
    private func toggleUnderline() {
        textView?.toggleUnderline()
    }
    
    private func insertBulletList() {
        textView?.toggleList(markerFormat: .disc)
    }
    
    private func insertNumberedList() {
        textView?.toggleList(markerFormat: .decimal)
    }
    
    private func insertCheckbox() {
        textView?.insertCheckbox()
    }
}

/// Internal NSViewRepresentable for the NSTextView
struct RichTextEditorView: NSViewRepresentable {
    @Binding var text: NSAttributedString
    @Binding var textView: NSTextView?
    @Binding var state: RichTextEditorState
    @Binding var calculatedHeight: CGFloat
    var onTextChange: (() -> Void)?
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> FormattingTextView {
        let tv = FormattingTextView(usingTextLayoutManager: true)
        tv.coordinator = context.coordinator
        tv.delegate = context.coordinator
        tv.isRichText = true
        tv.allowsUndo = true
        tv.isEditable = true
        tv.isSelectable = true
        tv.font = NSFont.systemFont(ofSize: 15)
        tv.textContainerInset = NSSize(width: 0, height: 8)
        tv.backgroundColor = .clear
        tv.drawsBackground = false
        
        // Disable internal scrolling to let parent handle it
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        
        // Initial text
        tv.textStorage?.setAttributedString(text)
        
        DispatchQueue.main.async {
            self.textView = tv
            context.coordinator.updateState()
            context.coordinator.updateHeight(tv)
        }
        
        return tv
    }
    
    func updateNSView(_ tv: FormattingTextView, context: Context) {
        // Only update if external binding changed and is different from internal state
        if tv.attributedString() != text {
            let selectedRanges = tv.selectedRanges
            tv.textStorage?.setAttributedString(text)
            tv.selectedRanges = selectedRanges
            context.coordinator.updateState()
            context.coordinator.updateHeight(tv)
        }
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditorView
        private var shouldResetInlineFormattingAfterNewline = false
        private var shouldResetHeadingAfterNewline = false
        
        init(_ parent: RichTextEditorView) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            
            if shouldResetInlineFormattingAfterNewline {
                shouldResetInlineFormattingAfterNewline = false
                tv.resetInlineFormattingAfterNewline()
            }
            if shouldResetHeadingAfterNewline {
                shouldResetHeadingAfterNewline = false
                tv.resetHeadingAfterNewline()
            }
            
            let newText = tv.attributedString()
            if parent.text != newText {
                parent.text = newText
                parent.onTextChange?()
            }
            updateHeight(tv)
            updateState()
        }
        
        func updateHeight(_ tv: NSTextView) {
            // Force layout to get correct height
            if let layoutManager = tv.layoutManager, let textContainer = tv.textContainer {
                layoutManager.ensureLayout(for: textContainer)
                let usedRect = layoutManager.usedRect(for: textContainer)
                let newHeight = max(100, usedRect.height + tv.textContainerInset.height * 2 + 20)
                
                if abs(parent.calculatedHeight - newHeight) > 1 {
                    DispatchQueue.main.async {
                        self.parent.calculatedHeight = newHeight
                    }
                }
            } else if #available(macOS 12.0, *), let layoutManager = tv.textLayoutManager, let _ = tv.textContainer {
                // If using TextLayoutManager (TextKit 2)
                let usedRect = layoutManager.usageBoundsForTextContainer
                let newHeight = max(100, usedRect.height + tv.textContainerInset.height * 2 + 20)
                
                if abs(parent.calculatedHeight - newHeight) > 1 {
                    DispatchQueue.main.async {
                        self.parent.calculatedHeight = newHeight
                    }
                }
            }
        }
        
        func textViewDidChangeSelection(_ notification: Notification) {
            updateState()
            // Trigger native toolbar validation
            if let tv = notification.object as? NSTextView {
                tv.window?.toolbar?.validateVisibleItems()
            }
        }
        
        func updateState() {
            guard let tv = parent.textView else { return }
            var newState = RichTextEditorState()
            
            let attributes = tv.typingAttributes
            let font = attributes[.font] as? NSFont ?? tv.font ?? NSFont.systemFont(ofSize: 15)
            let traits = NSFontManager.shared.traits(of: font)
            
            newState.isBold = traits.contains(.boldFontMask)
            newState.isItalic = traits.contains(.italicFontMask)
            newState.isUnderline = (attributes[.underlineStyle] as? Int ?? 0) != 0
            
            if let style = attributes[.paragraphStyle] as? NSParagraphStyle {
                newState.alignment = style.alignment
                if let list = style.textLists.first {
                    newState.listType = list.markerFormat.rawValue
                }
            }
            
            newState.headingLevel = tv.selectionHeadingLevel()
            
            if parent.state != newState {
                DispatchQueue.main.async {
                    self.parent.state = newState
                }
            }
        }
        
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if textView.handleListExitOnNewline() {
                    updateState()
                    return true
                }
                shouldResetInlineFormattingAfterNewline = true
                shouldResetHeadingAfterNewline = textView.selectionHeadingLevel() != nil
                updateState()
                return false
            }
            
            // Handle standard formatting hotkeys if they aren't working by default
            if commandSelector == NSSelectorFromString("toggleBoldface:") {
                textView.toggleFontTrait(.boldFontMask)
                updateState()
                return true
            }
            if commandSelector == NSSelectorFromString("toggleItalics:") {
                textView.toggleFontTrait(.italicFontMask)
                updateState()
                return true
            }
            if commandSelector == NSSelectorFromString("toggleUnderline:") {
                textView.toggleUnderline()
                updateState()
                return true
            }
            
            return false
        }
    }
}

// MARK: - NSTextView Extensions for Formatting
extension NSTextView {
    
    private var listIndentStep: CGFloat { 24 } // Larger indent for better hierarchy
    
    func toggleFontTrait(_ trait: NSFontTraitMask) {
        guard let textStorage = self.textStorage else { return }
        let selection = self.selectedRange()
        let defaultFont = (self.typingAttributes[.font] as? NSFont) ?? self.font ?? NSFont.systemFont(ofSize: 15)
        let fontManager = NSFontManager.shared
        
        if selection.length == 0 {
            let traits = fontManager.traits(of: defaultFont)
            let updatedFont = traits.contains(trait)
                ? fontManager.convert(defaultFont, toNotHaveTrait: trait)
                : fontManager.convert(defaultFont, toHaveTrait: trait)
            self.typingAttributes[.font] = updatedFont
            return
        }
        
        textStorage.beginEditing()
        textStorage.enumerateAttribute(.font, in: selection, options: []) { value, range, _ in
            let font = (value as? NSFont) ?? defaultFont
            let traits = fontManager.traits(of: font)
            let updatedFont = traits.contains(trait)
                ? fontManager.convert(font, toNotHaveTrait: trait)
                : fontManager.convert(font, toHaveTrait: trait)
            textStorage.addAttribute(.font, value: updatedFont, range: range)
        }
        textStorage.endEditing()
    }
    
    func toggleUnderline() {
        guard let textStorage = self.textStorage else { return }
        let selection = self.selectedRange()
        
        if selection.length == 0 {
            let current = (self.typingAttributes[.underlineStyle] as? Int) ?? 0
            if current == 0 {
                self.typingAttributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            } else {
                self.typingAttributes.removeValue(forKey: .underlineStyle)
            }
            return
        }
        
        textStorage.beginEditing()
        textStorage.enumerateAttribute(.underlineStyle, in: selection, options: []) { value, range, _ in
            let current = (value as? Int) ?? 0
            if current == 0 {
                textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            } else {
                textStorage.removeAttribute(.underlineStyle, range: range)
            }
        }
        textStorage.endEditing()
    }
    
    func toggleList(markerFormat: NSTextList.MarkerFormat) {
        guard let textStorage = self.textStorage else { return }
        let selection = self.selectedRange()
        let ranges = paragraphRanges(for: selection, in: textStorage.string as NSString)
        let list = NSTextList(markerFormat: markerFormat, options: 0)
        var lastStyle: NSMutableParagraphStyle?
        
        textStorage.beginEditing()
        for range in ranges {
            let style = paragraphStyle(for: range, in: textStorage)
            var lists = style.textLists
            if let index = lists.firstIndex(where: { $0.markerFormat == list.markerFormat }) {
                lists.remove(at: index)
            } else {
                lists.removeAll()
                lists.append(list)
            }
            style.textLists = lists
            if lists.isEmpty {
                style.headIndent = 0
                style.firstLineHeadIndent = 0
                style.tabStops = []
                style.defaultTabInterval = 0
            } else {
                applyListIndentation(style, level: lists.count)
            }
            if range.length > 0 {
                textStorage.addAttribute(.paragraphStyle, value: style, range: range)
            }
            lastStyle = style
        }
        textStorage.endEditing()
        
        if selection.length == 0, let lastStyle {
            self.typingAttributes[.paragraphStyle] = lastStyle
        }
    }
    
    func insertCheckbox() {
        let selection = self.selectedRange()
        self.insertText("☐ ", replacementRange: selection)
    }
    
    func toggleHeading(level: Int) {
        if selectionHeadingLevel() == level {
            applyBodyStyle()
        } else {
            applyHeading(level: level)
        }
    }
    
    private func applyHeading(level: Int) {
        guard let textStorage = self.textStorage else { return }
        let heading = headingSpec(for: level)
        let headingFont = NSFont.systemFont(ofSize: heading.size, weight: heading.weight)
        let selection = self.selectedRange()
        let ranges = paragraphRanges(for: selection, in: textStorage.string as NSString)
        var lastStyle: NSMutableParagraphStyle?
        
        textStorage.beginEditing()
        for range in ranges {
            let style = paragraphStyle(for: range, in: textStorage)
            style.paragraphSpacingBefore = heading.spacingBefore
            style.paragraphSpacing = heading.spacingAfter
            if range.length > 0 {
                textStorage.addAttribute(.paragraphStyle, value: style, range: range)
                textStorage.addAttribute(.font, value: headingFont, range: range)
            }
            lastStyle = style
        }
        textStorage.endEditing()
        
        if selection.length == 0 {
            var attributes = self.typingAttributes
            attributes[.font] = headingFont
            if let lastStyle {
                attributes[.paragraphStyle] = lastStyle
            }
            self.typingAttributes = attributes
        }
    }
    
    func applyBodyStyle() {
        guard let textStorage = self.textStorage else { return }
        let selection = self.selectedRange()
        let ranges = paragraphRanges(for: selection, in: textStorage.string as NSString)
        let fontManager = NSFontManager.shared
        let baseFont = self.font ?? NSFont.systemFont(ofSize: 15)
        let bodyFont = fontManager.convert(baseFont, toSize: 15)
        var lastStyle: NSMutableParagraphStyle?
        
        textStorage.beginEditing()
        for range in ranges {
            let style = paragraphStyle(for: range, in: textStorage)
            style.paragraphSpacingBefore = 0
            style.paragraphSpacing = 8 // Default paragraph spacing
            if range.length > 0 {
                textStorage.addAttribute(.paragraphStyle, value: style, range: range)
                textStorage.addAttribute(.font, value: bodyFont, range: range)
            }
            lastStyle = style
        }
        textStorage.endEditing()
        
        if selection.length == 0 {
            var attributes = self.typingAttributes
            attributes[.font] = bodyFont
            if let lastStyle {
                attributes[.paragraphStyle] = lastStyle
            }
            self.typingAttributes = attributes
        }
    }
    
    // MARK: - Smart Newline Helpers
    
    func handleListExitOnNewline() -> Bool {
        guard let textStorage = self.textStorage else { return false }
        let selection = self.selectedRange()
        guard selection.length == 0 else { return false }
        
        let string = textStorage.string as NSString
        if string.length == 0 { return false }
        
        let location = min(selection.location, string.length)
        let paragraphRange = string.paragraphRange(for: NSRange(location: location, length: 0))
        let paragraphText = string.substring(with: paragraphRange)
        let isEmptyParagraph = paragraphText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !isEmptyParagraph { return false }
        
        let style = paragraphStyle(for: paragraphRange, in: textStorage)
        if style.textLists.isEmpty { return false }
        
        style.textLists = []
        style.headIndent = 0
        style.firstLineHeadIndent = 0
        style.tabStops = []
        style.defaultTabInterval = 0
        
        textStorage.beginEditing()
        if paragraphRange.length > 0 {
            textStorage.addAttribute(.paragraphStyle, value: style, range: paragraphRange)
        }
        textStorage.endEditing()
        self.typingAttributes[.paragraphStyle] = style
        return true
    }
    
    func resetInlineFormattingAfterNewline() {
        var attributes = self.typingAttributes
        let baseFont = (attributes[.font] as? NSFont) ?? self.font ?? NSFont.systemFont(ofSize: 15)
        let fontManager = NSFontManager.shared
        let withoutBold = fontManager.convert(baseFont, toNotHaveTrait: .boldFontMask)
        let withoutItalic = fontManager.convert(withoutBold, toNotHaveTrait: .italicFontMask)
        attributes[.font] = withoutItalic
        attributes.removeValue(forKey: .underlineStyle)
        self.typingAttributes = attributes
    }
    
    func resetHeadingAfterNewline() {
        var attributes = self.typingAttributes
        let baseFont = (attributes[.font] as? NSFont) ?? self.font ?? NSFont.systemFont(ofSize: 15)
        let fontManager = NSFontManager.shared
        let resizedFont = fontManager.convert(baseFont, toSize: 15)
        attributes[.font] = resizedFont
        
        if let paragraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle {
            let style = (paragraphStyle.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            style.paragraphSpacingBefore = 0
            style.paragraphSpacing = 8
            attributes[.paragraphStyle] = style
        }
        
        self.typingAttributes = attributes
    }
    
    // MARK: - Internal Helpers
    
    func selectionHeadingLevel() -> Int? {
        guard let textStorage = self.textStorage else { return nil }
        let selection = self.selectedRange()
        let ranges = paragraphRanges(for: selection, in: textStorage.string as NSString)
        guard let firstRange = ranges.first else { return nil }
        
        let firstSize = fontSize(for: firstRange, in: textStorage)
        guard let level = headingLevel(for: firstSize) else { return nil }
        
        for range in ranges.dropFirst() {
            let size = fontSize(for: range, in: textStorage)
            if headingLevel(for: size) != level { return nil }
        }
        return level
    }
    
    private func headingLevel(for fontSize: CGFloat) -> Int? {
        for level in 1...2 {
            let target = headingSpec(for: level).size
            if abs(fontSize - target) < 0.5 { return level }
        }
        return nil
    }
    
    private struct HeadingSpec {
        let size: CGFloat
        let weight: NSFont.Weight
        let spacingBefore: CGFloat
        let spacingAfter: CGFloat
    }
    
    private func headingSpec(for level: Int) -> HeadingSpec {
        switch level {
        case 1:
            return HeadingSpec(size: 22, weight: .bold, spacingBefore: 12, spacingAfter: 8)
        case 2:
            return HeadingSpec(size: 18, weight: .bold, spacingBefore: 8, spacingAfter: 4)
        default:
            return HeadingSpec(size: 15, weight: .regular, spacingBefore: 0, spacingAfter: 8)
        }
    }
    
    private func fontSize(for range: NSRange, in textStorage: NSTextStorage) -> CGFloat {
        if range.length == 0 || range.location >= textStorage.length {
            let font = (self.typingAttributes[.font] as? NSFont) ?? self.font ?? NSFont.systemFont(ofSize: 15)
            return font.pointSize
        }
        let font = textStorage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont ?? self.font ?? NSFont.systemFont(ofSize: 15)
        return font.pointSize
    }
    
    private func paragraphRanges(for selection: NSRange, in text: NSString) -> [NSRange] {
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
    
    private func paragraphStyle(for range: NSRange, in textStorage: NSTextStorage) -> NSMutableParagraphStyle {
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
    
    private func applyListIndentation(_ style: NSMutableParagraphStyle, level: Int) {
        let indent = listIndentStep * CGFloat(max(level, 1))
        style.headIndent = indent
        style.firstLineHeadIndent = 0
        style.tabStops = [NSTextTab(textAlignment: .left, location: indent, options: [:])]
        style.defaultTabInterval = listIndentStep
    }
}

// MARK: - FormattingResponder Protocol

@objc protocol FormattingResponder {
    func formatBold(_ sender: Any?)
    func formatItalic(_ sender: Any?)
    func formatUnderline(_ sender: Any?)
    func toggleBulletedList(_ sender: Any?)
    func toggleNumberedList(_ sender: Any?)
    func applyHeading1(_ sender: Any?)
    func applyHeading2(_ sender: Any?)
}

// MARK: - FormattingResponder Conformance

extension NSTextView: FormattingResponder {
    
    @objc func formatBold(_ sender: Any?) {
        toggleFontTrait(.boldFontMask)
        window?.toolbar?.validateVisibleItems()
    }
    
    @objc func formatItalic(_ sender: Any?) {
        toggleFontTrait(.italicFontMask)
        window?.toolbar?.validateVisibleItems()
    }
    
    @objc func formatUnderline(_ sender: Any?) {
        toggleUnderline()
        window?.toolbar?.validateVisibleItems()
    }
    
    @objc func toggleBulletedList(_ sender: Any?) {
        toggleList(markerFormat: .disc)
        window?.toolbar?.validateVisibleItems()
    }
    
    @objc func toggleNumberedList(_ sender: Any?) {
        toggleList(markerFormat: .decimal)
        window?.toolbar?.validateVisibleItems()
    }
    
    @objc func applyHeading1(_ sender: Any?) {
        toggleHeading(level: 1)
        window?.toolbar?.validateVisibleItems()
    }
    
    @objc func applyHeading2(_ sender: Any?) {
        toggleHeading(level: 2)
        window?.toolbar?.validateVisibleItems()
    }
}

// MARK: - Selection Query Methods for Toolbar Validation

extension NSTextView {
    
    func selectionHasTrait(_ trait: NSFontTraitMask) -> Bool {
        guard let textStorage = self.textStorage else { return false }
        
        let selection = self.selectedRange()
        let defaultFont = (self.typingAttributes[.font] as? NSFont) ?? self.font ?? NSFont.systemFont(ofSize: 15)
        let fontManager = NSFontManager.shared
        
        if selection.length == 0 {
            return fontManager.traits(of: defaultFont).contains(trait)
        }
        
        var hasTrait = true
        textStorage.enumerateAttribute(.font, in: selection, options: []) { value, _, stop in
            let font = (value as? NSFont) ?? defaultFont
            if !fontManager.traits(of: font).contains(trait) {
                hasTrait = false
                stop.pointee = true
            }
        }
        return hasTrait
    }
    
    func selectionHasUnderline() -> Bool {
        guard let textStorage = self.textStorage else { return false }
        
        let selection = self.selectedRange()
        if selection.length == 0 {
            let current = (self.typingAttributes[.underlineStyle] as? Int) ?? 0
            return current != 0
        }
        
        var hasUnderline = true
        textStorage.enumerateAttribute(.underlineStyle, in: selection, options: []) { value, _, stop in
            let current = (value as? Int) ?? 0
            if current == 0 {
                hasUnderline = false
                stop.pointee = true
            }
        }
        return hasUnderline
    }
    
    func selectionAlignment() -> NSTextAlignment? {
        guard let textStorage = self.textStorage else { return nil }
        
        let selection = self.selectedRange()
        let string = textStorage.string as NSString
        let ranges = selectionParagraphRanges(for: selection, in: string)
        guard let firstRange = ranges.first else { return nil }
        
        let firstStyle = selectionParagraphStyle(for: firstRange, in: textStorage)
        let alignment = firstStyle.alignment
        for range in ranges.dropFirst() {
            let style = selectionParagraphStyle(for: range, in: textStorage)
            if style.alignment != alignment {
                return nil
            }
        }
        return alignment
    }
    
    func selectionHasList(markerFormat: NSTextList.MarkerFormat) -> Bool {
        guard let textStorage = self.textStorage else { return false }
        
        let selection = self.selectedRange()
        let string = textStorage.string as NSString
        let ranges = selectionParagraphRanges(for: selection, in: string)
        guard !ranges.isEmpty else { return false }
        
        for range in ranges {
            let style = selectionParagraphStyle(for: range, in: textStorage)
            if !style.textLists.contains(where: { $0.markerFormat == markerFormat }) {
                return false
            }
        }
        return true
    }
    
    // Private helpers for selection queries (non-private versions to avoid conflicts)
    private func selectionParagraphRanges(for selection: NSRange, in text: NSString) -> [NSRange] {
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
    
    private func selectionParagraphStyle(for range: NSRange, in textStorage: NSTextStorage) -> NSParagraphStyle {
        if range.length == 0 || range.location >= textStorage.length {
            return (self.typingAttributes[.paragraphStyle] as? NSParagraphStyle) ?? NSParagraphStyle.default
        }
        return (textStorage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle) ?? NSParagraphStyle.default
    }
}
