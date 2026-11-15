import Foundation
import FirebaseCore

public final class AppEnvironment {
    public enum ConfigurationError: LocalizedError {
        case missing(String), invalid(String)
        public var errorDescription: String? {
            switch self {
            case .missing(let name): return "Falta configurar \(name)."
            case .invalid(let name): return "Configuración inválida: \(name)."
            }
        }
    }
    private let values: [String: Any]
    public init(bundle: Bundle = .main) { values = bundle.infoDictionary ?? [:] }
    public func value(_ key: String) throws -> String {
        guard let value = values[key] as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !value.contains("$(") else { throw ConfigurationError.missing(key) }
        return value
    }
    public var restBaseURL: URL {
        get throws {
            let raw = try value("REST_API_BASE_URL")
            guard let url = URL(string: raw), url.scheme == "https", url.host != nil,
                  url.user == nil, url.password == nil else {
                throw ConfigurationError.invalid("REST_API_BASE_URL")
            }
            return url
        }
    }
    /// Missing or malformed configuration returns an actionable error before Firebase initialization.
    @MainActor public static func configureFirebase(bundle: Bundle = .main) throws {
        guard FirebaseApp.app() == nil else { return }
        guard let path = bundle.path(forResource: "GoogleService-Info", ofType: "plist") else {
            throw ConfigurationError.missing("GoogleService-Info.plist")
        }
        guard let data = FileManager.default.contents(atPath: path),
              let dictionary = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw ConfigurationError.invalid("GoogleService-Info.plist")
        }
        for key in ["API_KEY", "GOOGLE_APP_ID", "GCM_SENDER_ID", "PROJECT_ID", "BUNDLE_ID", "DATABASE_URL"] {
            guard let text = dictionary[key] as? String, !text.isEmpty, !text.contains("$(") else {
                throw ConfigurationError.missing(key)
            }
        }
        guard dictionary["BUNDLE_ID"] as? String == bundle.bundleIdentifier,
              let database = dictionary["DATABASE_URL"] as? String,
              let url = URL(string: database), url.scheme == "https", url.host != nil,
              let options = FirebaseOptions(contentsOfFile: path) else {
            throw ConfigurationError.invalid("GoogleService-Info.plist")
        }
        FirebaseApp.configure(options: options)
    }
}
