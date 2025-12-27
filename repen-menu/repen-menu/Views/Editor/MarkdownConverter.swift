import Foundation
import AppKit

struct MarkdownConverter {
    
    /// Converts a Markdown string into a styled NSAttributedString for the editor
    static func fromMarkdown(_ markdown: String) -> NSAttributedString {
        guard !markdown.isEmpty else { return NSAttributedString(string: "") }
        
        let result = NSMutableAttributedString()
        let lines = markdown.components(separatedBy: "\n")
        
        let baseFont = NSFont.systemFont(ofSize: 15)
        let textColor = NSColor.labelColor
        
        for (index, line) in lines.enumerated() {
            var processedLine = line
            var headerLevel = 0
            var listMarker: NSTextList.MarkerFormat?
            var listPrefix = ""
            
            // 1. Detect and strip Header prefix
            if processedLine.hasPrefix("## ") {
                headerLevel = 2
                processedLine = String(processedLine.dropFirst(3))
            } else if processedLine.hasPrefix("# ") {
                headerLevel = 1
                processedLine = String(processedLine.dropFirst(2))
            }
            
            // 2. Detect and handle Lists
            if processedLine.hasPrefix("- [ ] ") {
                listMarker = .disc
                listPrefix = "☐ "
                processedLine = String(processedLine.dropFirst(6))
            } else if processedLine.hasPrefix("- [x] ") || processedLine.hasPrefix("- [X] ") {
                listMarker = .disc
                listPrefix = "☑ "
                processedLine = String(processedLine.dropFirst(6))
            } else if processedLine.hasPrefix("- ") {
                listMarker = .disc
                listPrefix = "• "
                processedLine = String(processedLine.dropFirst(2))
            } else if processedLine.hasPrefix("* ") {
                listMarker = .disc
                listPrefix = "• "
                processedLine = String(processedLine.dropFirst(2))
            } else if let match = processedLine.range(of: #"^(\d+)\. "#, options: .regularExpression) {
                listMarker = .decimal
                let num = processedLine[processedLine.startIndex..<match.upperBound].dropLast(2)
                listPrefix = "\(num). "
                processedLine = String(processedLine[match.upperBound...])
            }
            
            // 3. Parse inline formatting (bold, italic, underline)
            let attrLine = parseInlineFormatting(processedLine, baseFont: baseFont, textColor: textColor)
            
            // Apply Header Styling
            if headerLevel > 0 {
                let size: CGFloat = headerLevel == 1 ? 22 : 18
                let weight: NSFont.Weight = .bold
                let headerFont = NSFont.systemFont(ofSize: size, weight: weight)
                attrLine.addAttribute(.font, value: headerFont, range: NSRange(location: 0, length: attrLine.length))
                
                // Store heading level as custom attribute for roundtrip
                attrLine.addAttribute(.headingLevel, value: headerLevel, range: NSRange(location: 0, length: attrLine.length))
                
                let style = NSMutableParagraphStyle()
                style.paragraphSpacingBefore = headerLevel == 1 ? 12 : 8
                style.paragraphSpacing = headerLevel == 1 ? 8 : 4
                attrLine.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: attrLine.length))
            }
            
            // Apply List Styling
            if let marker = listMarker {
                let style = NSMutableParagraphStyle()
                let list = NSTextList(markerFormat: marker, options: 0)
                style.textLists = [list]
                let indent: CGFloat = 24
                style.headIndent = indent
                style.firstLineHeadIndent = 0
                style.tabStops = [NSTextTab(textAlignment: .left, location: indent, options: [:])]
                style.defaultTabInterval = indent
                
                // Insert list prefix
                let prefixAttr = NSAttributedString(string: listPrefix, attributes: [
                    .font: baseFont,
                    .foregroundColor: textColor
                ])
                attrLine.insert(prefixAttr, at: 0)
                attrLine.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: attrLine.length))
            }
            
            result.append(attrLine)
            if index < lines.count - 1 {
                result.append(NSAttributedString(string: "\n"))
            }
        }
        
        return result
    }
    
    /// Parse inline markdown formatting (**bold**, *italic*, <u>underline</u>)
    private static func parseInlineFormatting(_ text: String, baseFont: NSFont, textColor: NSColor) -> NSMutableAttributedString {
        var result = NSMutableAttributedString()
        var remaining = text
        var currentIndex = remaining.startIndex
        
        while currentIndex < remaining.endIndex {
            // Check for bold (**text**)
            if remaining[currentIndex...].hasPrefix("**") {
                let afterStart = remaining.index(currentIndex, offsetBy: 2)
                if let endRange = remaining[afterStart...].range(of: "**") {
                    let boldText = String(remaining[afterStart..<endRange.lowerBound])
                    let boldAttr = NSMutableAttributedString(string: boldText, attributes: [
                        .font: NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask),
                        .foregroundColor: textColor
                    ])
                    result.append(boldAttr)
                    currentIndex = remaining.index(endRange.upperBound, offsetBy: 0)
                    remaining = String(remaining[currentIndex...])
                    currentIndex = remaining.startIndex
                    continue
                }
            }
            
            // Check for italic (*text*) - but not bold
            if remaining[currentIndex...].hasPrefix("*") && !remaining[currentIndex...].hasPrefix("**") {
                let afterStart = remaining.index(currentIndex, offsetBy: 1)
                if afterStart < remaining.endIndex {
                    // Find closing * that's not followed by another *
                    var searchStart = afterStart
                    while let endRange = remaining[searchStart...].range(of: "*") {
                        // Make sure it's not part of **
                        let nextIndex = remaining.index(after: endRange.lowerBound)
                        if nextIndex >= remaining.endIndex || remaining[nextIndex] != "*" {
                            // Check previous char isn't *
                            let prevIndex = remaining.index(before: endRange.lowerBound)
                            if prevIndex >= afterStart && remaining[prevIndex] != "*" || prevIndex < afterStart {
                                let italicText = String(remaining[afterStart..<endRange.lowerBound])
                                let italicAttr = NSMutableAttributedString(string: italicText, attributes: [
                                    .font: NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask),
                                    .foregroundColor: textColor
                                ])
                                result.append(italicAttr)
                                currentIndex = remaining.index(endRange.upperBound, offsetBy: 0)
                                remaining = String(remaining[currentIndex...])
                                currentIndex = remaining.startIndex
                                break
                            }
                        }
                        searchStart = remaining.index(after: endRange.lowerBound)
                    }
                    if currentIndex == remaining.startIndex {
                        // No match found, treat as regular text
                        result.append(NSAttributedString(string: String(remaining[currentIndex]), attributes: [
                            .font: baseFont,
                            .foregroundColor: textColor
                        ]))
                        currentIndex = remaining.index(after: currentIndex)
                        remaining = String(remaining[currentIndex...])
                        currentIndex = remaining.startIndex
                    }
                    continue
                }
            }
            
            // Check for underline (<u>text</u>)
            if remaining[currentIndex...].hasPrefix("<u>") {
                let afterStart = remaining.index(currentIndex, offsetBy: 3)
                if let endRange = remaining[afterStart...].range(of: "</u>") {
                    let underlineText = String(remaining[afterStart..<endRange.lowerBound])
                    let underlineAttr = NSMutableAttributedString(string: underlineText, attributes: [
                        .font: baseFont,
                        .foregroundColor: textColor,
                        .underlineStyle: NSUnderlineStyle.single.rawValue
                    ])
                    result.append(underlineAttr)
                    currentIndex = remaining.index(endRange.upperBound, offsetBy: 0)
                    remaining = String(remaining[currentIndex...])
                    currentIndex = remaining.startIndex
                    continue
                }
            }
            
            // Regular character
            result.append(NSAttributedString(string: String(remaining[currentIndex]), attributes: [
                .font: baseFont,
                .foregroundColor: textColor
            ]))
            currentIndex = remaining.index(after: currentIndex)
            if currentIndex < remaining.endIndex {
                remaining = String(remaining[currentIndex...])
                currentIndex = remaining.startIndex
            } else {
                break
            }
        }
        
        return result
    }
    
    /// Converts a styled NSAttributedString from the editor back into a Markdown string
    static func toMarkdown(_ attributedString: NSAttributedString) -> String {
        let string = attributedString.string
        guard !string.isEmpty else { return "" }
        
        var markdownResult = ""
        let nsString = string as NSString
        
        // Process line by line to handle block-level formatting (headers, lists)
        let lines = string.components(separatedBy: "\n")
        var lineStart = 0
        
        for (lineIndex, line) in lines.enumerated() {
            let lineRange = NSRange(location: lineStart, length: (line as NSString).length)
            guard lineRange.location < nsString.length else { break }
            
            var lineMarkdown = ""
            var headerPrefix = ""
            var listPrefix = ""
            
            // Check for heading level (custom attribute or font size)
            if lineRange.length > 0 {
                if let headingLevel = attributedString.attribute(.headingLevel, at: lineRange.location, effectiveRange: nil) as? Int {
                    headerPrefix = headingLevel == 1 ? "# " : "## "
                } else if let font = attributedString.attribute(.font, at: lineRange.location, effectiveRange: nil) as? NSFont {
                    if font.pointSize >= 20 {
                        headerPrefix = "# "
                    } else if font.pointSize >= 17 {
                        headerPrefix = "## "
                    }
                }
                
                // Check for list
                if let style = attributedString.attribute(.paragraphStyle, at: lineRange.location, effectiveRange: nil) as? NSParagraphStyle {
                    if let list = style.textLists.first {
                        if list.markerFormat == .disc {
                            listPrefix = "- "
                        } else if list.markerFormat == .decimal {
                            listPrefix = "1. "
                        }
                    }
                }
            }
            
            lineMarkdown += headerPrefix
            lineMarkdown += listPrefix
            
            // Process inline formatting within the line
            var lineContent = line
            // Strip list bullet/number from start if present
            if !listPrefix.isEmpty {
                if lineContent.hasPrefix("• ") {
                    lineContent = String(lineContent.dropFirst(2))
                } else if lineContent.hasPrefix("☐ ") || lineContent.hasPrefix("☑ ") {
                    lineContent = String(lineContent.dropFirst(2))
                } else if let match = lineContent.range(of: #"^\d+\. "#, options: .regularExpression) {
                    lineContent = String(lineContent[match.upperBound...])
                }
            }
            
            // Now process inline formatting
            if lineRange.length > 0 && lineRange.location + lineRange.length <= nsString.length {
                let contentStart = lineStart + (line.count - lineContent.count)
                let contentRange = NSRange(location: contentStart, length: lineContent.count)
                
                if contentRange.length > 0 && contentRange.location + contentRange.length <= nsString.length {
                    lineMarkdown += processInlineFormatting(attributedString, range: contentRange, isHeader: !headerPrefix.isEmpty)
                }
            }
            
            markdownResult += lineMarkdown
            if lineIndex < lines.count - 1 {
                markdownResult += "\n"
            }
            
            lineStart += line.count + 1 // +1 for newline
        }
        
        return markdownResult
    }
    
    /// Process inline formatting (bold, italic, underline) for a range
    private static func processInlineFormatting(_ attrString: NSAttributedString, range: NSRange, isHeader: Bool) -> String {
        var result = ""
        let nsString = attrString.string as NSString
        
        attrString.enumerateAttributes(in: range, options: []) { attrs, attrRange, _ in
            var text = nsString.substring(with: attrRange)
            let font = attrs[.font] as? NSFont
            let traits = font?.fontDescriptor.symbolicTraits ?? []
            let isBold = traits.contains(.bold)
            let isItalic = traits.contains(.italic)
            let isUnderline = (attrs[.underlineStyle] as? Int ?? 0) != 0
            
            // Don't add bold markers for headers (they're bold by default)
            if isBold && !isHeader {
                text = "**\(text)**"
            }
            if isItalic {
                text = "*\(text)*"
            }
            if isUnderline {
                text = "<u>\(text)</u>"
            }
            
            result += text
        }
        
        return result
    }
}

// MARK: - Custom Attribute Key for Heading Level
extension NSAttributedString.Key {
    static let headingLevel = NSAttributedString.Key("headingLevel")
}
