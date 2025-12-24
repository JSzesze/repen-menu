import SwiftUI
import AppKit
import Combine
import AVFoundation

// MARK: - Window Controller

final class HistoryWindowController: NSWindowController, NSToolbarDelegate {
    static let shared = HistoryWindowController()
    
    private let defaultSize = NSSize(width: 900, height: 600)
    
    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = false
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 600, height: 400)
        
        // Disable state restoration to prevent small window
        window.isRestorable = false
        
        super.init(window: window)
        
        // Setup toolbar with sidebar toggle
        let toolbar = NSToolbar(identifier: "MainToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        
        window.contentViewController = NSHostingController(rootView: HistoryWindowView())
        
        // Set frame and center after initialization
        window.setContentSize(defaultSize)
        window.center()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func showWindow() {
        // Ensure window is proper size when shown
        if let window = window {
            if window.frame.size.width < defaultSize.width || window.frame.size.height < defaultSize.height {
                window.setContentSize(defaultSize)
                window.center()
            }
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // MARK: - NSToolbarDelegate
    
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace]
    }
    
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace]
    }
    
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        return nil // Use system-provided items
    }
}

// MARK: - Main Window View

struct HistoryWindowView: View {
    @State private var selectedFilter: DateFilter = .all
    @State private var selectedRecording: URL?
    @State private var showSettings = false
    @State private var searchText = ""
    @AppStorage("isDarkMode") private var isDarkMode = false
    @ObservedObject private var recorder = AudioRecorder.shared
    
    enum DateFilter: String, CaseIterable {
        case all = "All"
        case today = "Today"
        case thisWeek = "This Week"
    }
    
    var filteredURLs: [URL] {
        var urls = recorder.recordedURLs
        
        let calendar = Calendar.current
        let now = Date()
        
        switch selectedFilter {
        case .all:
            break
        case .today:
            urls = urls.filter { url in
                guard let date = url.creationDate else { return false }
                return calendar.isDateInToday(date)
            }
        case .thisWeek:
            let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
            urls = urls.filter { url in
                guard let date = url.creationDate else { return false }
                return date >= weekAgo
            }
        }
        
        if !searchText.isEmpty {
            urls = urls.filter { $0.lastPathComponent.localizedCaseInsensitiveContains(searchText) }
        }
        
        return urls
    }
    
    var body: some View {
        NavigationSplitView {
            // Sidebar: Native List for proper scroll edge effect and transparency
            List(selection: $selectedRecording) {
                Section {
                    ForEach(filteredURLs, id: \.absoluteString) { url in
                        NavigationLink(value: url) {
                            RecordingListRow(
                                url: url,
                                hasTranscript: hasTranscript(for: url),
                                isRecording: recorder.currentRecordingURL == url
                            )
                        }
                    }
                } header: {
                    HStack {
                        Text("Recordings")
                            .font(.headline)
                        Spacer()
                        filterMenu
                    }
                    .textCase(nil)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 380)
            .safeAreaInset(edge: .bottom) {
                floatingActionBar
                    .padding(.bottom, 12)
            }
            .overlay {
                if filteredURLs.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No recordings yet" : "No matches",
                        systemImage: "waveform",
                        description: Text(searchText.isEmpty ? "Start recording to see items here" : "Try a different search")
                    )
                }
            }
            .onChange(of: selectedRecording) { _, newValue in
                if newValue != nil {
                    showSettings = false
                }
            }
        } detail: {
            // Detail: Recording Player or Settings
            if showSettings {
                SettingsDetailView()
            } else if let url = selectedRecording {
                if recorder.currentRecordingURL == url {
                    // Show in-progress recording view
                    RecordingInProgressView(url: url)
                } else {
                    RecordingDetailView(url: url)
                }
            } else {
                ContentUnavailableView("Select a Recording", systemImage: "waveform", description: Text("Choose a recording from the list to view details"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.textBackgroundColor))
            }
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search recordings...")
        .navigationSplitViewStyle(.balanced)
        .preferredColorScheme(isDarkMode ? .dark : .light)
        .onChange(of: recorder.currentRecordingURL) { _, newURL in
            // Auto-select the new recording when recording starts
            if let url = newURL {
                selectedRecording = url
                showSettings = false
            }
        }
    }
    
    private func hasTranscript(for url: URL) -> Bool {
        let transcriptURL = url.deletingPathExtension().appendingPathExtension("md")
        return FileManager.default.fileExists(atPath: transcriptURL.path)
    }
    
    private var filterMenu: some View {
        Menu {
            ForEach(DateFilter.allCases, id: \.rawValue) { filter in
                Button(action: { selectedFilter = filter }) {
                    HStack {
                        Text(filter.rawValue)
                        if selectedFilter == filter {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(selectedFilter.rawValue)
                    .font(.system(size: 11, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
    }
    
    private var floatingActionBar: some View {
        HStack(spacing: 0) {
            // New Recording
            FloatingBarButton(
                icon: "plus",
                action: {
                    Task {
                        await AudioRecorder.shared.startRecording()
                    }
                }
            )
            
            Divider()
                .frame(height: 20)
            
            // Theme Toggle
            FloatingBarButton(
                icon: isDarkMode ? "sun.max" : "moon",
                action: { isDarkMode.toggle() }
            )
            
            Divider()
                .frame(height: 20)
            
            // Settings
            FloatingBarButton(
                icon: "gear",
                isActive: showSettings,
                action: { 
                    showSettings.toggle()
                    if showSettings {
                        selectedRecording = nil
                    }
                }
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 4)
        )
        .overlay(
            Capsule()
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - Recording List Row

struct RecordingListRow: View {
    let url: URL
    let hasTranscript: Bool
    var isRecording: Bool = false
    
    var body: some View {
        HStack(spacing: 10) {
            // Recording indicator or waveform icon
            if isRecording {
                Image(systemName: "record.circle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.red)
                    .symbolEffect(.pulse)
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: "waveform")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.accentColor)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.accentColor.opacity(0.12))
                    )
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(url.deletingPathExtension().lastPathComponent)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    if isRecording {
                        Text("Recording...")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.red)
                    } else {
                        Text(url.shortCreationDate)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    if hasTranscript {
                        Image(systemName: "text.bubble.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.green)
                    }
                }
            }
        }
    }
}

// MARK: - Recording In Progress View

struct RecordingInProgressView: View {
    let url: URL
    @ObservedObject private var recorder = AudioRecorder.shared
    @State private var notesContent: String = ""
    @FocusState private var isNotesFocused: Bool
    
    private var notesURL: URL {
        url.deletingPathExtension().appendingPathExtension("notes")
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Recording status header
            HStack(spacing: 16) {
                // Pulsing record indicator
                Circle()
                    .fill(Color.red)
                    .frame(width: 12, height: 12)
                    .shadow(color: .red.opacity(0.5), radius: 4)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recording in Progress")
                        .font(.headline)
                    
                    HStack(spacing: 8) {
                        Text(recorder.elapsedDisplay)
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundColor(.secondary)
                        
                        Text("•")
                            .foregroundColor(.secondary)
                        
                        Text(recorder.recordingSource.rawValue)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Stop button
                Button(action: {
                    Task {
                        await recorder.stopRecording()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "stop.fill")
                        Text("Stop")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.red)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Audio level visualizer
            AudioLevelBar(level: recorder.audioLevel)
                .frame(height: 6)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            
            Divider()
            
            // Notes editor (main content)
            VStack(alignment: .leading, spacing: 8) {
                Text("Notes")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                TextEditor(text: $notesContent)
                    .font(.system(size: 14))
                    .focused($isNotesFocused)
                    .onChange(of: notesContent) { _, _ in
                        saveNotes()
                    }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Color(NSColor.textBackgroundColor))
        .onAppear {
            loadNotes()
        }
    }
    
    private func loadNotes() {
        if FileManager.default.fileExists(atPath: notesURL.path) {
            notesContent = (try? String(contentsOf: notesURL, encoding: .utf8)) ?? ""
        }
    }
    
    private func saveNotes() {
        try? notesContent.write(to: notesURL, atomically: true, encoding: .utf8)
    }
}

// MARK: - Audio Level Bar

struct AudioLevelBar: View {
    let level: Double
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.1))
                
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.green, .yellow, .red],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * min(1, level * 3))
            }
        }
    }
}

// MARK: - Floating Bar Button

struct FloatingBarButton: View {
    let icon: String
    var isActive: Bool = false
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(isActive ? .accentColor : .primary.opacity(0.7))
                .frame(width: 40, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isHovered || isActive ? Color.primary.opacity(0.08) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Compact Recording Row

struct CompactRecordingRow: View {
    let url: URL
    let isSelected: Bool
    let onSelect: () -> Void
    
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme
    
    private var hasTranscript: Bool {
        let transcriptURL = url.deletingPathExtension().appendingPathExtension("md")
        return FileManager.default.fileExists(atPath: transcriptURL.path)
    }
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                // Compact waveform icon
                Image(systemName: "waveform")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.accentColor)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.accentColor.opacity(0.12))
                    )
                
                // Content - single line with truncation
                VStack(alignment: .leading, spacing: 2) {
                    Text(url.deletingPathExtension().lastPathComponent)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 6) {
                        Text(url.shortCreationDate)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        
                        if hasTranscript {
                            Image(systemName: "text.bubble.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.green)
                        }
                    }
                }
                
                Spacer()
                
                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.4))
                    .opacity(isHovered || isSelected ? 1 : 0.5)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : 
                          isHovered ? Color.primary.opacity(0.04) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Premium Recording Card

struct PremiumRecordingCard: View {
    let url: URL
    let isSelected: Bool
    let onSelect: () -> Void
    
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme
    
    private var hasTranscript: Bool {
        let transcriptURL = url.deletingPathExtension().appendingPathExtension("md")
        return FileManager.default.fileExists(atPath: transcriptURL.path)
    }
    
    private var cardBackground: Color {
        if isSelected {
            return Color.accentColor.opacity(0.15)
        } else if isHovered {
            return colorScheme == .dark ? Color(white: 0.2) : Color.white
        } else {
            return colorScheme == .dark ? Color(white: 0.15) : Color.white
        }
    }
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Waveform icon
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: "waveform")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.accentColor)
                }
                
                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text(url.deletingPathExtension().lastPathComponent)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.system(size: 10))
                            Text(url.creationDateFormatted)
                        }
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        
                        if hasTranscript {
                            HStack(spacing: 3) {
                                Image(systemName: "text.bubble.fill")
                                    .font(.system(size: 9))
                                Text("Transcribed")
                            }
                            .font(.system(size: 10))
                            .foregroundColor(.green)
                        }
                    }
                }
                
                Spacer()
                
                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isSelected ? .accentColor : .secondary.opacity(0.4))
                    .opacity(isHovered || isSelected ? 1 : 0.6)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(cardBackground)
                    .shadow(color: Color.black.opacity(isHovered || isSelected ? 0.08 : 0.04), radius: 6, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Recording Row

struct RecordingRow: View {
    let url: URL
    @State private var isHovered = false
    @State private var isTranscribing = false
    @State private var showingTranscript = false
    @State private var showingError = false
    @State private var transcriptText = ""
    @State private var errorMessage = ""
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(url.deletingPathExtension().lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text(url.creationDateFormatted)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    Text(url.fileSizeFormatted)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if hasTranscript {
                        Text("•")
                            .foregroundColor(.secondary)
                        Image(systemName: "text.bubble.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            }
            
            Spacer()
            
            if isTranscribing {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 20)
            } else if isHovered {
                HStack(spacing: 8) {
                    Button(action: playRecording) {
                        Image(systemName: "play.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                    
                    Button(action: transcribeRecording) {
                        Image(systemName: "text.bubble")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.purple)
                    .help("Transcribe with Deepgram")
                    
                    Button(action: showInFinder) {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    
                    Button(action: deleteRecording) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.red)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .alert("Transcription", isPresented: $showingTranscript) {
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(transcriptText, forType: .string)
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(transcriptText)
        }
        .alert("Transcription Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
    
    private var hasTranscript: Bool {
        let transcriptURL = url.deletingPathExtension().appendingPathExtension("md")
        return FileManager.default.fileExists(atPath: transcriptURL.path)
    }
    
    private func playRecording() {
        NSWorkspace.shared.open(url)
    }
    
    private func showInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    
    private func deleteRecording() {
        try? FileManager.default.removeItem(at: url)
        AudioRecorder.shared.refreshRecordings()
    }
    
    private func transcribeRecording() {
        isTranscribing = true
        
        Task {
            let result = await DeepgramService.shared.transcribe(audioURL: url) { phase in
                // Could update UI with phase here
            }
            
            await MainActor.run {
                isTranscribing = false
                
                if result.success, let text = result.text {
                    transcriptText = text
                    showingTranscript = true
                    
                    // Save transcript to .md file
                    let transcriptURL = url.deletingPathExtension().appendingPathExtension("md")
                    let markdown = generateTranscriptMarkdown(result: result)
                    try? markdown.write(to: transcriptURL, atomically: true, encoding: .utf8)
                } else {
                    errorMessage = result.error ?? "Unknown error"
                    showingError = true
                }
            }
        }
    }
    
    private func generateTranscriptMarkdown(result: TranscriptionResult) -> String {
        var md = "# Transcription\n\n"
        
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
        
        md += "---\n\n"
        md += "## Metadata\n\n"
        md += "- **File:** \(url.lastPathComponent)\n"
        md += "- **Transcribed:** \(Date().formatted())\n"
        md += "- **Service:** Deepgram Nova-2\n"
        
        if let duration = result.duration {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            md += "- **Duration:** \(minutes)m \(seconds)s\n"
        }
        
        return md
    }
    
    private func formatTimestamp(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

// MARK: - Recording Detail View

struct RecordingDetailView: View {
    let url: URL
    
    @StateObject private var player = AudioPlayerController()
    @State private var transcriptContent: String = ""
    @State private var notesContent: String = ""
    @State private var isTranscribing = false
    @State private var isSummarizing = false
    @State private var errorMessage: String?
    @State private var showTranscriptInspector = false
    @State private var summaryContent: String = ""
    @Environment(\.colorScheme) private var colorScheme
    
    private var transcriptURL: URL {
        url.deletingPathExtension().appendingPathExtension("md")
    }
    
    private var notesURL: URL {
        url.deletingPathExtension().appendingPathExtension("notes")
    }
    
    private var hasTranscript: Bool {
        FileManager.default.fileExists(atPath: transcriptURL.path)
    }
    
    private var hasSummary: Bool {
        FileManager.default.fileExists(atPath: summaryURL.path) && !summaryContent.isEmpty
    }
    
    private var summaryURL: URL {
        url.deletingPathExtension().appendingPathExtension("summary")
    }
    
    private var recordingName: String {
        url.deletingPathExtension().lastPathComponent
    }
    
    // Main view mode toggle
    enum MainViewMode: String, CaseIterable {
        case notes = "Notes"
        case summary = "Summary"
    }
    @State private var mainViewMode: MainViewMode = .notes
    
    var body: some View {
        VStack(spacing: 0) {
            // Recording info badges
            recordingInfoHeader
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 12)
            
            Divider()
            
            // Error message if present
            if let error = errorMessage {
                errorBanner(error)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
            }
            
            // Main content: Notes or Summary
            Group {
                if mainViewMode == .notes {
                    notesEditorView
                } else {
                    summaryView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(NSColor.textBackgroundColor))
        .navigationTitle(recordingName)
        .toolbar {
            // Actions group (right side)
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
                
                // Summarize button (only if transcript exists and no summary yet)
                if hasTranscript && !isTranscribing && !hasSummary {
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
                
                Divider()
                
                // Show in Finder
                Button(action: showInFinder) {
                    Label("Show in Finder", systemImage: "folder")
                }
                .help("Show in Finder")
                
                // Share
                ShareLink(item: url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .help("Share Recording")
                
                Divider()
                
                // Transcript inspector toggle
                Button(action: { showTranscriptInspector.toggle() }) {
                    Label("Transcript", systemImage: showTranscriptInspector ? "sidebar.right" : "text.bubble")
                }
                .help(showTranscriptInspector ? "Hide Transcript" : "Show Transcript")
            }
        }
        .safeAreaInset(edge: .bottom) {
            floatingPlayBar
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
        }
        .inspector(isPresented: $showTranscriptInspector) {
            TranscriptInspectorView(
                content: transcriptContent,
                hasTranscript: hasTranscript,
                isTranscribing: isTranscribing,
                onTranscribe: transcribe,
                onCopy: copyTranscript
            )
            .inspectorColumnWidth(min: 280, ideal: 350, max: 500)
        }
        .onAppear {
            loadTranscript()
            loadNotes()
            loadSummary()
            player.load(url: url)
        }
        .onDisappear {
            saveNotes()
            player.stop()
        }
        .onChange(of: url) { _, newURL in
            saveNotes()
            loadTranscript()
            loadNotes()
            loadSummary()
            player.load(url: newURL)
        }
    }
    
    // MARK: - Notes Editor View
    
    private var notesEditorView: some View {
        TextEditor(text: $notesContent)
            .font(.system(size: 14))
            .padding(16)
            .onChange(of: notesContent) { _, _ in
                saveNotes()
            }
    }
    
    // MARK: - Summary View
    
    private var summaryView: some View {
        ScrollView {
            if !summaryContent.isEmpty {
                Text(summaryContent)
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.3))
                    
                    Text("No summary yet")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    if hasTranscript {
                        Text("Click Summarize to generate an AI summary")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.7))
                        
                        Button(action: summarize) {
                            Label("Summarize Now", systemImage: "sparkles")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSummarizing)
                        .padding(.top, 8)
                    } else {
                        Text("Transcribe first to enable summarization")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(60)
            }
        }
    }
    
    // MARK: - Recording Info Header
    
    private var recordingInfoHeader: some View {
        HStack(spacing: 16) {
            Label(url.creationDateFormatted, systemImage: "calendar")
            Label(player.durationDisplay, systemImage: "clock")
            Label(url.fileSizeFormatted, systemImage: "doc")
            
            if hasTranscript {
                Label("Transcribed", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
            
            Spacer()
        }
        .font(.system(size: 12))
        .foregroundColor(.secondary)
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
    
    private var floatingPlayBar: some View {
        HStack(spacing: 12) {
            // Play controls pill
            HStack(spacing: 12) {
                // Current time
                Text(player.currentTimeDisplay)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 45, alignment: .trailing)
                
                // Skip back 15s
                Button(action: { player.skip(by: -15) }) {
                    Image(systemName: "gobackward.15")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .foregroundColor(.primary.opacity(0.6))
                
                // Play/Pause - prominent center button
                Button(action: player.togglePlayPause) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .offset(x: player.isPlaying ? 0 : 1)
                    }
                }
                .buttonStyle(.plain)
                
                // Skip forward 15s
                Button(action: { player.skip(by: 15) }) {
                    Image(systemName: "goforward.15")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .foregroundColor(.primary.opacity(0.6))
                
                // Remaining time
                Text("-\(player.remainingTimeDisplay)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 45, alignment: .leading)
                
                // Progress bar
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
                        .frame(width: 28)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .shadow(color: Color.black.opacity(0.1), radius: 12, x: 0, y: 3)
            )
            .overlay(
                Capsule()
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
            
            // View toggle pill (only show when summary exists)
            if hasSummary {
                HStack(spacing: 4) {
                    Button(action: { mainViewMode = .notes }) {
                        Image(systemName: "note.text")
                            .font(.system(size: 13, weight: mainViewMode == .notes ? .semibold : .regular))
                            .foregroundColor(mainViewMode == .notes ? .accentColor : .secondary)
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(mainViewMode == .notes ? Color.accentColor.opacity(0.15) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Notes")
                    
                    Button(action: { mainViewMode = .summary }) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: mainViewMode == .summary ? .semibold : .regular))
                            .foregroundColor(mainViewMode == .summary ? .accentColor : .secondary)
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(mainViewMode == .summary ? Color.accentColor.opacity(0.15) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Summary")
                }
                .padding(4)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .shadow(color: Color.black.opacity(0.1), radius: 12, x: 0, y: 3)
                )
                .overlay(
                    Capsule()
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
            }
        }
    }
    
    private func loadTranscript() {
        if hasTranscript {
            transcriptContent = (try? String(contentsOf: transcriptURL, encoding: .utf8)) ?? ""
        } else {
            transcriptContent = ""
        }
    }
    
    private func loadNotes() {
        if FileManager.default.fileExists(atPath: notesURL.path) {
            notesContent = (try? String(contentsOf: notesURL, encoding: .utf8)) ?? ""
        } else {
            notesContent = ""
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
        if notesContent.isEmpty {
            // Delete the file if notes are empty
            try? FileManager.default.removeItem(at: notesURL)
        } else {
            try? notesContent.write(to: notesURL, atomically: true, encoding: .utf8)
        }
    }
    
    private func showInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    
    private func copyTranscript() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcriptContent, forType: .string)
    }
    
    private func summarize() {
        guard hasTranscript else { return }
        
        isSummarizing = true
        errorMessage = nil
        
        Task {
            // Extract plain text from the markdown transcript
            let plainText = transcriptContent
                .components(separatedBy: "\n")
                .filter { !$0.hasPrefix("**[") && !$0.hasPrefix("---") && !$0.hasPrefix("##") && !$0.hasPrefix("- **") }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            let result = await OpenAIService.shared.summarize(transcript: plainText)
            
            await MainActor.run {
                isSummarizing = false
                
                if result.success, let summary = result.summary {
                    // Save summary to separate file
                    summaryContent = summary
                    try? summary.write(to: summaryURL, atomically: true, encoding: .utf8)
                    mainViewMode = .summary  // Switch to summary view
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
            let result = await DeepgramService.shared.transcribe(audioURL: url) { _ in }
            
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

// MARK: - Transcript Inspector View

struct TranscriptInspectorView: View {
    let content: String
    let hasTranscript: Bool
    let isTranscribing: Bool
    let onTranscribe: () -> Void
    let onCopy: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Transcript")
                    .font(.headline)
                
                Spacer()
                
                if hasTranscript {
                    Button(action: onCopy) {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    .help("Copy Transcript")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            
            Divider()
            
            // Content
            if isTranscribing {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Transcribing...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if hasTranscript {
                ScrollView {
                    TranscriptTextView(content: content)
                        .padding()
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary.opacity(0.3))
                    
                    Text("No transcript yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Button(action: onTranscribe) {
                        Label("Transcribe", systemImage: "waveform.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
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

// MARK: - Settings Detail View

struct SettingsDetailView: View {
    @AppStorage("defaultSource") private var defaultSource = "Microphone"
    @AppStorage("autoOpenFolder") private var autoOpenFolder = false
    @AppStorage("showInDock") private var showInDock = false
    @AppStorage("autoTranscribe") private var autoTranscribe = false
    
    // Deepgram Settings
    @AppStorage("deepgramApiKey") private var deepgramApiKey = ""
    
    // R2 Settings
    @AppStorage("r2AccountId") private var r2AccountId = ""
    @AppStorage("r2AccessKeyId") private var r2AccessKeyId = ""
    @AppStorage("r2SecretAccessKey") private var r2SecretAccessKey = ""
    @AppStorage("r2BucketName") private var r2BucketName = ""
    @AppStorage("r2PublicUrl") private var r2PublicUrl = ""
    
    @State private var showingApiKey = false
    @State private var showingR2Secret = false
    
    var body: some View {
        Form {
            Section("Recording") {
                Picker("Default Source", selection: $defaultSource) {
                    Text("Microphone").tag("Microphone")
                    Text("System Audio").tag("System Audio")
                    Text("Mic + System").tag("Mic + System")
                }
                .pickerStyle(.menu)
                
                Toggle("Open recordings folder after recording", isOn: $autoOpenFolder)
            }
            
            Section("Transcription") {
                Toggle("Auto-transcribe after recording", isOn: $autoTranscribe)
                    .disabled(deepgramApiKey.isEmpty)
                
                HStack {
                    if showingApiKey {
                        TextField("Deepgram API Key", text: $deepgramApiKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("Deepgram API Key", text: $deepgramApiKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button {
                        showingApiKey.toggle()
                    } label: {
                        Image(systemName: showingApiKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.plain)
                }
                
                if deepgramApiKey.isEmpty {
                    Text("Get your API key at [deepgram.com](https://deepgram.com)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Section("AI Summarization") {
                HStack {
                    SecureField("OpenAI API Key", text: Binding(
                        get: { UserDefaults.standard.string(forKey: "openaiApiKey") ?? "" },
                        set: { UserDefaults.standard.set($0, forKey: "openaiApiKey") }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
                
                if (UserDefaults.standard.string(forKey: "openaiApiKey") ?? "").isEmpty {
                    Text("Get your API key at [platform.openai.com](https://platform.openai.com)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Label("OpenAI Configured", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                }
            }
            
            Section("Cloudflare R2 Storage") {
                Text("Required for transcribing large audio files (>10MB)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                TextField("Account ID", text: $r2AccountId)
                    .textFieldStyle(.roundedBorder)
                
                TextField("Access Key ID", text: $r2AccessKeyId)
                    .textFieldStyle(.roundedBorder)
                
                HStack {
                    if showingR2Secret {
                        TextField("Secret Access Key", text: $r2SecretAccessKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("Secret Access Key", text: $r2SecretAccessKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button {
                        showingR2Secret.toggle()
                    } label: {
                        Image(systemName: showingR2Secret ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.plain)
                }
                
                TextField("Bucket Name", text: $r2BucketName)
                    .textFieldStyle(.roundedBorder)
                
                TextField("Public URL", text: $r2PublicUrl)
                    .textFieldStyle(.roundedBorder)
                
                if !r2AccountId.isEmpty && !r2AccessKeyId.isEmpty && !r2SecretAccessKey.isEmpty && !r2BucketName.isEmpty && !r2PublicUrl.isEmpty {
                    Label("R2 Configured", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                } else {
                    Text("Set up R2 at [dash.cloudflare.com](https://dash.cloudflare.com)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Section("Appearance") {
                Toggle("Show in Dock", isOn: $showInDock)
                    .onChange(of: showInDock) { _, newValue in
                        NSApp.setActivationPolicy(newValue ? .regular : .accessory)
                    }
            }
            
            Section("Storage") {
                LabeledContent("Location") {
                    Text("~/Documents/Repen Menu/Recordings")
                        .foregroundColor(.secondary)
                }
                
                Button("Open Recordings Folder") {
                    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                    let folder = docs.appendingPathComponent("Repen Menu/Recordings")
                    NSWorkspace.shared.open(folder)
                }
            }
            
            Section("About") {
                LabeledContent("Version") {
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - URL Extensions

private extension URL {
    var creationDate: Date? {
        try? FileManager.default.attributesOfItem(atPath: path)[.creationDate] as? Date
    }
    
    var creationDateFormatted: String {
        guard let date = creationDate else { return "Unknown" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    var shortCreationDate: String {
        guard let date = creationDate else { return "Unknown" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    var fileSizeFormatted: String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int64 else { return "Unknown" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}
