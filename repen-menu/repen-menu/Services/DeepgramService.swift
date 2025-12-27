import Foundation

// MARK: - Deepgram Configuration

struct DeepgramConfiguration: Sendable {
    let apiKey: String
    
    var isConfigured: Bool {
        !apiKey.isEmpty
    }
    
    @MainActor
    static func load() -> DeepgramConfiguration {
        DeepgramConfiguration(
            apiKey: UserDefaults.standard.string(forKey: "deepgramApiKey") ?? ""
        )
    }
    
    @MainActor
    func save() {
        UserDefaults.standard.set(apiKey, forKey: "deepgramApiKey")
    }
}

// MARK: - Transcription Result

struct TranscriptionResult {
    let success: Bool
    let text: String?
    let error: String?
    let duration: Double?
    let segments: [TranscriptionSegment]?
}

struct TranscriptionSegment {
    let text: String
    let start: Double
    let end: Double
}

// MARK: - Transcription Progress

enum TranscriptionPhase {
    case uploading(percent: Int)
    case transcribing
    case completed
    case failed(error: String)
}

// MARK: - Deepgram Service

actor DeepgramService {
    static let shared = DeepgramService()
    
    // Size threshold for using R2 upload (10MB - be conservative)
    private let largeFileThreshold: Int64 = 10 * 1024 * 1024
    
    private init() {}
    
    // MARK: - Public API
    
    /// Transcribe an audio file using Deepgram
    /// For large files, uploads to R2 first and sends URL to Deepgram
    func transcribe(
        audioURL: URL,
        onProgress: (@Sendable (TranscriptionPhase) -> Void)? = nil
    ) async -> TranscriptionResult {
        let config = await MainActor.run { DeepgramConfiguration.load() }
        
        guard config.isConfigured else {
            return TranscriptionResult(
                success: false,
                text: nil,
                error: "Deepgram API key not configured. Please set it in settings.",
                duration: nil,
                segments: nil
            )
        }
        
        do {
            let fileSize = try FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as? Int64 ?? 0
            
            print("[Deepgram] Starting transcription for: \(audioURL.lastPathComponent)")
            print("[Deepgram] File size: \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))")
            
            if fileSize > largeFileThreshold {
                // Large file - upload to R2 first
                print("[Deepgram] Large file detected, using R2 upload strategy")
                return await transcribeViaR2(audioURL: audioURL, config: config, onProgress: onProgress)
            } else {
                // Small file - direct upload to Deepgram
                print("[Deepgram] Using direct upload strategy")
                return await transcribeDirect(audioURL: audioURL, config: config, onProgress: onProgress)
            }
        } catch {
            return TranscriptionResult(
                success: false,
                text: nil,
                error: error.localizedDescription,
                duration: nil,
                segments: nil
            )
        }
    }
    
    // MARK: - Private Methods
    
    /// Direct upload to Deepgram for smaller files
    private func transcribeDirect(
        audioURL: URL,
        config: DeepgramConfiguration,
        onProgress: (@Sendable (TranscriptionPhase) -> Void)?
    ) async -> TranscriptionResult {
        do {
            onProgress?(.uploading(percent: 0))
            
            let audioData = try Data(contentsOf: audioURL)
            
            onProgress?(.uploading(percent: 50))
            
            var urlComponents = URLComponents(string: "https://api.deepgram.com/v1/listen")!
            urlComponents.queryItems = [
                URLQueryItem(name: "model", value: "nova-2"),
                URLQueryItem(name: "smart_format", value: "true"),
                URLQueryItem(name: "punctuate", value: "true"),
                URLQueryItem(name: "utterances", value: "true"),
                URLQueryItem(name: "paragraphs", value: "true")
            ]
            
            var request = URLRequest(url: urlComponents.url!)
            request.httpMethod = "POST"
            request.httpBody = audioData
            request.setValue("Token \(config.apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue(getContentType(for: audioURL), forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 300 // 5 minute timeout
            
            onProgress?(.transcribing)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            return parseDeepgramResponse(data: data, response: response, onProgress: onProgress)
        } catch {
            onProgress?(.failed(error: error.localizedDescription))
            return TranscriptionResult(
                success: false,
                text: nil,
                error: error.localizedDescription,
                duration: nil,
                segments: nil
            )
        }
    }
    
    /// Upload to R2 first, then send URL to Deepgram
    private func transcribeViaR2(
        audioURL: URL,
        config: DeepgramConfiguration,
        onProgress: (@Sendable (TranscriptionPhase) -> Void)?
    ) async -> TranscriptionResult {
        // Check if R2 is configured
        let r2Config = await MainActor.run { R2Configuration.load() }
        guard r2Config.isConfigured else {
            return TranscriptionResult(
                success: false,
                text: nil,
                error: "Large file detected but R2 storage is not configured. Please set up R2 credentials in settings.",
                duration: nil,
                segments: nil
            )
        }
        
        // Upload to R2
        let uploadResult: R2UploadResult
        do {
            uploadResult = try await R2UploadService.shared.uploadFile(at: audioURL) { progress in
                onProgress?(.uploading(percent: progress.percent))
            }
        } catch {
            let message = error.localizedDescription
            onProgress?(.failed(error: message))
            return TranscriptionResult(
                success: false,
                text: nil,
                error: "Failed to upload to R2: \(message)",
                duration: nil,
                segments: nil
            )
        }
        
        guard uploadResult.success, let r2Url = uploadResult.url else {
            onProgress?(.failed(error: uploadResult.error ?? "R2 upload failed"))
            return TranscriptionResult(
                success: false,
                text: nil,
                error: "Failed to upload to R2: \(uploadResult.error ?? "Unknown error")",
                duration: nil,
                segments: nil
            )
        }
        
        print("[Deepgram] R2 upload successful! URL: \(r2Url)")
        
        // Now send URL to Deepgram
        onProgress?(.transcribing)
        
        do {
            var urlComponents = URLComponents(string: "https://api.deepgram.com/v1/listen")!
            urlComponents.queryItems = [
                URLQueryItem(name: "model", value: "nova-2"),
                URLQueryItem(name: "smart_format", value: "true"),
                URLQueryItem(name: "punctuate", value: "true"),
                URLQueryItem(name: "utterances", value: "true"),
                URLQueryItem(name: "paragraphs", value: "true")
            ]
            
            var request = URLRequest(url: urlComponents.url!)
            request.httpMethod = "POST"
            request.setValue("Token \(config.apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 600 // 10 minute timeout for large files
            
            let body = ["url": r2Url]
            request.httpBody = try JSONEncoder().encode(body)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            return parseDeepgramResponse(data: data, response: response, onProgress: onProgress)
        } catch {
            onProgress?(.failed(error: error.localizedDescription))
            return TranscriptionResult(
                success: false,
                text: nil,
                error: error.localizedDescription,
                duration: nil,
                segments: nil
            )
        }
    }
    
    /// Parse Deepgram API response
    private func parseDeepgramResponse(
        data: Data,
        response: URLResponse,
        onProgress: (@Sendable (TranscriptionPhase) -> Void)?
    ) -> TranscriptionResult {
        guard let httpResponse = response as? HTTPURLResponse else {
            onProgress?(.failed(error: "Invalid response"))
            return TranscriptionResult(
                success: false,
                text: nil,
                error: "Invalid response from Deepgram",
                duration: nil,
                segments: nil
            )
        }
        
        if httpResponse.statusCode != 200 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("[Deepgram] API error: \(httpResponse.statusCode) - \(errorMessage)")
            onProgress?(.failed(error: errorMessage))
            return TranscriptionResult(
                success: false,
                text: nil,
                error: "Deepgram API error: HTTP \(httpResponse.statusCode)",
                duration: nil,
                segments: nil
            )
        }
        
        do {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            // Extract transcript
            let results = json?["results"] as? [String: Any]
            let channels = results?["channels"] as? [[String: Any]]
            let alternatives = channels?.first?["alternatives"] as? [[String: Any]]
            let transcript = alternatives?.first?["transcript"] as? String ?? ""
            
            // Extract metadata
            let metadata = json?["metadata"] as? [String: Any]
            let duration = metadata?["duration"] as? Double
            
            // Extract segments from paragraphs or utterances
            var segments: [TranscriptionSegment] = []
            
            if let paragraphs = alternatives?.first?["paragraphs"] as? [String: Any],
               let paragraphsList = paragraphs["paragraphs"] as? [[String: Any]] {
                for paragraph in paragraphsList {
                    let sentences = paragraph["sentences"] as? [[String: Any]] ?? []
                    let text = sentences.compactMap { $0["text"] as? String }.joined(separator: " ")
                    let start = paragraph["start"] as? Double ?? 0
                    let end = paragraph["end"] as? Double ?? 0
                    segments.append(TranscriptionSegment(text: text, start: start, end: end))
                }
            } else if let utterances = results?["utterances"] as? [[String: Any]] {
                for utterance in utterances {
                    let text = utterance["transcript"] as? String ?? ""
                    let start = utterance["start"] as? Double ?? 0
                    let end = utterance["end"] as? Double ?? 0
                    segments.append(TranscriptionSegment(text: text, start: start, end: end))
                }
            }
            
            print("[Deepgram] ✅ Transcription successful!")
            print("[Deepgram] Duration: \(duration ?? 0)s, Segments: \(segments.count)")
            
            onProgress?(.completed)
            
            return TranscriptionResult(
                success: true,
                text: transcript,
                error: nil,
                duration: duration,
                segments: segments.isEmpty ? nil : segments
            )
        } catch {
            print("[Deepgram] Failed to parse response: \(error)")
            onProgress?(.failed(error: error.localizedDescription))
            return TranscriptionResult(
                success: false,
                text: nil,
                error: "Failed to parse Deepgram response: \(error.localizedDescription)",
                duration: nil,
                segments: nil
            )
        }
    }
    
    private func getContentType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "wav": return "audio/wav"
        case "mp3": return "audio/mpeg"
        case "m4a": return "audio/mp4"
        case "webm": return "audio/webm"
        default: return "application/octet-stream"
        }
    }
}

