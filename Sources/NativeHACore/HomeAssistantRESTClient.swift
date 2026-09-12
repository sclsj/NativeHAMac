import Foundation

public enum HomeAssistantClientError: Error, Equatable, LocalizedError {
    case invalidResponse
    case httpStatus(Int, String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid Home Assistant HTTP response"
        case let .httpStatus(status, _):
            return "Home Assistant HTTP \(status): \(HTTPURLResponse.localizedString(forStatusCode: status))"
        }
    }
}

public final class HomeAssistantRESTClient {
    private let configuration: HomeAssistantConfiguration
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(configuration: HomeAssistantConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    public func fetchConfig() async throws -> HAConfig {
        try await send(method: "GET", pathComponents: ["api", "config"])
    }

    public func fetchStates() async throws -> [HAState] {
        try await send(method: "GET", pathComponents: ["api", "states"])
    }

    public func fetchHistory(entityIDs: [String], hoursToShow: Int) async throws -> [HAHistorySeries] {
        guard !entityIDs.isEmpty else {
            return []
        }

        let startDate = Date().addingTimeInterval(TimeInterval(-max(hoursToShow, 1) * 60 * 60))
        let start = ISO8601DateFormatter().string(from: startDate)
        let endpoint = url(pathComponents: ["api", "history", "period", start])

        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "filter_entity_id", value: entityIDs.joined(separator: ",")),
            URLQueryItem(name: "minimal_response", value: nil),
            URLQueryItem(name: "significant_changes_only", value: "0"),
        ]

        guard let url = components?.url else {
            throw HomeAssistantClientError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = configuration.timeout
        request.setValue("Bearer \(configuration.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let rawSeries: [[HAHistoryPoint]] = try await perform(request)
        return rawSeries.compactMap { points in
            guard let entityID = points.compactMap(\.entityId).first else {
                return nil
            }
            return HAHistorySeries(entityID: entityID, points: points)
        }
    }

    @discardableResult
    public func callService(
        domain: String,
        service: String,
        data: [String: JSONValue] = [:]
    ) async throws -> [HAState] {
        try await send(
            method: "POST",
            pathComponents: ["api", "services", domain, service],
            body: .object(data)
        )
    }

    private func send<T: Decodable>(
        method: String,
        pathComponents: [String],
        body: JSONValue? = nil
    ) async throws -> T {
        var request = URLRequest(url: url(pathComponents: pathComponents))
        request.httpMethod = method
        request.timeoutInterval = configuration.timeout
        request.setValue("Bearer \(configuration.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body = body {
            request.httpBody = try encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        return try await perform(request)
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        var responseData: Data?
        var status: Int?
        do {
            let (data, response) = try await session.data(for: request)
            responseData = data
            guard let http = response as? HTTPURLResponse else {
                throw HomeAssistantClientError.invalidResponse
            }
            status = http.statusCode
            guard (200..<300).contains(http.statusCode) else {
                throw HomeAssistantClientError.httpStatus(http.statusCode, diagnosticPayload(data))
            }
            return try decoder.decode(T.self, from: data)
        } catch {
            if !isDiagnosticCancellation(error), !Task.isCancelled {
                AppLog(
                    "REST \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "unknown") " +
                        "failed; status=\(status.map(String.init) ?? "none") " +
                        "error=\(String(reflecting: error)) " +
                        "request=\(request.httpBody.map(diagnosticPayload) ?? "none") " +
                        "response=\(responseData.map(diagnosticPayload) ?? "none")",
                    severity: .error,
                    category: .network
                )
            }
            throw error
        }
    }

    private func url(pathComponents: [String]) -> URL {
        var url = configuration.baseURL
        for component in pathComponents {
            url.appendPathComponent(component)
        }
        return url
    }
}
