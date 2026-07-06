import CoreGraphics
import Foundation
import NativeHACore

enum AppConfig {
    static let tokenFilePath = "/Users/jin/Documents/Computer/ha_apikey.txt"

    static let baseURLs: [URL] = [
        URL(string: "http://joyj.me:8123")!,
        URL(string: "http://172.20.200.123:8123")!,
        URL(string: "http://192.168.71.18:8123")!,
    ]

    static let showEntityIDsByDefault = false
    static let defaultGraphHours = 1
    static let graphHourOptions = [1, 3, 6, 12]
    static let renderInteractiveGraphsAtFullResolution = true
    static let realtimeUpdateCoalesceNanoseconds: UInt64 = 50_000_000
    static let liveGraphDataRenderDelayNanoseconds: UInt64 = 120_000_000
    static let liveGraphInteractionDeferNanoseconds: UInt64 = 500_000_000

    static let sidebarWidth: CGFloat = 238
    static let dashboardColumnCount = 3
    static let dashboardColumnWidth: CGFloat = 496
    static let dashboardColumnSpacing: CGFloat = 12
    static let dashboardOuterPadding: CGFloat = 16

    static let hiddenEntityIDs: Set<String> = [
        "sensor.humidity_temp_humidity",
        "sensor.humidity_temp_temperature",
    ]

    static let extraEntitiesByCardTitle: [String: [LovelaceEntityRef]] = [
        "AC Unit Controller": [
            LovelaceEntityRef(entity: "climate.room_ac", name: "Room AC"),
        ],
    ]

    static let climatePresetTargetTemperatures: [String: [String: Double]] = [
        "climate.room_ac": [
            "activity": 23.0,
            "sleep": 23.6,
        ],
    ]

    static let cardColumnRules: [CardColumnRule] = [
        CardColumnRule(column: 0, title: "温湿度"),
        CardColumnRule(column: 0, title: "CO2/VOC"),
        CardColumnRule(column: 1, title: "Temp/Humidity"),
        CardColumnRule(column: 1, entity: "person.joy"),
        CardColumnRule(column: 1, entity: "weather.forecast_wo_de_jia"),
        CardColumnRule(column: 1, entity: "binary_sensor.heater_active"),
        CardColumnRule(column: 2, title: "Sensor"),
        CardColumnRule(column: 2, title: "AC Unit Controller"),
    ]
}

struct CardColumnRule {
    let column: Int
    let title: String?
    let type: String?
    let entity: String?

    init(column: Int, title: String? = nil, type: String? = nil, entity: String? = nil) {
        self.column = column
        self.title = title
        self.type = type
        self.entity = entity
    }

    func matches(_ card: LovelaceCard) -> Bool {
        if let title = title, card.title != title {
            return false
        }

        if let type = type, card.type != type {
            return false
        }

        if let entity = entity, !card.containsEntity(entity) {
            return false
        }

        return true
    }
}

private extension LovelaceCard {
    func containsEntity(_ entityID: String) -> Bool {
        if entity == entityID {
            return true
        }

        if entities?.contains(where: { $0.entity == entityID }) == true {
            return true
        }

        if cards?.contains(where: { $0.containsEntity(entityID) }) == true {
            return true
        }

        return false
    }
}
