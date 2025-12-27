import Foundation

// MARK: - URL Extensions

extension URL {
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
