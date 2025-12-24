import Foundation

// MARK: - OpenAI Configuration

struct OpenAIConfiguration: Sendable {
    let apiKey: String
    
    var isConfigured: Bool {
        !apiKey.isEmpty
    }
    
    @MainActor
    static func load() -> OpenAIConfiguration {
        OpenAIConfiguration(
            apiKey: UserDefaults.standard.string(forKey: "openaiApiKey") ?? ""
        )
    }
    
    @MainActor
    func save() {
        UserDefaults.standard.set(apiKey, forKey: "openaiApiKey")
    }
}

// MARK: - Summary Result

struct SummaryResult {
    let success: Bool
    let summary: String?
    let error: String?
}

// MARK: - OpenAI Service

actor OpenAIService {
    static let shared = OpenAIService()
    
    private init() {}
    
    /// Summarize a transcript using OpenAI
    func summarize(transcript: String) async -> SummaryResult {
        let config = await MainActor.run { OpenAIConfiguration.load() }
        
        guard config.isConfigured else {
            return SummaryResult(
                success: false,
                summary: nil,
                error: "OpenAI API key not configured. Please set it in settings."
            )
        }
        
        guard !transcript.isEmpty else {
            return SummaryResult(
                success: false,
                summary: nil,
                error: "No transcript to summarize."
            )
        }
        
        do {
            let url = URL(string: "https://api.openai.com/v1/chat/completions")!
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 60
            
            let systemPrompt = """
            You are a helpful assistant that summarizes meeting transcripts and audio recordings.
            Provide a clear, concise summary that captures:
            - Key topics discussed
            - Important decisions or action items
            - Notable quotes or statements
            Keep the summary organized and easy to scan.
            """
            
            let body: [String: Any] = [
                "model": "gpt-4o-mini",
                "messages": [
                    ["role": "system", "content": systemPrompt],
                    ["role": "user", "content": "Please summarize this transcript:\n\n\(transcript)"]
                ],
                "max_tokens": 1000,
                "temperature": 0.5
            ]
            
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            print("[OpenAI] Sending transcript for summarization...")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return SummaryResult(success: false, summary: nil, error: "Invalid response")
            }
            
            if httpResponse.statusCode != 200 {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("[OpenAI] API error: \(httpResponse.statusCode) - \(errorMessage)")
                return SummaryResult(
                    success: false,
                    summary: nil,
                    error: "OpenAI API error: HTTP \(httpResponse.statusCode)"
                )
            }
            
            // Parse response
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let choices = json?["choices"] as? [[String: Any]]
            let message = choices?.first?["message"] as? [String: Any]
            let content = message?["content"] as? String
            
            print("[OpenAI] ✅ Summary generated successfully!")
            
            return SummaryResult(
                success: true,
                summary: content?.trimmingCharacters(in: .whitespacesAndNewlines),
                error: nil
            )
        } catch {
            print("[OpenAI] Error: \(error.localizedDescription)")
            return SummaryResult(
                success: false,
                summary: nil,
                error: error.localizedDescription
            )
        }
    }
}
