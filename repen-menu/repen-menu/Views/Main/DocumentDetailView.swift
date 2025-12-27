import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

// MARK: - Document Detail View

struct DocumentDetailView: View {
    let document: Document
    
    @StateObject private var player = AudioPlayerController()
    @ObservedObject private var recorder = AudioRecorder.shared
    @State private var transcriptContent: String = ""
    @State private var summaryContent: String = ""
    @State private var notesContent = NSAttributedString(string: "")
    @State private var isTranscribing = false
    @State private var isSummarizing = false
    @State private var errorMessage: String?
    @State private var showTranscriptSheet = false
    @State private var isEditingTitle = false
    @State private var editedTitle: String = ""
    @State private var showSummary = true
    @State private var hasCopied = false
    @State private var showFormattingPopover = false
    @Environment(\.colorScheme) private var colorScheme
    
    private var folderURL: URL { DocumentStore.shared.folderURL }
    
    private var audioURL: URL { document.audioURL(in: folderURL) }
    private var transcriptURL: URL { document.transcriptURL(in: folderURL) }
    private var summaryURL: URL { document.summaryURL(in: folderURL) }
    private var notesURL: URL { document.notesURL(in: folderURL) }
    
    private var hasTranscript: Bool {
        FileManager.default.fileExists(atPath: transcriptURL.path)
    }
    
    private var hasRecording: Bool {
        FileManager.default.fileExists(atPath: audioURL.path)
    }
    
    private var hasSummary: Bool {
        FileManager.default.fileExists(atPath: summaryURL.path)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Compact header: title + info
                compactHeader
                
                // Error message if present
                if let error = errorMessage {
                    errorBanner(error)
                }
                
                // Toggle between Summary and Notes
                contentToggleHeader
                
                Divider()
                    .padding(.vertical, 8)
                
                // Content area
                if showSummary {
                    summaryContentView
                } else {
                    notesContentView
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // Transcribe button
                if isTranscribing {
                    ProgressView()
                        .scaleEffect(0.6)
                        .help("Transcribing...")
                } else if !hasTranscript {
                    Button(action: transcribe) {
                        Label("Transcribe", systemImage: "waveform.badge.plus")
                    }
                    .help("Transcribe with AI")
                }
                
                // Summarize button
                if hasTranscript && !isTranscribing {
                    if isSummarizing {
                        ProgressView()
                            .scaleEffect(0.6)
                            .help("Summarizing...")
                    } else {
                        Button(action: summarize) {
                            Label("Summarize", systemImage: "sparkles")
                        }
                        .help("Summarize with AI")
                    }
                }
                
                // Formatting popover trigger
                Button(action: { showFormattingPopover.toggle() }) {
                    Label("Format", systemImage: "textformat")
                }
                .help("Formatting Options")
                .popover(isPresented: $showFormattingPopover, arrowEdge: .bottom) {
                    FormattingPopoverView(
                        textView: $textView,
                        state: $editorState,
                        onAction: { notesVM.debouncer.send() },
                        updateState: { updateEditorState() }
                    )
                }
                
                Divider()
                
                // Show in Finder
                Button(action: showInFinder) {
                    Label("Show in Finder", systemImage: "folder")
                }
                .help("Show in Finder")
                
                // Share
                if hasRecording {
                    ShareLink(item: audioURL) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .help("Share Recording")
                }
            }
        }
        .sheet(isPresented: $showTranscriptSheet) {
            TranscriptSheetView(
                content: transcriptContent, 
                recordingName: document.title,
                player: player
            )
        }
        .onAppear {
            editedTitle = document.title
            loadTranscript()
            loadSummary()
            loadNotes()
            if hasRecording { player.load(url: audioURL) }
        }
        .onDisappear {
            saveNotes()
            player.stop()
        }
    }
    
    // MARK: - Compact Header
    
    private var compactHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title
            TextField("Document Title", text: $editedTitle)
                .font(.system(size: 20, weight: .bold))
                .textFieldStyle(.plain)
                .onSubmit { saveTitle() }
            
            // Actions if no recording
            if !hasRecording {
                audioActionsSection
            }
            
            // Info row: date, combined media badge
            HStack(spacing: 12) {
                // Date
                Label {
                    Text(document.createdAt, style: .date)
                } icon: {
                    Image(systemName: "calendar")
                }
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                
                // Combined Media Badge (Player + Transcript Status + Recording)
                if recorder.isRecording && recorder.currentDocument?.id == document.id {
                    // Recording State
                    Button(action: { Task { await recorder.stopRecording() } }) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                            
                            Text(recorder.elapsedDisplay)
                                .font(.system(size: 11, weight: .medium).monospacedDigit())
                            
                            Text("Stop")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.1))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.red.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.red)
                    .help("Stop Recording")
                } else if hasRecording {
                    // Playback State
                    Button(action: { showTranscriptSheet = true }) {
                        HStack(spacing: 6) {
                            // Play/Pause icon
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 10, weight: .bold))
                            
                            // Time / Status
                            if player.isPlaying || player.currentTime > 0 {
                                Text("\(player.currentTimeDisplay) / \(player.durationDisplay)")
                                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                            } else {
                                Text(player.durationDisplay)
                                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                            }
                            
                            // Transcript indication
                            if hasTranscript {
                                Image(systemName: "text.bubble.fill") // or checkmark.circle.fill
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            hasTranscript 
                                ? Color.green.opacity(0.12) 
                                : Color.secondary.opacity(0.1)
                        )
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(
                                    hasTranscript 
                                        ? Color.green.opacity(0.3) 
                                        : Color.primary.opacity(0.05),
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(hasTranscript ? .green : .secondary)
                    .help("View Transcript & Player")
                }
                
                Spacer()
            }
        }
    }
    
    // MARK: - Inline Compact Player
    
    private var inlineCompactPlayer: some View {
        HStack(spacing: 8) {
            // Play/Pause
            Button(action: player.togglePlayPause) {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.accentColor))
            }
            .buttonStyle(.plain)
            
            // Time
            Text(player.currentTimeDisplay)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
            
            // Mini progress
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.1))
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: max(2, geometry.size.width * player.progress))
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let progress = max(0, min(1, value.location.x / geometry.size.width))
                            player.seek(to: progress)
                        }
                )
            }
            .frame(width: 80, height: 3)
            
            Text(player.durationDisplay)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
            
            // Speed
            Menu {
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                    Button(action: { player.setSpeed(Float(speed)) }) {
                        HStack {
                            Text("\(speed, specifier: "%.2g")x")
                            if abs(player.playbackSpeed - Float(speed)) < 0.01 {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Text("\(player.playbackSpeed, specifier: "%.2g")x")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.04))
        )
    }
    
    // Keep title section for reference but use compactHeader instead
    private var titleSection: some View {
        TextField("Document Title", text: $editedTitle)
            .font(.system(size: 24, weight: .bold))
            .textFieldStyle(.plain)
            .onSubmit {
                saveTitle()
            }
            .onChange(of: editedTitle) { oldValue, newValue in
                // Debounced save - saves after typing stops
            }
    }
    
    private func saveTitle() {
        guard !editedTitle.isEmpty, editedTitle != document.title else { return }
        DocumentStore.shared.updateTitle(for: document, newTitle: editedTitle)
    }
    
    // MARK: - Document Info Header
    
    private var recordingInfoHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Info badges row
            HStack(spacing: 16) {
                Label {
                    Text(document.createdAt, style: .date)
                } icon: {
                    Image(systemName: "calendar")
                }
                
                if hasTranscript {
                    Button(action: { showTranscriptSheet = true }) {
                        Label("Transcribed", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                    .buttonStyle(.plain)
                    .help("View Transcript")
                }
                
                Spacer()
            }
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            
            // Mini player (only if recording exists)
            if hasRecording {
                MiniPlayerView(player: player)
            } else {
                // Action buttons for empty document
                audioActionsSection
            }
        }
    }
    
    private var audioActionsSection: some View {
        HStack(spacing: 12) {
            // Start Recording button
            Button(action: startRecordingForDocument) {
                Label("Start Recording", systemImage: "record.circle")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            
            // Import Audio button
            Button(action: importAudioFile) {
                Label("Import Audio", systemImage: "square.and.arrow.down")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.bordered)
        }
    }
    
    private func startRecordingForDocument() {
        Task {
            // Update AudioRecorder to use this document
            AudioRecorder.shared.currentDocument = document
            await AudioRecorder.shared.startRecording()
        }
    }
    
    private func importAudioFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .wav, .mp3, .aiff]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose an audio file to transcribe"
        
        if panel.runModal() == .OK, let url = panel.url {
            // Copy file to document's audio location
            let destURL = document.audioURL(in: DocumentStore.shared.folderURL)
            do {
                if FileManager.default.fileExists(atPath: destURL.path) {
                    try FileManager.default.removeItem(at: destURL)
                }
                try FileManager.default.copyItem(at: url, to: destURL)
                DocumentStore.shared.updateFlags(for: document)
                DocumentStore.shared.refresh()
                // Reload player
                player.load(url: destURL)
            } catch {
                errorMessage = "Failed to import: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Error Banner
    
    private func errorBanner(_ error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(error)
                .font(.callout)
            Spacer()
            Button("Dismiss") {
                errorMessage = nil
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
        }
        .padding(12)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
    
    // MARK: - Content Toggle Section
    
    class NotesViewModel: ObservableObject {
        let debouncer = PassthroughSubject<Void, Never>()
        private var cancellables = Set<AnyCancellable>()
        var onSave: (() -> Void)?
        
        init() {
            debouncer
                .debounce(for: .seconds(1), scheduler: RunLoop.main)
                .sink { [weak self] _ in
                    self?.onSave?()
                }
                .store(in: &cancellables)
        }
    }
    
    @StateObject private var notesVM = NotesViewModel()
    @State private var textView: NSTextView?
    @State private var editorState = RichTextEditorState()
    @State private var editorHeight: CGFloat = 300
    @Namespace private var toggleNamespace
    
    // Just the toggle header without content
    private var contentToggleHeader: some View {
        HStack(spacing: 8) {
            // Sliding Switch
            HStack(spacing: 0) {
                toggleSegment(title: "Summary", icon: "sparkles", isSelected: showSummary) {
                    showSummary = true
                }
                
                toggleSegment(title: "Notes", icon: "note.text", isSelected: !showSummary) {
                    showSummary = false
                }
            }
            .padding(2)
            .background(Color.primary.opacity(0.04))
            .clipShape(Capsule())
            
            Spacer()
            
            if showSummary && !summaryContent.isEmpty {
                Button(action: copySummary) {
                    HStack(spacing: 4) {
                        Image(systemName: hasCopied ? "checkmark" : "doc.on.doc")
                        if hasCopied {
                            Text("Copied").transition(.opacity)
                        } else {
                            Text("Copy")
                        }
                    }
                    .font(.system(size: 12))
                    .animation(.spring(), value: hasCopied)
                }
                .buttonStyle(.plain)
                .foregroundColor(hasCopied ? .green : .secondary)
                .help("Copy Summary")
            }
        }
        .onAppear {
            notesVM.onSave = { self.saveNotes() }
        }
    }
    
    private func toggleSegment(title: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(minWidth: 90)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(isSelected ? .accentColor : .secondary)
        .background {
            if isSelected {
                Capsule()
                    .fill(Color.accentColor.opacity(0.12))
                    .matchedGeometryEffect(id: "toggleSelection", in: toggleNamespace)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showSummary)
    }
    
    // Keep old contentToggleSection for reference (unused now)
    private var contentToggleSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            contentToggleHeader
            
            if showSummary {
                summaryContentView
            } else {
                notesContentView
            }
        }
    }
    
    
    private var summaryContentView: some View {
        Group {
            if isSummarizing {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Generating summary...")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .padding(16)
            } else if !summaryContent.isEmpty {
                MarkdownView(markdown: summaryContent)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if hasTranscript {
                VStack(spacing: 12) {
                    Text("No summary yet")
                        .foregroundColor(.secondary)
                    Button(action: summarize) {
                        Label("Generate Summary", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
            } else {
                Text("Record or import audio, then transcribe to generate a summary.")
                    .foregroundColor(.secondary)
                    .padding(16)
            }
        }
    }
    
    private var notesContentView: some View {
        NotesEditorView(
            attributedText: $notesContent,
            textView: $textView,
            state: $editorState,
            editorHeight: $editorHeight,
            onTextChange: { notesVM.debouncer.send() }
        )
        .frame(height: editorHeight)
    }
    
    // MARK: - State Update Helper
    
    private func updateEditorState() {
        guard let tv = textView else { return }
        
        let attributes = tv.typingAttributes
        let font = attributes[.font] as? NSFont ?? tv.font ?? NSFont.systemFont(ofSize: 15)
        let traits = NSFontManager.shared.traits(of: font)
        
        var newState = RichTextEditorState()
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
        
        if editorState != newState {
            editorState = newState
        }
    }
    
    // MARK: - Transcript Preview Section
    
    private var transcriptPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Transcript", systemImage: "text.bubble")
                    .font(.headline)
                Spacer()
                if hasTranscript {
                    Button(action: { showTranscriptSheet = true }) {
                        Label("View Full", systemImage: "arrow.up.left.and.arrow.down.right")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            
            if isTranscribing {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Transcribing...")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .padding(16)
            } else if hasTranscript {
                Text(transcriptPreview)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .lineLimit(4)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.96))
                    .cornerRadius(10)
                    .onTapGesture {
                        showTranscriptSheet = true
                    }
            } else {
                Button(action: transcribe) {
                    Label("Transcribe Recording", systemImage: "waveform.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .padding(.vertical, 8)
            }
        }
    }
    
    private var transcriptPreview: String {
        let text = transcriptContent
            .components(separatedBy: "\n")
            .filter { !$0.hasPrefix("**[") && !$0.hasPrefix("---") && !$0.hasPrefix("##") && !$0.hasPrefix("- **") && !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(text.prefix(300)) + (text.count > 300 ? "..." : "")
    }
    
    private var floatingPlayBar: some View {
        HStack(spacing: 16) {
            // Current time
            Text(player.currentTimeDisplay)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .trailing)
            
            // Skip back 15s
            Button(action: { player.skip(by: -15) }) {
                Image(systemName: "gobackward.15")
                    .font(.system(size: 15))
            }
            .buttonStyle(.plain)
            .foregroundColor(.primary.opacity(0.6))
            
            // Play/Pause - prominent center button
            Button(action: player.togglePlayPause) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .offset(x: player.isPlaying ? 0 : 1)
                }
            }
            .buttonStyle(.plain)
            
            // Skip forward 15s
            Button(action: { player.skip(by: 15) }) {
                Image(systemName: "goforward.15")
                    .font(.system(size: 15))
            }
            .buttonStyle(.plain)
            .foregroundColor(.primary.opacity(0.6))
            
            // Remaining time
            Text("-\(player.remainingTimeDisplay)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .leading)
            
            // Progress bar (compact)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.1))
                    
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: max(4, geometry.size.width * player.progress))
                }
                .frame(height: 4)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let progress = max(0, min(1, value.location.x / geometry.size.width))
                            player.seek(to: progress)
                        }
                )
            }
            .frame(height: 4)
            
            // Speed control
            Menu {
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                    Button(action: { player.setSpeed(Float(speed)) }) {
                        HStack {
                            Text("\(speed, specifier: "%.2g")x")
                            if abs(player.playbackSpeed - Float(speed)) < 0.01 {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Text("\(player.playbackSpeed, specifier: "%.2g")x")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.12), radius: 16, x: 0, y: 4)
        )
        .overlay(
            Capsule()
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
    
    private func loadTranscript() {
        if hasTranscript {
            transcriptContent = (try? String(contentsOf: transcriptURL, encoding: .utf8)) ?? ""
        } else {
            transcriptContent = ""
        }
    }
    
    private func loadNotes() {
        let oldNotesURL = folderURL.appendingPathComponent("\(document.id).notes")
        
        // Migration: If .notes.md doesn't exist but old .notes does
        if !FileManager.default.fileExists(atPath: notesURL.path) && 
           FileManager.default.fileExists(atPath: oldNotesURL.path) {
            if let content = try? String(contentsOf: oldNotesURL, encoding: .utf8) {
                // Check if it's the combined format
                if content.contains("## AI Summary") && content.contains("---") {
                    let parts = content.components(separatedBy: "---")
                    let summaryPart = parts[0].replacingOccurrences(of: "## AI Summary", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let notesPart = (parts.count > 1 ? parts[1] : "").trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    // Save separated files
                    try? summaryPart.write(to: summaryURL, atomically: true, encoding: .utf8)
                    try? notesPart.write(to: notesURL, atomically: true, encoding: .utf8)
                    
                    notesContent = MarkdownConverter.fromMarkdown(notesPart)
                    summaryContent = summaryPart
                } else {
                    // Just a rename
                    try? content.write(to: notesURL, atomically: true, encoding: .utf8)
                    notesContent = MarkdownConverter.fromMarkdown(content)
                }
                // Delete old file
                try? FileManager.default.removeItem(at: oldNotesURL)
            }
        } else if FileManager.default.fileExists(atPath: notesURL.path) {
            if let md = try? String(contentsOf: notesURL, encoding: .utf8) {
                notesContent = MarkdownConverter.fromMarkdown(md)
            }
        } else {
            notesContent = NSAttributedString(string: "")
        }
    }
    
    private func loadSummary() {
        if FileManager.default.fileExists(atPath: summaryURL.path) {
            summaryContent = (try? String(contentsOf: summaryURL, encoding: .utf8)) ?? ""
        } else {
            summaryContent = ""
        }
    }
    
    private func saveNotes() {
        let md = MarkdownConverter.toMarkdown(notesContent)
        
        if md.isEmpty {
            // Delete the file if notes are empty
            try? FileManager.default.removeItem(at: notesURL)
        } else {
            try? md.write(to: notesURL, atomically: true, encoding: .utf8)
        }
    }
    
    private func showInFinder() {
        // Show the document's folder
        NSWorkspace.shared.activateFileViewerSelecting([folderURL])
    }
    
    private func copyTranscript() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcriptContent, forType: .string)
    }
    
    private func copySummary() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summaryContent, forType: .string)
        
        withAnimation {
            hasCopied = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                hasCopied = false
            }
        }
    }
    
    private func summarize() {
        guard hasTranscript else { return }
        
        isSummarizing = true
        errorMessage = nil
        
        // Capture value before Task to avoid Swift 6 concurrency warning
        let transcript = transcriptContent
        
        Task {
            // Extract plain text from the markdown transcript
            let plainText = transcript
                .components(separatedBy: "\n")
                .filter { !$0.hasPrefix("**[") && !$0.hasPrefix("---") && !$0.hasPrefix("##") && !$0.hasPrefix("- **") }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            let result = await OpenAIService.shared.summarize(
                transcript: plainText,
                documentTitle: document.title,
                date: document.createdAt
            )
            
            await MainActor.run {
                isSummarizing = false
                
                if result.success, let summary = result.summary {
                    // Extract title from summary if it starts with # 
                    if UserDefaults.standard.bool(forKey: "autoTitleFromSummary") {
                        if let titleLine = summary.components(separatedBy: "\n").first,
                           titleLine.hasPrefix("# ") {
                            let extractedTitle = String(titleLine.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                            if !extractedTitle.isEmpty {
                                DocumentStore.shared.updateTitle(for: document, newTitle: extractedTitle)
                                editedTitle = extractedTitle
                            }
                        }
                    }
                    
                    // Save summary to separate file
                    summaryContent = summary
                    do {
                        try summary.write(to: summaryURL, atomically: true, encoding: .utf8)
                    } catch {
                        errorMessage = "Failed to save summary: \(error.localizedDescription)"
                    }
                } else {
                    errorMessage = result.error ?? "Failed to summarize"
                }
            }
        }
    }
    
    private func transcribe() {
        isTranscribing = true
        errorMessage = nil
        
        Task {
            let result = await DeepgramService.shared.transcribe(audioURL: audioURL) { _ in }
            
            await MainActor.run {
                isTranscribing = false
                
                if result.success, let _ = result.text {
                    // Save transcript
                    let markdown = generateTranscriptMarkdown(result: result)
                    try? markdown.write(to: transcriptURL, atomically: true, encoding: .utf8)
                    loadTranscript()
                } else {
                    errorMessage = result.error ?? "Unknown error"
                }
            }
        }
    }
    
    private func generateTranscriptMarkdown(result: TranscriptionResult) -> String {
        var md = ""
        
        if let segments = result.segments, !segments.isEmpty {
            for segment in segments {
                let startTime = formatTimestamp(segment.start)
                let endTime = formatTimestamp(segment.end)
                md += "**[\(startTime) - \(endTime)]**\n"
                md += "\(segment.text)\n\n"
            }
        } else if let text = result.text {
            md += "\(text)\n\n"
        }
        
        return md
    }
    
    private func formatTimestamp(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
