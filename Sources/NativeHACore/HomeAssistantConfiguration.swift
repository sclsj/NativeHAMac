import Foundation

public struct HomeAssistantConfiguration {
    public let baseURL: URL
    public let accessToken: String
    public let timeout: TimeInterval

    public init(baseURL: URL, accessToken: String, timeout: TimeInterval = 10) {
        self.baseURL = baseURL
        self.accessToken = accessToken
        self.timeout = timeout
    }
}
