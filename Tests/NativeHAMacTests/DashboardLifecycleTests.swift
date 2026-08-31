import XCTest
@testable import NativeHAMac

final class DashboardLifecycleTests: XCTestCase {
    func testTypedLifecycleProjectsCompatibilityAndKeepsComponentErrorsIndependent() {
        var lifecycle = DashboardLifecycle()
        XCTAssertEqual(lifecycle.phase, .idle)
        XCTAssertEqual(lifecycle.compatibilityStatus, "Starting")

        lifecycle.begin()
        XCTAssertEqual(lifecycle.phase, .connecting)
        lifecycle.loading()
        XCTAssertEqual(lifecycle.compatibilityStatus, "Loading dashboard")
        lifecycle.installed()
        XCTAssertEqual(lifecycle.compatibilityStatus, "Live")

        lifecycle.set(.lovelace, phase: .failed("config unavailable"))
        XCTAssertEqual(lifecycle.phase, .ready, "A component failure must not erase usable installed data")
        XCTAssertEqual(lifecycle.components[.entities], .ready)
        XCTAssertEqual(lifecycle.primaryErrorMessage, "Lovelace: config unavailable")

        lifecycle.connectionChanged(.reconnecting)
        XCTAssertEqual(lifecycle.phase, .reconnecting)
        XCTAssertEqual(lifecycle.components[.entities], .reconnecting)
        lifecycle.connectionChanged(.ready)
        XCTAssertEqual(lifecycle.phase, .reconnecting, "Socket ready alone must not imply entity freshness")
        lifecycle.set(.entities, phase: .ready)
        XCTAssertEqual(lifecycle.phase, .reconnecting, "Entity freshness alone must not imply Lovelace freshness")
        lifecycle.set(.lovelace, phase: .ready)
        XCTAssertEqual(lifecycle.phase, .ready)

        lifecycle.stop()
        XCTAssertEqual(lifecycle.phase, .stopped)
        XCTAssertTrue(lifecycle.components.values.allSatisfy { $0 == .stopped })
    }

    func testInvalidConnectionTransitionDoesNotPromoteLifecycle() {
        var lifecycle = DashboardLifecycle()
        lifecycle.connectionChanged(.failed)
        XCTAssertEqual(lifecycle.phase, .idle)
        lifecycle.failBootstrap("missing token")
        XCTAssertEqual(lifecycle.phase, .failed)
        XCTAssertEqual(lifecycle.primaryErrorMessage, "Bootstrap: missing token")
    }
}
