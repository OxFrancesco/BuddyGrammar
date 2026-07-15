import Foundation

struct ElevenLabsTranscriptResponse: Decodable, Equatable, Sendable {
    let text: String
    let languageCode: String?
    let languageProbability: Double?

    private enum CodingKeys: String, CodingKey {
        case text
        case languageCode = "language_code"
        case languageProbability = "language_probability"
    }
}

enum ElevenLabsSpeechError: LocalizedError {
    case missingAPIKey
    case emptyAudio
    case invalidResponse
    case emptyTranscript
    case server(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Add your ElevenLabs API key in Voice Settings."
        case .emptyAudio:
            "The recording did not contain any audio."
        case .invalidResponse:
            "ElevenLabs returned an unreadable transcription response."
        case .emptyTranscript:
            "ElevenLabs could not hear any speech in the recording."
        case .server(let message):
            message
        }
    }
}

actor ElevenLabsSpeechClient {
    private let session: URLSession
    private let endpoint: URL

    init(
        session: URLSession = .shared,
        endpoint: URL = URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!
    ) {
        self.session = session
        self.endpoint = endpoint
    }

    func transcribe(
        audioURL: URL,
        apiKey: String,
        localeIdentifier: String,
        vocabulary: [String]
    ) async throws -> String {
        let audioData = try Data(contentsOf: audioURL)
        guard !audioData.isEmpty else { throw ElevenLabsSpeechError.emptyAudio }

        let boundary = "BuddyWrite-\(UUID().uuidString)"
        let body = MultipartFormData(boundary: boundary)
            .addingField(name: "model_id", value: "scribe_v2")
            .addingField(name: "language_code", value: Self.languageCode(for: localeIdentifier))
            .addingField(name: "tag_audio_events", value: "false")
            .addingField(name: "diarize", value: "false")
            .addingField(name: "timestamps_granularity", value: "none")
            .addingFields(name: "keyterms", values: Array(vocabulary.prefix(1_000)))
            .addingFile(
                name: "file",
                filename: audioURL.lastPathComponent,
                contentType: "audio/wav",
                data: audioData
            )
            .encoded()

        var request = URLRequest(url: endpoint, timeoutInterval: 90)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ElevenLabsSpeechError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ElevenLabsSpeechError.server(
                Self.errorMessage(from: data, statusCode: httpResponse.statusCode)
            )
        }

        guard let transcript = try? JSONDecoder().decode(ElevenLabsTranscriptResponse.self, from: data) else {
            throw ElevenLabsSpeechError.invalidResponse
        }
        let text = transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ElevenLabsSpeechError.emptyTranscript }
        return text
    }

    static func languageCode(for localeIdentifier: String) -> String {
        Locale(identifier: localeIdentifier).language.languageCode?.identifier.lowercased() ?? "en"
    }

    private static func errorMessage(from data: Data, statusCode: Int) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let detail = object["detail"] as? String, !detail.isEmpty {
                return detail
            }
            if let detail = object["detail"] as? [String: Any],
               let message = detail["message"] as? String,
               !message.isEmpty {
                return message
            }
        }
        return "ElevenLabs transcription failed: \(HTTPURLResponse.localizedString(forStatusCode: statusCode))."
    }
}

@MainActor
final class ElevenLabsSpeechEngine: SpeechTranscriptionEngine {
    private let client: ElevenLabsSpeechClient
    private var apiKey: String?

    init(apiKey: String? = nil, client: ElevenLabsSpeechClient = ElevenLabsSpeechClient()) {
        self.apiKey = apiKey
        self.client = client
    }

    func updateAPIKey(_ apiKey: String?) {
        self.apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func isAvailable(for localeIdentifier: String) async -> Bool {
        apiKey?.isEmpty == false
    }

    func requiresSpeechRecognitionAuthorization(for localeIdentifier: String) async -> Bool {
        false
    }

    func transcribe(
        audioURL: URL,
        localeIdentifier: String,
        vocabulary: [String]
    ) async throws -> String {
        guard let apiKey, !apiKey.isEmpty else {
            throw ElevenLabsSpeechError.missingAPIKey
        }
        return try await client.transcribe(
            audioURL: audioURL,
            apiKey: apiKey,
            localeIdentifier: localeIdentifier,
            vocabulary: vocabulary
        )
    }
}

private struct MultipartFormData {
    private let boundary: String
    private var data = Data()

    init(boundary: String) {
        self.boundary = boundary
    }

    func addingField(name: String, value: String?) -> Self {
        guard let value, !value.isEmpty else { return self }
        var copy = self
        copy.append("--\(boundary)\r\n")
        copy.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        copy.append("\(value)\r\n")
        return copy
    }

    func addingFields(name: String, values: [String]) -> Self {
        values.reduce(self) { form, value in
            form.addingField(name: name, value: value)
        }
    }

    func addingFile(
        name: String,
        filename: String,
        contentType: String,
        data fileData: Data
    ) -> Self {
        var copy = self
        let safeFilename = filename.replacingOccurrences(of: "\"", with: "")
        copy.append("--\(boundary)\r\n")
        copy.append(
            "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(safeFilename)\"\r\n"
        )
        copy.append("Content-Type: \(contentType)\r\n\r\n")
        copy.data.append(fileData)
        copy.append("\r\n")
        return copy
    }

    func encoded() -> Data {
        var result = data
        result.append(Data("--\(boundary)--\r\n".utf8))
        return result
    }

    private mutating func append(_ string: String) {
        data.append(Data(string.utf8))
    }
}
