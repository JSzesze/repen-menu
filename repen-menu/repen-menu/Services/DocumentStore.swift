import Foundation
import SwiftUI
import Combine

// MARK: - Document Model

struct Document: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var createdAt: Date
    var modifiedAt: Date
    
    // File references (optional - document may not have all)
    var hasRecording: Bool
    var hasTranscript: Bool
    var hasSummary: Bool
    
    init(id: String = UUID().uuidString, title: String, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.modifiedAt = createdAt
        self.hasRecording = false
        self.hasTranscript = false
        self.hasSummary = false
    }
    
    // MARK: - File URLs
    
    // MARK: - File URLs
    
    func folderURL(in rootFolder: URL) -> URL {
        rootFolder.appendingPathComponent(id, isDirectory: true)
    }
    
    func manifestURL(in rootFolder: URL) -> URL {
        folderURL(in: rootFolder).appendingPathComponent("manifest.json")
    }
    
    func audioURL(in rootFolder: URL) -> URL {
        folderURL(in: rootFolder).appendingPathComponent("audio.wav")
    }
    
    func transcriptURL(in rootFolder: URL) -> URL {
        folderURL(in: rootFolder).appendingPathComponent("transcript.md")
    }
    
    func summaryURL(in rootFolder: URL) -> URL {
        folderURL(in: rootFolder).appendingPathComponent("summary.md")
    }
    
    func notesURL(in rootFolder: URL) -> URL {
        folderURL(in: rootFolder).appendingPathComponent("notes.md")
    }
}

// MARK: - Document Store

@MainActor
final class DocumentStore: ObservableObject {
    static let shared = DocumentStore()
    
    @Published var documents: [Document] = []
    
    private let fm = FileManager.default
    
    var folderURL: URL {
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("Repen Menu/Documents", isDirectory: true)
    }
    
    // Legacy folder for migration
    private var legacyFolderURL: URL {
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("Repen Menu/Recordings", isDirectory: true)
    }
    
    private init() {
        ensureFolderExists()
        migrateLegacyFolder()
        migrateFlatFilesToFolders() // New migration
        refresh()
    }
    
    // MARK: - Public API
    
    func refresh() {
        documents = loadDocuments()
    }
    
    /// Create a new document (notes-only)
    func createDocument(title: String) -> Document {
        let doc = Document(title: title)
        
        // Create folder
        try? fm.createDirectory(at: doc.folderURL(in: folderURL), withIntermediateDirectories: true)
        
        // Create empty notes file
        let notesURL = doc.notesURL(in: folderURL)
        try? "".write(to: notesURL, atomically: true, encoding: .utf8)
        
        save(doc)
        refresh()
        return doc
    }
    
    /// Create a document for a new recording
    func createDocumentForRecording() -> Document {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy h:mm a"
        let title = "Recording - \(formatter.string(from: Date()))"
        
        var doc = Document(title: title)
        doc.hasRecording = true
        
        // Create folder
        try? fm.createDirectory(at: doc.folderURL(in: folderURL), withIntermediateDirectories: true)
        
        // Create empty notes file
        let notesURL = doc.notesURL(in: folderURL)
        try? "".write(to: notesURL, atomically: true, encoding: .utf8)
        
        save(doc)
        refresh()
        return doc
    }
    
    func save(_ document: Document) {
        var doc = document
        doc.modifiedAt = Date()
        
        let url = doc.manifestURL(in: folderURL)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        
        if let data = try? encoder.encode(doc) {
            try? data.write(to: url)
        }
    }
    
    func delete(_ document: Document) {
        // Delete the entire document folder
        try? fm.removeItem(at: document.folderURL(in: folderURL))
        refresh()
    }
    
    func updateFlags(for document: Document) {
        var doc = document
        doc.hasRecording = fm.fileExists(atPath: doc.audioURL(in: folderURL).path)
        doc.hasTranscript = fm.fileExists(atPath: doc.transcriptURL(in: folderURL).path)
        doc.hasSummary = fm.fileExists(atPath: doc.summaryURL(in: folderURL).path)
        save(doc)
    }
    
    func updateTitle(for document: Document, newTitle: String) {
        var doc = document
        doc.title = newTitle
        doc.modifiedAt = Date()
        save(doc)
        refresh()
    }
    
    // MARK: - Private
    
    private func ensureFolderExists() {
        if !fm.fileExists(atPath: folderURL.path) {
            try? fm.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }
    }
    
    private func loadDocuments() -> [Document] {
        // 1. Get all subdirectories in the main Documents folder
        guard let items = try? fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return []
        }
        
        var docs: [Document] = []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        for item in items {
            // Check if directory
            let resourceValues = try? item.resourceValues(forKeys: [.isDirectoryKey])
            if resourceValues?.isDirectory == true {
                // Look for manifest.json inside
                let manifestURL = item.appendingPathComponent("manifest.json")
                if let data = try? Data(contentsOf: manifestURL),
                   var doc = try? decoder.decode(Document.self, from: data) {
                    
                    // Update flags based on actual files in the folder
                    doc.hasRecording = fm.fileExists(atPath: doc.audioURL(in: folderURL).path)
                    doc.hasTranscript = fm.fileExists(atPath: doc.transcriptURL(in: folderURL).path)
                    doc.hasSummary = fm.fileExists(atPath: doc.summaryURL(in: folderURL).path)
                    
                    docs.append(doc)
                }
            }
        }
        
        return docs.sorted { $0.modifiedAt > $1.modifiedAt }
    }
    
    // Flag check helper removed as we now check for file existence directly in updateFlags

    
    // MARK: - Migration
    
    /// Migrates from "Repen Menu/Recordings" (v1) to "Repen Menu/Documents" (v2 flat)
    private func migrateLegacyFolder() {
        guard fm.fileExists(atPath: legacyFolderURL.path) else { return }
        guard let files = try? fm.contentsOfDirectory(at: legacyFolderURL, includingPropertiesForKeys: [.creationDateKey]) else { return }
        
        // Find all .wav files in legacy folder
        let wavFiles = files.filter { $0.pathExtension == "wav" }
        
        for wavURL in wavFiles {
            let basename = wavURL.deletingPathExtension().lastPathComponent
            
            // Legacy check (title match)
            let checkManifests = documents.first { $0.title == basename }
            if checkManifests != nil { continue }
            
            // Create document object
            let creationDate = (try? wavURL.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
            var doc = Document(title: basename, createdAt: creationDate)
            doc.hasRecording = true
            
            // Create folder for it
            try? fm.createDirectory(at: doc.folderURL(in: folderURL), withIntermediateDirectories: true)
            
            // Legacy files
            let legacyMd = legacyFolderURL.appendingPathComponent("\(basename).md")
            let legacyNotes = legacyFolderURL.appendingPathComponent("\(basename).notes")
            
            // Move files to new folder structure
            try? fm.moveItem(at: wavURL, to: doc.audioURL(in: folderURL))
            
            if fm.fileExists(atPath: legacyMd.path) {
                try? fm.moveItem(at: legacyMd, to: doc.transcriptURL(in: folderURL))
                doc.hasTranscript = true
            }
            
            if fm.fileExists(atPath: legacyNotes.path) {
                try? fm.moveItem(at: legacyNotes, to: doc.notesURL(in: folderURL))
            } else {
                try? "".write(to: doc.notesURL(in: folderURL), atomically: true, encoding: .utf8)
            }
            
            save(doc)
        }
    }

    /// Migrates from "Repen Menu/Documents" (flat files) to "Repen Menu/Documents/{id}/" (folders)
    private func migrateFlatFilesToFolders() {
        guard let files = try? fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil) else { return }
        
        // Find all flat manifest files: {id}.json
        let manifests = files.filter { $0.pathExtension == "json" }
        
        for manifest in manifests {
            let id = manifest.deletingPathExtension().lastPathComponent
            
            // Ignore if it is NOT a UUID
            guard UUID(uuidString: id) != nil else { continue }
            
            let docFolder = folderURL.appendingPathComponent(id, isDirectory: true)
            
            // Create folder if needed
            if !fm.fileExists(atPath: docFolder.path) {
                try? fm.createDirectory(at: docFolder, withIntermediateDirectories: true)
            }
            
            // Helper to move file
            func moveFile(ext: String, destName: String) {
                let flatURL = folderURL.appendingPathComponent("\(id).\(ext)")
                if fm.fileExists(atPath: flatURL.path) {
                    let destURL = docFolder.appendingPathComponent(destName)
                    try? fm.moveItem(at: flatURL, to: destURL)
                }
            }
            
            // Move items
            // 1. Manifest: {id}.json -> manifest.json
            let destManifest = docFolder.appendingPathComponent("manifest.json")
            if !fm.fileExists(atPath: destManifest.path) {
                try? fm.moveItem(at: manifest, to: destManifest)
            } else {
                try? fm.removeItem(at: manifest)
            }
            
            // 2. Audio: {id}.wav -> audio.wav
            moveFile(ext: "wav", destName: "audio.wav")
            
            // 3. Transcript: {id}.md -> transcript.md
            moveFile(ext: "md", destName: "transcript.md")
            
            // 4. Summary: {id}.summary.md -> summary.md
            let flatSummary = folderURL.appendingPathComponent("\(id).summary.md")
            if fm.fileExists(atPath: flatSummary.path) {
                try? fm.moveItem(at: flatSummary, to: docFolder.appendingPathComponent("summary.md"))
            }
            
            // 5. Notes: {id}.notes.md -> notes.md
            let flatNotesMd = folderURL.appendingPathComponent("\(id).notes.md")
            if fm.fileExists(atPath: flatNotesMd.path) {
                try? fm.moveItem(at: flatNotesMd, to: docFolder.appendingPathComponent("notes.md"))
            } else {
                // Check for really old {id}.notes (no md)
                let flatNotesOld = folderURL.appendingPathComponent("\(id).notes")
                if fm.fileExists(atPath: flatNotesOld.path) {
                    try? fm.moveItem(at: flatNotesOld, to: docFolder.appendingPathComponent("notes.md"))
                }
            }
        }
    }
}
