import Vapor

struct AIExtractionStatus: Content {
    var available: Bool
}

struct MenuExtractionRequest: Content {
    var photoUrl: String
}

/// Reads a competitor's menu photo (already uploaded via /api/upload) with
/// Claude's vision API and returns the item names/prices it can make out —
/// entirely gated behind ANTHROPIC_API_KEY, which is a separate credential
/// from any claude.ai chat subscription. Mirrors the "hidden until
/// configured" pattern already used for Apple/Facebook Sign-In: the client
/// checks availability once and simply doesn't show the button otherwise.
enum AnthropicMenuExtraction {
    struct ExtractedItem: Content {
        var name: String
        var price: Double?
    }

    struct ExtractionResult: Content {
        var items: [ExtractedItem]
    }

    enum ExtractionError: Error {
        case notConfigured
        case requestFailed
        case unparsableResponse
    }

    private struct ImageSource: Encodable {
        let type = "base64"
        let media_type: String
        let data: String
    }

    private struct ContentBlock: Encodable {
        let type: String
        var source: ImageSource?
        var text: String?
    }

    private struct Message: Encodable {
        let role: String
        let content: [ContentBlock]
    }

    private struct RequestBody: Encodable {
        let model: String
        let max_tokens: Int
        let messages: [Message]
    }

    private struct ResponseContentBlock: Decodable {
        let type: String
        let text: String?
    }

    private struct ResponseBody: Decodable {
        let content: [ResponseContentBlock]
    }

    private struct RawExtraction: Decodable {
        let items: [ExtractedItem]
    }

    static func mediaType(forExtension ext: String) -> String {
        switch ext {
        case "png": return "image/png"
        case "webp": return "image/webp"
        case "gif": return "image/gif"
        default: return "image/jpeg"
        }
    }

    static func extractItems(client: Client, apiKey: String, imageData: Data, mediaType: String) async throws -> [ExtractedItem] {
        let base64 = imageData.base64EncodedString()
        let prompt = """
        This is a photo of a restaurant's menu. List every food/drink item and its price you can \
        read, as a JSON object of exactly this shape: {"items": [{"name": "Item Name", "price": 12.5}]}. \
        Omit "price" for a specific item only if its price genuinely isn't legible in the photo — \
        never guess a price. Respond with ONLY that JSON object — no markdown code fences, no other text.
        """
        let body = RequestBody(
            model: "claude-sonnet-5",
            max_tokens: 2048,
            messages: [
                Message(role: "user", content: [
                    ContentBlock(type: "image", source: ImageSource(media_type: mediaType, data: base64), text: nil),
                    ContentBlock(type: "text", source: nil, text: prompt),
                ])
            ]
        )

        let response = try await client.post(URI(string: "https://api.anthropic.com/v1/messages")) { req in
            req.headers.add(name: "x-api-key", value: apiKey)
            req.headers.add(name: "anthropic-version", value: "2023-06-01")
            try req.content.encode(body, as: .json)
        }.get()

        guard response.status == .ok else {
            throw ExtractionError.requestFailed
        }
        let decoded = try response.content.decode(ResponseBody.self)
        guard let text = decoded.content.first(where: { $0.type == "text" })?.text else {
            throw ExtractionError.unparsableResponse
        }
        guard let jsonStart = text.firstIndex(of: "{"), let jsonEnd = text.lastIndex(of: "}"), jsonStart <= jsonEnd else {
            throw ExtractionError.unparsableResponse
        }
        guard let jsonData = String(text[jsonStart...jsonEnd]).data(using: .utf8) else {
            throw ExtractionError.unparsableResponse
        }
        do {
            return try JSONDecoder().decode(RawExtraction.self, from: jsonData).items
        } catch {
            throw ExtractionError.unparsableResponse
        }
    }
}

extension AnthropicMenuExtraction.ExtractionError: AbortError {
    var status: HTTPResponseStatus {
        switch self {
        case .notConfigured: return .serviceUnavailable
        case .requestFailed: return .badGateway
        case .unparsableResponse: return .badGateway
        }
    }

    var reason: String {
        switch self {
        case .notConfigured: return "AI menu extraction isn't configured yet."
        case .requestFailed: return "The AI request failed — try again in a moment."
        case .unparsableResponse: return "Couldn't read a clear response from the AI — try a clearer photo."
        }
    }
}
