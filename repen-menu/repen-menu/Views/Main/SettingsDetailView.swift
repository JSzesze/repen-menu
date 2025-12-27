import SwiftUI
import AppKit

// MARK: - Settings Detail View

struct SettingsDetailView: View {
    @AppStorage("defaultSource") private var defaultSource = "Microphone"
    @AppStorage("autoOpenFolder") private var autoOpenFolder = false
    @AppStorage("showInDock") private var showInDock = true
    @AppStorage("autoTranscribe") private var autoTranscribe = false
    @AppStorage("autoTitleFromSummary") private var autoTitleFromSummary = true
    
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
                Toggle("Auto-update title from summary", isOn: $autoTitleFromSummary)
                    .help("Automatically set document title from AI-generated summary")
                
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
