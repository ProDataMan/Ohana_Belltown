import Crypto
import Foundation
import Vapor

protocol TuyaCommanding: Sendable {
    func setColor(deviceId: String, color: LightColor, on: Bool) async throws
}

/// Tuya Cloud "Send commands" client. No-ops are handled by LightNotifier
/// when credentials are missing — this type assumes it was constructed with
/// real Access ID / Secret.
///
/// Sign algorithm: HMAC-SHA256(client_id + [access_token] + t + stringToSign, secret)
/// where stringToSign is METHOD \\n SHA256(body) \\n \\n pathAndQuery
/// (https://developer.tuya.com/en/docs/iot/singnature).
actor TuyaCloudClient: TuyaCommanding {
    struct Config: Sendable {
        var accessId: String
        var accessSecret: String
        var baseURL: String
        var colourCode: String
    }

    private let config: Config
    private let http: any TuyaHTTPClient
    private var accessToken: String?
    private var tokenExpiresAt: Date = .distantPast

    init(config: Config, http: any TuyaHTTPClient = URLSessionTuyaHTTPClient()) {
        self.config = config
        self.http = http
    }

    static func fromEnvironment() -> TuyaCloudClient? {
        guard let accessId = Environment.get("TUYA_ACCESS_ID")?.nonEmpty,
              let accessSecret = Environment.get("TUYA_ACCESS_SECRET")?.nonEmpty else {
            return nil
        }
        return TuyaCloudClient(config: Config(
            accessId: accessId,
            accessSecret: accessSecret,
            baseURL: TuyaCloudClient.baseURL(for: Environment.get("TUYA_REGION")),
            colourCode: Environment.get("TUYA_COLOUR_CODE")?.nonEmpty ?? "colour_data"
        ))
    }

    static func baseURL(for region: String?) -> String {
        switch (region ?? "us").lowercased() {
        case "us-e", "useast", "east", "us-east":
            return "https://openapi-ueaz.tuyaus.com"
        case "eu", "europe":
            return "https://openapi.tuyaeu.com"
        case "in", "india":
            return "https://openapi.tuyain.com"
        case "cn", "china":
            return "https://openapi.tuya.cn.com"
        default:
            return "https://openapi.tuyaus.com"
        }
    }

    func setColor(deviceId: String, color: LightColor, on: Bool) async throws {
        var commands: [[String: Any]] = [
            ["code": "switch_led", "value": on]
        ]
        if on {
            if config.colourCode == "colour_data_v2" {
                let hsv = color.tuyaHSVv2
                commands.append(["code": "work_mode", "value": "colour"])
                commands.append(["code": "colour_data_v2", "value": hsv])
            } else {
                commands.append(["code": "work_mode", "value": "colour"])
                commands.append(["code": config.colourCode, "value": color.tuyaColourData])
            }
        }
        try await sendCommands(deviceId: deviceId, commands: commands)
    }

    private func sendCommands(deviceId: String, commands: [[String: Any]]) async throws {
        let token = try await validToken()
        let path = "/v1.0/iot-03/devices/\(deviceId)/commands"
        let bodyObj: [String: Any] = ["commands": commands]
        let body = try JSONSerialization.data(withJSONObject: bodyObj)
        _ = try await signedRequest(method: "POST", path: path, body: body, accessToken: token)
    }

    private func validToken() async throws -> String {
        if let accessToken, tokenExpiresAt > Date().addingTimeInterval(30) {
            return accessToken
        }
        let path = "/v1.0/token?grant_type=1"
        let json = try await signedRequest(method: "GET", path: path, body: nil, accessToken: nil)
        guard let result = json["result"] as? [String: Any],
              let token = result["access_token"] as? String else {
            throw TuyaError.unexpectedResponse("token missing access_token")
        }
        let expire = (result["expire_time"] as? Int) ?? 7200
        self.accessToken = token
        self.tokenExpiresAt = Date().addingTimeInterval(TimeInterval(expire))
        return token
    }

    @discardableResult
    private func signedRequest(method: String, path: String, body: Data?, accessToken: String?) async throws -> [String: Any] {
        let timestamp = String(Int(Date().timeIntervalSince1970 * 1000))
        let bodyString = body.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let contentHash = sha256Hex(bodyString)
        let stringToSign = "\(method)\n\(contentHash)\n\n\(path)"
        var message = config.accessId
        if let accessToken { message += accessToken }
        message += timestamp + stringToSign
        let sign = hmacSHA256Upper(message: message, secret: config.accessSecret)

        var headers = [
            "client_id": config.accessId,
            "sign": sign,
            "sign_method": "HMAC-SHA256",
            "t": timestamp,
            "lang": "en"
        ]
        if let accessToken {
            headers["access_token"] = accessToken
        }

        let url = config.baseURL + path
        let json = try await http.send(method: method, url: url, headers: headers, body: body)
        if let success = json["success"] as? Bool, success == false {
            let msg = (json["msg"] as? String) ?? "Tuya request failed"
            throw TuyaError.api(msg)
        }
        return json
    }
}

enum TuyaError: Error, CustomStringConvertible {
    case api(String)
    case unexpectedResponse(String)

    var description: String {
        switch self {
        case .api(let message): return message
        case .unexpectedResponse(let message): return message
        }
    }
}

protocol TuyaHTTPClient: Sendable {
    func send(method: String, url: String, headers: [String: String], body: Data?) async throws -> [String: Any]
}

struct URLSessionTuyaHTTPClient: TuyaHTTPClient {
    func send(method: String, url: String, headers: [String: String], body: Data?) async throws -> [String: Any] {
        guard let parsed = URL(string: url) else {
            throw TuyaError.unexpectedResponse("bad URL")
        }
        var request = URLRequest(url: parsed)
        request.httpMethod = method
        request.timeoutInterval = 4
        request.httpBody = body
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (data, _) = try await URLSession.shared.data(for: request)
        let raw = try JSONSerialization.jsonObject(with: data)
        return raw as? [String: Any] ?? [:]
    }
}

private func sha256Hex(_ string: String) -> String {
    let digest = SHA256.hash(data: Data(string.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
}

private func hmacSHA256Upper(message: String, secret: String) -> String {
    let key = SymmetricKey(data: Data(secret.utf8))
    let mac = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
    return Data(mac).map { String(format: "%02X", $0) }.joined()
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension LightColor {
    var tuyaHSVv2: [String: Int] {
        let hex = tuyaColourData
        func part(_ range: Range<String.Index>) -> Int {
            Int(hex[range], radix: 16) ?? 0
        }
        let hEnd = hex.index(hex.startIndex, offsetBy: 4)
        let sEnd = hex.index(hEnd, offsetBy: 4)
        return [
            "h": part(hex.startIndex..<hEnd),
            "s": part(hEnd..<sEnd),
            "v": part(sEnd..<hex.endIndex)
        ]
    }
}
