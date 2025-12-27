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
    func summarize(transcript: String, documentTitle: String, date: Date) async -> SummaryResult {
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
        
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        let dateString = formatter.string(from: date)
        
        do {
            let url = URL(string: "https://api.openai.com/v1/chat/completions")!
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 60
            
            let systemPrompt = """
            You are a professional meeting assistant that provides highly accurate, structured summaries of transcripts.
            
            TRANSCRIPT DETAILS:
            Title: \(documentTitle)
            Date: \(dateString)
            
            CRITICAL INSTRUCTIONS:
            1. DO NOT include placeholders like "[Insert Date]", "[Insert Names]", or "[Meeting Summary]".
            2. DO NOT start with "## AI Summary" or any variation of that header.
            3. If you don't know the exact attendees, omit that section or list "Mentioned Participants".
            4. Use only the Markdown structure provided below.
            
            STRUCTURE:
            # [Create a better title if the current one is generic]
            
            ## Overview
            2-3 sentence executive summary.
            
            ## Key Discussion Points
            - Broad topics and specific decisions
            - Use bullet points
            
            ## Action Items & Next Steps
            - Tasks assigned to specific people (if mentioned)
            - Deadlines or milestones
            
            ## Notable Quotes
            > "Full quote here" - Speaker (if known)
            
            Format everything in clean Markdown. Be concise and professional.
            """
            
            let body: [String: Any] = [
                "model": "gpt-4o-mini",
                "messages": [
                    ["role": "system", "content": systemPrompt],
                    ["role": "user", "content": "Transcript to summarize:\n\n\(transcript)"]
                ],
                "temperature": 0.3
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
