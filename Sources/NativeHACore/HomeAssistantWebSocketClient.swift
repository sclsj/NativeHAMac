import Foundation

public enum HomeAssistantWebSocketError: Error, Equatable {
    case invalidURL
    case invalidMessage
    case authenticationFailed(String)
    case commandFailed(String)
    case disconnected
}

public final class HomeAssistantWebSocketClient {
    private let configuration: HomeAssistantConfiguration
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var nextID = 1

    public init(configuration: HomeAssistantConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    public func connect() async throws {
        let url = try webSocketURL(from: configuration.baseURL)
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()

        let authRequired = try await receiveDictionary()
        guard authRequired["type"] as? String == "auth_required" else {
            throw HomeAssistantWebSocketError.invalidMessage
        }

        try await send([
            "type": "auth",
            "access_token": configuration.accessToken,
        ])

        while true {
            let response = try await receiveDictionary()
            switch response["type"] as? String {
            case "auth_ok":
                return
            case "auth_invalid":
                let message = response["message"] as? String ?? "Authentication rejected"
                throw HomeAssistantWebSocketError.authenticationFailed(message)
            default:
                continue
            }
        }
    }

    public func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    public func fetchLovelaceConfig() async throws -> LovelaceConfig {
        let result = try await sendCommand(type: "lovelace/config")
        let data = try JSONSerialization.data(withJSONObject: result)
        return try JSONDecoder().decode(LovelaceConfig.self, from: data)
    }

    public func subscribeToStateChanges() async throws {
        _ = try await sendCommand(
            type: "subscribe_events",
            fields: ["event_type": "state_changed"]
        )
    }

    public func receiveStateChanges(_ onState: @escaping @MainActor (HAState) -> Void) async throws {
        while true {
            let message = try await receiveDictionary()
            guard
                message["type"] as? String == "event",
                let event = message["event"] as? [String: Any],
                let data = event["data"] as? [String: Any],
                let newState = data["new_state"] as? [String: Any]
            else {
                continue
            }

            let encoded = try JSONSerialization.data(withJSONObject: newState)
            let state = try JSONDecoder().decode(HAState.self, from: encoded)
            await onState(state)
        }
    }

    private func sendCommand(type: String, fields: [String: Any] = [:]) async throws -> Any {
        guard task != nil else {
            throw HomeAssistantWebSocketError.disconnected
        }

        let id = nextID
        nextID += 1

        var payload = fields
        payload["id"] = id
        payload["type"] = type

        try await send(payload)

        while true {
            let response = try await receiveDictionary()
            guard response["id"] as? Int == id else {
                continue
            }

            if response["success"] as? Bool == true, let result = response["result"] {
                return result
            }

            if
                let error = response["error"] as? [String: Any],
                let message = error["message"] as? String
            {
                throw HomeAssistantWebSocketError.commandFailed(message)
            }

            throw HomeAssistantWebSocketError.invalidMessage
        }
    }

    private func send(_ object: [String: Any]) async throws {
        guard let task = task else {
            throw HomeAssistantWebSocketError.disconnected
        }

        let data = try JSONSerialization.data(withJSONObject: object)
        guard let string = String(data: data, encoding: .utf8) else {
            throw HomeAssistantWebSocketError.invalidMessage
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            task.send(.string(string)) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func receiveDictionary() async throws -> [String: Any] {
        guard let task = task else {
            throw HomeAssistantWebSocketError.disconnected
        }

        let message = try await withCheckedThrowingContinuation { continuation in
            task.receive { result in
                continuation.resume(with: result)
            }
        }

        let data: Data
        switch message {
        case let .string(string):
            data = Data(string.utf8)
        case let .data(rawData):
            data = rawData
        @unknown default:
            throw HomeAssistantWebSocketError.invalidMessage
        }

        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HomeAssistantWebSocketError.invalidMessage
        }
        return object
    }

    private func webSocketURL(from baseURL: URL) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw HomeAssistantWebSocketError.invalidURL
        }

        switch components.scheme {
        case "https":
            components.scheme = "wss"
        case "http":
            components.scheme = "ws"
        default:
            throw HomeAssistantWebSocketError.invalidURL
        }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + ([basePath, "api", "websocket"].filter { !$0.isEmpty }.joined(separator: "/"))

        guard let url = components.url else {
            throw HomeAssistantWebSocketError.invalidURL
        }
        return url
    }
}
