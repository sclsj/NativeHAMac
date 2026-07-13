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
        print("Entities: \(states.count)")
        
        let sps30Id = states.first { $0.entityId.contains("sps30") && $0.entityId.starts(with: "sensor.") && $0.entityId.contains("pm2") }?.entityId ?? "sensor.sps30_mass_concentration_pm2_5"
        print("Fetching 1 day of data for \(sps30Id)...")
        let history = try await client.fetchHistory(entityIDs: [sps30Id], hoursToShow: 24)
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(history)
        let fileURL = URL(fileURLWithPath: "sps30_1day.json")
        try data.write(to: fileURL)
        print("Saved \(data.count) bytes to \(fileURL.path)")
    }
}
