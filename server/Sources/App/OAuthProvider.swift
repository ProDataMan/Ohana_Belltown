import Vapor

struct OAuthUserInfo {
    var providerId: String
    var email: String
    var displayName: String
}

enum OAuthConfigError: Error {
    case missingConfig(String)
}

extension OAuthConfigError: AbortError {
    var status: HTTPResponseStatus { .serviceUnavailable }

    var reason: String {
        switch self {
        case .missingConfig(let detail):
            return "Sign-in with this provider isn't configured yet (\(detail))."
        }
    }
}

enum OAuthProvider: String {
    case google
    case apple

    func id(of user: CustomerUser) -> String? {
        switch self {
        case .google: return user.googleId
        case .apple: return user.appleId
        }
    }

    func setId(_ id: String, on user: inout CustomerUser) {
        switch self {
        case .google: user.googleId = id
        case .apple: user.appleId = id
        }
    }

    func id(of user: StaffUser) -> String? {
        switch self {
        case .google: return user.googleId
        case .apple: return user.appleId
        }
    }

    func setId(_ id: String, on user: inout StaffUser) {
        switch self {
        case .google: user.googleId = id
        case .apple: user.appleId = id
        }
    }
}
