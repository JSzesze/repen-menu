import SwiftUI
import AppKit

// MARK: - Main Window View

struct MainWindowView: View {
    @State private var selectedFilter: DateFilter = .all
    @State private var selectedDocument: Document?
    @State private var showSettings = false
    @State private var searchText = ""
    @AppStorage("isDarkMode") private var isDarkMode = false
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @ObservedObject private var store = DocumentStore.shared
    @ObservedObject private var recorder = AudioRecorder.shared
    
    enum DateFilter: String, CaseIterable {
        case all = "All"
        case today = "Today"
        case thisWeek = "This Week"
    }
    
    var filteredDocuments: [Document] {
        var docs = store.documents
        
        let calendar = Calendar.current
        let now = Date()
        
        switch selectedFilter {
        case .all:
            break
        case .today:
            docs = docs.filter { calendar.isDateInToday($0.createdAt) }
        case .thisWeek:
            let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
            docs = docs.filter { $0.createdAt >= weekAgo }
        }
        
        if !searchText.isEmpty {
            docs = docs.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        }
        
        return docs
    }
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarView
        } detail: {
            contentDetailView
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search documents...")
        .navigationSplitViewStyle(.balanced)
        .preferredColorScheme(isDarkMode ? .dark : .light)
        .onChange(of: recorder.currentDocument) { _, newDoc in
            // Auto-select the new document when recording starts
            if let doc = newDoc {
                selectedDocument = doc
                showSettings = false
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: toggleSidebar) {
                    Image(systemName: "sidebar.left")
                }
                .help("Toggle Sidebar")
            }
        }
    }
    
    private func toggleSidebar() {
        withAnimation {
            if columnVisibility == .detailOnly {
                columnVisibility = .all
            } else {
                columnVisibility = .detailOnly
            }
        }
    }
    
    @ViewBuilder
    private var sidebarView: some View {
        sidebarList
            .onChange(of: selectedDocument) { _, newValue in
                if newValue != nil {
                    showSettings = false
                }
            }
    }
    
    @ViewBuilder
    private var sidebarList: some View {
        let docs: [Document] = filteredDocuments
        
        List(selection: $selectedDocument) {
            Section {
                ForEach(docs, id: \.id) { doc in
                    NavigationLink(value: doc) {
                        DocumentListRow(
                            document: doc,
                            isRecording: recorder.currentDocument?.id == doc.id
                        )
                    }
                }
            } header: {
                HStack {
                    Text("Documents")
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
            if docs.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No documents yet" : "No matches",
                    systemImage: "doc.text",
                    description: Text(searchText.isEmpty ? "Create a new document or start recording" : "Try a different search")
                )
            }
        }
    }
    
    @ViewBuilder
    private var contentDetailView: some View {
        Group {
            if showSettings {
                SettingsDetailView()
            } else if let doc = selectedDocument {
                DocumentDetailView(document: doc)
                    .id(doc.id)
            } else {
                ContentUnavailableView(
                    "Select a Document",
                    systemImage: "doc.text",
                    description: Text("Choose a document from the list to view details")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.textBackgroundColor))
            }
        }
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
            // New Document
            FloatingBarButton(
                icon: "plus",
                action: {
                    let doc = DocumentStore.shared.createDocument(title: "Untitled")
                    selectedDocument = doc
                    showSettings = false
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
                        selectedDocument = nil
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
