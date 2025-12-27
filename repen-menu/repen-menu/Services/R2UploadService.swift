import Foundation
import CryptoKit

// MARK: - R2 Configuration

struct R2Configuration: Sendable {
    let accountId: String
    let accessKeyId: String
    let secretAccessKey: String
    let bucketName: String
    let publicUrl: String
    
    var endpoint: String {
        "https://\(accountId).r2.cloudflarestorage.com"
    }
    
    var isConfigured: Bool {
        !accountId.isEmpty && !accessKeyId.isEmpty && !secretAccessKey.isEmpty && !bucketName.isEmpty && !publicUrl.isEmpty
    }
    
    @MainActor
    static func load() -> R2Configuration {
        R2Configuration(
            accountId: UserDefaults.standard.string(forKey: "r2AccountId") ?? "",
            accessKeyId: UserDefaults.standard.string(forKey: "r2AccessKeyId") ?? "",
            secretAccessKey: UserDefaults.standard.string(forKey: "r2SecretAccessKey") ?? "",
            bucketName: UserDefaults.standard.string(forKey: "r2BucketName") ?? "",
            publicUrl: UserDefaults.standard.string(forKey: "r2PublicUrl") ?? ""
        )
    }
    
    @MainActor
    func save() {
        UserDefaults.standard.set(accountId, forKey: "r2AccountId")
        UserDefaults.standard.set(accessKeyId, forKey: "r2AccessKeyId")
        UserDefaults.standard.set(secretAccessKey, forKey: "r2SecretAccessKey")
        UserDefaults.standard.set(bucketName, forKey: "r2BucketName")
        UserDefaults.standard.set(publicUrl, forKey: "r2PublicUrl")
    }
}

// MARK: - R2 Upload Result

struct R2UploadResult {
    let success: Bool
    let url: String?
    let error: String?
}

// MARK: - R2 Upload Progress

struct R2UploadProgress {
    enum Phase {
        case preparing
        case uploading
        case completing
    }
    
    let phase: Phase
    let bytesUploaded: Int64
    let totalBytes: Int64
    let percent: Int
}

// MARK: - R2 Upload Service

actor R2UploadService {
    static let shared = R2UploadService()
    
    private init() {}
    
    // MARK: - Public API
    
    func uploadFile(at url: URL, onProgress: (@Sendable (R2UploadProgress) -> Void)? = nil) async throws -> R2UploadResult {
        let config = await MainActor.run { R2Configuration.load() }
        
        guard config.isConfigured else {
            return R2UploadResult(success: false, url: nil, error: "R2 is not configured. Please set up R2 credentials in settings.")
        }
        
        let fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 ?? 0
        let objectKey = generateObjectKey(for: url)
        let contentType = getContentType(for: url)
        
        print("[R2] Starting upload for: \(url.lastPathComponent)")
        print("[R2] File size: \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))")
        print("[R2] Object key: \(objectKey)")
        
        // Report preparing phase
        onProgress?(R2UploadProgress(phase: .preparing, bytesUploaded: 0, totalBytes: fileSize, percent: 0))
        
        do {
            // Read file data
            let fileData = try Data(contentsOf: url)
            
            // Report uploading phase
            onProgress?(R2UploadProgress(phase: .uploading, bytesUploaded: 0, totalBytes: fileSize, percent: 0))
            
            // Upload to R2
            let uploadUrl = URL(string: "\(config.endpoint)/\(config.bucketName)/\(objectKey)")!
            
            var request = URLRequest(url: uploadUrl)
            request.httpMethod = "PUT"
            request.httpBody = fileData
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
            request.setValue("\(fileData.count)", forHTTPHeaderField: "Content-Length")
            
            // Sign the request with AWS4 signature
            let signedRequest = signRequest(request, method: "PUT", body: fileData, config: config)
            
            let (_, response) = try await URLSession.shared.data(for: signedRequest)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return R2UploadResult(success: false, url: nil, error: "Invalid response from R2")
            }
            
            if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                // Report completing phase
                onProgress?(R2UploadProgress(phase: .completing, bytesUploaded: fileSize, totalBytes: fileSize, percent: 100))
                
                // Construct public URL
                var publicUrl = config.publicUrl
                if !publicUrl.hasSuffix("/") {
                    publicUrl += "/"
                }
                let fullUrl = "\(publicUrl)\(objectKey)"
                
                print("[R2] Upload successful! Public URL: \(fullUrl)")
                return R2UploadResult(success: true, url: fullUrl, error: nil)
            } else {
                let errorMessage = "R2 upload failed: HTTP \(httpResponse.statusCode)"
                print("[R2] \(errorMessage)")
                return R2UploadResult(success: false, url: nil, error: errorMessage)
            }
        } catch {
            print("[R2] Upload error: \(error)")
            return R2UploadResult(success: false, url: nil, error: error.localizedDescription)
        }
    }
    
    // MARK: - Private Helpers
    
    private func generateObjectKey(for url: URL) -> String {
        let fileName = url.lastPathComponent
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let randomSuffix = String((0..<6).map { _ in "abcdefghijklmnopqrstuvwxyz0123456789".randomElement()! })
        return "audio-uploads/\(timestamp)-\(randomSuffix)-\(fileName)"
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
    
    private func signRequest(_ request: URLRequest, method: String, body: Data?, config: R2Configuration) -> URLRequest {
        var signedRequest = request
        guard let url = request.url else { return signedRequest }
        
        let now = Date()
        let amzDate = ISO8601DateFormatter.awsDateTime.string(from: now)
        let dateStamp = ISO8601DateFormatter.awsDateOnly.string(from: now)
        
        // Calculate payload hash
        let payloadHash: String
        if let body = body {
            payloadHash = SHA256.hash(data: body).hexString
        } else {
            payloadHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" // empty hash
        }
        
        // Set required headers
        signedRequest.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
        signedRequest.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")
        signedRequest.setValue(url.host ?? "", forHTTPHeaderField: "Host")
        
        // Build canonical request
        let canonicalUri = url.path.isEmpty ? "/" : url.path
        let canonicalQuerystring = url.query ?? ""
        
        let headersToSign = ["content-length", "content-type", "host", "x-amz-content-sha256", "x-amz-date"]
        let signedHeaders = headersToSign.joined(separator: ";")
        
        var canonicalHeaders = ""
        for header in headersToSign {
            if let value = signedRequest.value(forHTTPHeaderField: header) {
                canonicalHeaders += "\(header):\(value.trimmingCharacters(in: .whitespaces))\n"
            }
        }
        
        let canonicalRequest = [
            method,
            canonicalUri,
            canonicalQuerystring,
            canonicalHeaders,
            signedHeaders,
            payloadHash
        ].joined(separator: "\n")
        
        // Create string to sign
        let algorithm = "AWS4-HMAC-SHA256"
        let region = "auto"
        let service = "s3"
        let credentialScope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        
        let canonicalRequestHash = SHA256.hash(data: Data(canonicalRequest.utf8)).hexString
        let stringToSign = [
            algorithm,
            amzDate,
            credentialScope,
            canonicalRequestHash
        ].joined(separator: "\n")
        
        // Calculate signature
        let kDate = hmacSHA256(key: Data("AWS4\(config.secretAccessKey)".utf8), data: Data(dateStamp.utf8))
        let kRegion = hmacSHA256(key: kDate, data: Data(region.utf8))
        let kService = hmacSHA256(key: kRegion, data: Data(service.utf8))
        let kSigning = hmacSHA256(key: kService, data: Data("aws4_request".utf8))
        let signature = hmacSHA256(key: kSigning, data: Data(stringToSign.utf8)).hexString
        
        // Create authorization header
        let authorizationHeader = "\(algorithm) Credential=\(config.accessKeyId)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
        signedRequest.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        
        return signedRequest
    }
    
    private func hmacSHA256(key: Data, data: Data) -> Data {
        let symmetricKey = SymmetricKey(data: key)
        let signature = HMAC<SHA256>.authenticationCode(for: data, using: symmetricKey)
        return Data(signature)
    }
}

// MARK: - Extensions

extension ISO8601DateFormatter {
    // AWS requires format: 20231224T093753Z (no dashes, no colons)
    static let awsDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
    
    // AWS date only: 20231224
    static let awsDateOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}

extension SHA256.Digest {
    var hexString: String {
        self.map { String(format: "%02x", $0) }.joined()
    }
}

extension Data {
    var hexString: String {
        self.map { String(format: "%02x", $0) }.joined()
    }
}
