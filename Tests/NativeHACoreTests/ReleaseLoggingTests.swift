#if !DEBUG
import XCTest
import NativeHACore

final class ReleaseLoggingTests: XCTestCase {
    func testReleaseNeverEvaluatesDiagnosticMessages() {
        var evaluations = 0
        func message() -> String {
            evaluations += 1
            return "must not be evaluated"
        }
        for severity: LogSeverity in [.debug, .info, .warning, .error] {
            for category: LogCategory in [.webSocket, .network, .rendering, .interaction, .lifecycle, .general] {
                AppLog(message(), severity: severity, category: category)
            }
        }
        XCTAssertEqual(evaluations, 0)
    }
}
#endif
