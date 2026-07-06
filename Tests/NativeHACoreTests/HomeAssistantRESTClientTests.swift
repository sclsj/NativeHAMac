import XCTest
@testable import NativeHACore

final class HomeAssistantRESTClientTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testFetchConfigUsesBearerTokenAndConfigEndpoint() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/config")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")

            let data = Data("""
            {
              "location_name": "Workshop",
              "components": ["api", "mobile_app"]
            }
            """.utf8)
            return (HTTPURLResponse.ok(for: request), data)
        }

        let client = makeClient()
        let config = try await client.fetchConfig()

        XCTAssertEqual(config.locationName, "Workshop")
        XCTAssertEqual(config.components, ["api", "mobile_app"])
    }

    func testCallServicePostsJSONBodyToServiceEndpoint() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/services/light/turn_on")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

            let body = try XCTUnwrap(request.bodyDataForTest)
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            XCTAssertEqual(json?["entity_id"] as? String, "light.desk")
            XCTAssertEqual(json?["brightness"] as? Int, 160)

            let data = Data("""
            [
              {
                "entity_id": "light.desk",
                "state": "on",
                "attributes": {"friendly_name": "Desk"}
              }
            ]
            """.utf8)
            return (HTTPURLResponse.ok(for: request), data)
        }

        let client = makeClient()
        let states = try await client.callService(
            domain: "light",
            service: "turn_on",
            data: [
                "entity_id": "light.desk",
                "brightness": 160,
            ]
        )

        XCTAssertEqual(states.first?.entityId, "light.desk")
        XCTAssertEqual(states.first?.state, "on")
    }

    private func makeClient() -> HomeAssistantRESTClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]

        return HomeAssistantRESTClient(
            configuration: HomeAssistantConfiguration(
                baseURL: URL(string: "http://homeassistant.local:8123")!,
                accessToken: "test-token"
            ),
            session: URLSession(configuration: configuration)
        )
    }
}

private final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let requestHandler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try requestHandler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private extension HTTPURLResponse {
    static func ok(for request: URLRequest) -> HTTPURLResponse {
        HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
    }
}

private extension URLRequest {
    var bodyDataForTest: Data? {
        if let httpBody = httpBody {
            return httpBody
        }

        guard let stream = httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let bytesRead = stream.read(buffer, maxLength: 1024)
            if bytesRead > 0 {
                data.append(buffer, count: bytesRead)
            } else {
                break
            }
        }

        return data
    }
}
