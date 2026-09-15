import Foundation
import XCTest
import NativeHACore
@testable import NativeHAMac

/// Requires fresh, explicit authorization before ACTUATE. The normal suite is offline.
/// READ_ONLY prepares the identical production path without issuing services.
@MainActor
final class ClimateLiveAcceptanceTests: XCTestCase {
    func testAuthorizedRoomACAcceptanceAndRestoration() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard ["READ_ONLY", "ACTUATE"].contains(environment["NATIVEHA_CLIMATE_LIVE"] ?? ""),
              environment["NATIVEHA_CLIMATE_LIVE_ENTITY"] == "climate.room_ac" else {
            throw XCTSkip("Requires fresh authorization, NATIVEHA_CLIMATE_LIVE=READ_ONLY or ACTUATE, and NATIVEHA_CLIMATE_LIVE_ENTITY=climate.room_ac")
        }
        let token = try String(contentsOfFile: AppConfig.tokenFilePath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let configuration = HomeAssistantConfiguration(baseURL: AppConfig.baseURLs[0], accessToken: token, timeout: 15)
        let run = ClimateLiveRun(configuration: configuration)
        var failure: Error?
        do {
            try await run.prepare()
            if environment["NATIVEHA_CLIMATE_LIVE"] == "ACTUATE" {
                try await run.exercise()
            }
        } catch { failure = error; run.note("exercise_failure", ["error": .string(String(describing: error))]) }
        // An unstructured task does not inherit a cancelled test task's cancellation.
        // Cleanup still cannot survive process termination or a network/server outage.
        let cleanup = Task { @MainActor () -> Error? in
            do { try await run.restore(); return nil }
            catch { run.note("RESTORATION_FAILURE", ["error": .string(String(describing: error))]); return error }
        }
        let restorationFailure = await cleanup.value
        await run.finish()
        if let restorationFailure = restorationFailure { throw restorationFailure }
        if let failure = failure { throw failure }
    }
}

private enum ClimateLiveFailure: Error { case precondition(String), timeout(String) }

@MainActor
private final class ClimateLiveRun {
    let entityID = "climate.room_ac"
    let configuration: HomeAssistantConfiguration
    let rest: HomeAssistantRESTClient
    let client: HomeAssistantWebSocketClient
    let controller = ClimateServiceController()
    var model: DashboardViewModel!
    var coordinator: HAEntitySubscriptionCoordinator?
    var starting: ClimateEntity?
    var calls = 0
    var acknowledgements = 0
    var serviceError: String?
    var replacements = 0
    var mutated = false

    init(configuration: HomeAssistantConfiguration) {
        self.configuration = configuration
        rest = HomeAssistantRESTClient(configuration: configuration)
        client = HomeAssistantWebSocketClient(configuration: configuration, commandTimeout: 10)
    }

    func note(_ kind: String, _ fields: [String: JSONValue] = [:]) {
        var event = fields
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        event["at"] = .string(formatter.string(from: Date()))
        event["event"] = .string(kind)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(JSONValue.object(event)), let line = String(data: data, encoding: .utf8) {
            print("CLIMATE_LIVE " + line)
            fflush(stdout)
        }
    }

    func read(_ label: String) async throws -> ClimateEntity {
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent("api/states/" + entityID))
        request.timeoutInterval = 15
        request.setValue("Bearer " + configuration.accessToken, forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ClimateLiveFailure.precondition("GET failed") }
        let raw = try JSONDecoder().decode(JSONValue.self, from: data)
        note(label, ["raw_state": raw])
        return ClimateEntity(state: try JSONDecoder().decode(HAState.self, from: data), unit: "°C")
    }

    func prepare() async throws {
        let config = try await rest.fetchConfig()
        guard config.unitSystem?.temperature == "°C" else { throw ClimateLiveFailure.precondition("Expected server Celsius") }
        starting = try await read("initial_GET")
        guard let start = starting, start.state.state == "off", start.value(.value) == 22.8,
              start.string("preset_mode") == "none", start.hvacModes == ["cool", "off"],
              start.options("preset_mode") == ["none", "sleep", "activity"], start.step == 0.1,
              start.temperatureBounds == 19...28 else { throw ClimateLiveFailure.precondition("Starting settings/capabilities differ from reviewed sequence") }
        model = DashboardViewModel(initialStates: [entityID: start.state], homeAssistantConfig: config)
        model.selectedEntityID = entityID
        model.installServiceCallerForTesting { [self] domain, service, data in
            try await self.dispatch(domain: domain, service: service, data: data, cleanup: false)
        }
        controller.install(entity: start) { [self] request, completion in
            model.invokeClimate(request, entityID: entityID) { [self] error in
                serviceError = error
                completion(error)
            }
        }
        coordinator = HAEntitySubscriptionCoordinator(onReplacement: { [self] ids in
            model.acceptClimateReplacement(entityIDs: ids)
            if ids.contains(entityID), let state = model.states[entityID] {
                replacements += 1
                controller.replace(ClimateEntity(state: state, unit: "°C"))
            }
        }, onSnapshot: { [self] states in model.states = states }, onPhase: { _ in })
        try await client.connect()
        _ = try await coordinator?.start(using: client)
        note("prepared", ["subscription_replacements": .int(replacements)])
    }

    func dispatch(domain: String, service: String, data: [String: JSONValue], cleanup: Bool) async throws {
        guard domain == "climate", data["entity_id"] == .string(entityID),
              ["set_temperature", "set_preset_mode", "set_hvac_mode"].contains(service) else {
            throw ClimateLiveFailure.precondition("Out of scope service")
        }
        calls += 1
        note("service_send", ["index": .int(calls), "cleanup": .bool(cleanup), "domain": .string(domain), "service": .string(service), "data": .object(data)])
        _ = try await rest.callService(domain: domain, service: service, data: data)
        acknowledgements += 1
        note("service_ack", ["index": .int(calls)])
    }

    func exercise() async throws {
        let fresh = try await read("pre_mutation_GET")
        guard sameSettings(fresh, starting!) else { throw ClimateLiveFailure.precondition("Settings changed before mutation") }
        mutated = true
        try await step("button_plus", expected: { abs(($0.value(.value) ?? 0) - 22.9) < 0.00001 }) { controller.button(1, target: .value) }
        for preset in ["sleep", "activity", "none"] {
            try await step("preset_" + preset, expected: { $0.string("preset_mode") == preset }) { controller.mode("preset_mode", value: preset) }
        }
        let needsTargetRestore = controller.entity?.value(.value) != 22.8
        if needsTargetRestore {
            try await step("target_restore_before_mode", expected: { $0.value(.value) == 22.8 }) {
                controller.change(22.8, target: .value, snap: false); controller.commit(.value)
            }
        } else {
            note("target_restore_noop", ["reason": .string("Preset already restored authoritative target to 22.8")])
        }
        for mode in ["cool", "off"] {
            try await step("mode_" + mode, expected: { $0.state.state == mode }) { controller.mode("hvac_mode", value: mode) }
        }
        let expectedCalls = needsTargetRestore ? 7 : 6
        guard calls == expectedCalls, acknowledgements == expectedCalls else { throw ClimateLiveFailure.precondition("Unexpected service call/ack count") }
    }

    func step(_ label: String, expected: (ClimateEntity) -> Bool, action: () -> Void) async throws {
        let before = calls
        let revision = replacements
        serviceError = nil
        action()
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if let error = serviceError { throw ClimateLiveFailure.precondition(error) }
            if calls == before + 1, acknowledgements == calls, replacements > revision,
               let state = model.states[entityID], expected(ClimateEntity(state: state, unit: "°C")) {
                let actual = try await read(label + "_confirmed_GET")
                guard expected(actual), let draft = controller.entity, expected(draft),
                      controller.values[.value] == actual.value(.value) else { throw ClimateLiveFailure.precondition("REST/subscription/draft disagree: " + label) }
                note("confirmed", ["step": .string(label), "calls": .int(calls), "replacements": .int(replacements), "draft_temperature": controller.values[.value].map(JSONValue.double) ?? .null])
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw ClimateLiveFailure.timeout(label)
    }

    func sameSettings(_ lhs: ClimateEntity, _ rhs: ClimateEntity) -> Bool {
        lhs.state.state == rhs.state.state && lhs.value(.value) == rhs.value(.value) && lhs.string("preset_mode") == rhs.string("preset_mode")
    }

    func restore() async throws {
        guard mutated, let start = starting else { return }
        controller.cancelDebounce()
        // Wait for the bounded REST request to retire before restoration can race it.
        let deadline = Date().addingTimeInterval(20)
        while model.dashboardOwnerSnapshotForTesting().serviceTaskCount > 0, Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        if model.dashboardOwnerSnapshotForTesting().serviceTaskCount > 0 {
            note("cleanup_retire_overdue_service_tasks")
            await model.stop()
        }
        var actual = try await read("cleanup_GET")
        for attribute in ["hvac_mode", "preset_mode", "temperature"] {
            let desired: JSONValue
            if attribute == "hvac_mode" { desired = .string(start.state.state); if actual.state.state == start.state.state { continue } }
            else if attribute == "preset_mode" { desired = .string(start.string(attribute)!); if actual.string(attribute) == start.string(attribute) { continue } }
            else { desired = .double(start.value(.value)!); if actual.value(.value) == start.value(.value) { continue } }
            try await dispatch(domain: "climate", service: attribute == "temperature" ? "set_temperature" : "set_" + attribute,
                               data: ["entity_id": .string(entityID), attribute: desired], cleanup: true)
            let deadline = Date().addingTimeInterval(20)
            while true {
                actual = try await read("restoration_" + attribute + "_GET")
                let matches: Bool
                if attribute == "hvac_mode" { matches = actual.state.state == start.state.state }
                else if attribute == "preset_mode" { matches = actual.string(attribute) == start.string(attribute) }
                else { matches = actual.value(.value) == start.value(.value) }
                if matches { break }
                guard Date() < deadline else { throw ClimateLiveFailure.timeout("Restoration " + attribute) }
                try await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        let final = try await read("FINAL_GET")
        guard sameSettings(final, start) else { throw ClimateLiveFailure.precondition("Original mode/target/preset NOT restored") }
        note("restored", ["total_calls": .int(calls), "mode": .string(final.state.state), "temperature": .double(final.value(.value)!), "preset": .string(final.string("preset_mode")!)])
    }

    func finish() async {
        controller.close()
        await coordinator?.stop()
        coordinator = nil
        await model?.stop()
        await client.disconnect()
    }
}
