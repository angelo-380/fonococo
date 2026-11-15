import Foundation

/// REST schema belongs to the application's own backend, not Gartic Phone.
public final class RESTClient: ContentServicing {
    private let baseURL: URL
    private let apiKey: String
    private let phrasePath: String
    private let avatarPath: String
    private let session: URLSession
    public init(environment: AppEnvironment, session: URLSession = .shared) throws {
        baseURL = try environment.restBaseURL
        apiKey = try environment.value("REST_API_KEY")
        phrasePath = try environment.value("REST_PHRASES_PATH")
        avatarPath = try environment.value("REST_AVATARS_PATH")
        self.session = session
    }
    public func randomPhrase() async throws -> Phrase { try await get(path: phrasePath) }
    public func avatars() async throws -> [Avatar] { try await get(path: avatarPath) }
    private func get<T: Decodable>(path: String) async throws -> T {
        guard !path.hasPrefix("/"), !path.contains("://"), !path.contains("..") else { throw ServiceError.invalidPayload }
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        let (data, response) = try await session.data(for: request, delegate: SameOriginRedirectDelegate(origin: baseURL))
        guard let http = response as? HTTPURLResponse else { throw ServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw ServiceError.http(http.statusCode) }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

/// A redirect must not carry the app's API key to another origin or downgrade TLS.
private final class SameOriginRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let origin: URL
    init(origin: URL) { self.origin = origin }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard let destination = request.url,
              destination.scheme == origin.scheme,
              destination.host?.lowercased() == origin.host?.lowercased(),
              (destination.port ?? 443) == (origin.port ?? 443),
              destination.user == nil, destination.password == nil else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
