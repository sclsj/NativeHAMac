import Foundation
import NativeHACore

@main
enum HAProbe {
    static func main() async throws {
        let environment = ProcessInfo.processInfo.environment

        guard
            let baseURLString = environment["HA_BASE_URL"],
            let baseURL = URL(string: baseURLString),
            let token = environment["HA_TOKEN"],
            !token.isEmpty
        else {
            print("Usage: HA_BASE_URL=http://homeassistant.local:8123 HA_TOKEN=<token> swift run ha-probe")
            return
        }

        let client = HomeAssistantRESTClient(
            configuration: HomeAssistantConfiguration(baseURL: baseURL, accessToken: token)
        )
        let config = try await client.fetchConfig()
        let states = try await client.fetchStates()

        print("Connected to: \(config.locationName ?? baseURL.host ?? baseURLString)")
        print("Components: \(config.components.count)")
        print("Entities: \(states.count)")
    }
}
