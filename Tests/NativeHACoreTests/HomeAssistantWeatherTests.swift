import XCTest
@testable import NativeHACore

final class HomeAssistantWeatherTests: XCTestCase {
    func testSupportedFeatureBitsUseReferenceOrderAndIgnoreMalformedValues() {
        XCTAssertEqual(
            HAWeatherForecastFeatures.supportedTypes(in: ["supported_features": .int(7)]),
            [.daily, .twiceDaily, .hourly]
        )
        XCTAssertEqual(
            HAWeatherForecastFeatures.supportedTypes(in: ["supported_features": .int(3)]),
            [.daily, .hourly]
        )
        XCTAssertEqual(
            HAWeatherForecastFeatures.supportedTypes(in: ["supported_features": .string("4")]),
            [.twiceDaily]
        )
        for value in [
            JSONValue.null, .bool(true), .double(1.5), .double(Double.greatestFiniteMagnitude),
            .object([:]), .array([]),
        ] {
            XCTAssertEqual(
                HAWeatherForecastFeatures.supportedTypes(in: ["supported_features": value]),
                []
            )
        }
    }

    func testForecastEventStrictlyDecodesLiveShapeNullShortAndAllOptionals() throws {
        let event = try decode("""
        {
          "type":"daily",
          "forecast":[
            {"datetime":"2026-09-09T00:00:00+08:00","temperature":27.3,"templow":20,"precipitation":0,"precipitation_probability":15,"humidity":78,"condition":"partlycloudy","is_daytime":true,"pressure":1010.5,"wind_speed":10.8},
            {"datetime":"2026-09-10T00:00:00+08:00","templow":"19.5","is_daytime":false},
            {"datetime":"2026-09-11T00:00:00+08:00"}
          ]
        }
        """)
        XCTAssertEqual(event.type, .daily)
        XCTAssertEqual(event.forecast?.count, 3)
        XCTAssertEqual(event.forecast?.first?.temperature, 27.3)
        XCTAssertEqual(event.forecast?.first?.windSpeed, "10.8")
        XCTAssertEqual(event.forecast?[1].temperatureLow, 19.5)
        XCTAssertNil(event.forecast?[2].condition)

        XCTAssertNil(try decode("{\"type\":\"hourly\",\"forecast\":null}").forecast)
        XCTAssertEqual(
            try decode("{\"type\":\"twice_daily\",\"forecast\":[]}").forecast,
            []
        )
        XCTAssertThrowsError(try decode("{\"type\":\"weekly\",\"forecast\":null}"))
        XCTAssertThrowsError(try decode("{\"type\":\"daily\",\"forecast\":[{\"datetime\":\"x\",\"temperature\":true}]}"))
        XCTAssertThrowsError(try decode("{\"type\":\"daily\",\"forecast\":[{\"temperature\":1}]}"))
    }

    func testTypedFacadeSendsExactCommandDeliversMatchingPayloadAndCancels() async throws {
        let transport = ScriptedWebSocketTransport(
            automaticAuthentication: true,
            automaticSubscriptionAcknowledgement: true
        )
        let factory = ScriptedTransportFactory([transport])
        let connection = HomeAssistantWebSocketConnection(
            accessToken: "token-for-test",
            commandTimeoutNanoseconds: 5_000_000_000,
            reconnectDelayNanoseconds: { _ in 60_000_000_000 },
            transportFactory: factory.make
        )
        let client = HomeAssistantWebSocketClient(connection: connection)
        try await client.connect()
        let log = WeatherEventLog()
        let owner = try await client.subscribeWeatherForecast(
            entityID: "weather.home",
            type: .hourly,
            onForecast: { await log.append($0) }
        )

        let sentObjects = await transport.sentObjects()
        let command = try XCTUnwrap(
            sentObjects.first {
                $0["type"] == .string("weather/subscribe_forecast")
            }
        )
        XCTAssertEqual(Set(command.keys), ["id", "type", "entity_id", "forecast_type"])
        XCTAssertEqual(command["entity_id"], .string("weather.home"))
        XCTAssertEqual(command["forecast_type"], .string("hourly"))
        let id = try XCTUnwrap(command["id"]?.testInt)

        try await transport.push([
            "id": .int(id),
            "type": .string("event"),
            "event": .object([
                "type": .string("hourly"),
                "forecast": .array((0..<48).map { index in
                    .object([
                        "datetime": .string("2026-09-09T\(String(format: "%02d", index % 24)):00:00+08:00"),
                        "temperature": .double(Double(index)),
                    ])
                }),
            ]),
        ])
        try await waitUntil { await log.count == 1 }
        let delivered = await log.last
        XCTAssertEqual(delivered?.forecast?.count, 48)

        await owner.cancel()
        let snapshot = await connection.debugSnapshot()
        XCTAssertEqual(snapshot.subscriptionCount, 0)
        XCTAssertEqual(snapshot.deliveryOwnerCount, 0)
        await connection.disconnect()
    }

    private func decode(_ json: String) throws -> HAWeatherForecastEvent {
        try JSONDecoder().decode(HAWeatherForecastEvent.self, from: Data(json.utf8))
    }
}

private actor WeatherEventLog {
    private var events: [HAWeatherForecastEvent] = []
    var count: Int { events.count }
    var last: HAWeatherForecastEvent? { events.last }
    func append(_ event: HAWeatherForecastEvent) { events.append(event) }
}
