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

    static var graphRenderEngine: GraphRenderEngine = .coreGraphics

    static let showEntityIDsByDefault = false
    static let graphTimeRangePolicy = GraphTimeRangePolicy(
        availableSelections: [1, 3, 6, 12].map(GraphTimeRange.init(hours:)),
        defaultSelection: GraphTimeRange(hours: 1),
        scope: .global,
        detailDefault: GraphTimeRange(hours: 24),
        allowsExpansionBeyondSelection: false,
        maximumExpansion: nil,
        expansionGestureThreshold: nil
    )
    static var defaultGraphHours: Int { graphTimeRangePolicy.defaultSelection.hours }
    static var graphHourOptions: [Int] { graphTimeRangePolicy.availableSelections.map(\.hours) }
    static let graphMaxZoomVisibleSamplePercentage: CGFloat = 0.10
    static let graphRenderSchedulingPolicy = GraphRenderSchedulingPolicy(
        realtimeStateCoalesceNanoseconds: 50_000_000,
        liveDataRenderDelayNanoseconds: 120_000_000,
        liveDataInteractionDeferNanoseconds: 500_000_000
    )
    static let graphInteractionPolicy = GraphInteractionPolicy(
        hoverOverlayDefault: .enabled,
        hoverOverlayEnvironmentVariable: "NATIVEHA_GRAPH_HOVER_OVERLAY"
    )
    static let graphTooltipFormattingPolicy = GraphTooltipFormattingPolicy(
        timePrecision: .homeAssistant,
        numericDigits: nil,
        entityNumericDigits: [:]
    )
    static let webSocketPolicy = WebSocketPolicy(
        commandTimeout: 10,
        receivePolicy: HomeAssistantWebSocketReceivePolicy(
            maximumMessageBytes: 32 * 1_024 * 1_024
        ),
        subscriptionDeliveryCapacity: 256,
        maximumConcurrentCallbackTasks: 4
    )

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

    static let loggingPolicy = LoggingPolicy(
        minimumSeverity: LogSeverityPolicy(
            webSocket: .warning,
            network: .debug,
            rendering: .debug,
            interaction: .debug,
            lifecycle: .debug,
            general: .debug
        ),
        flushIntervalSeconds: 1,
        flushEntryThreshold: 256,
        busyTimeoutMilliseconds: 1_000,
        retryIntervalSeconds: 1
    )
}

enum GraphRenderEngine: Equatable {
    case coreGraphics
    case canvas
    case metal
}

struct GraphTimeRange: Hashable {
    let hours: Int

    init(hours: Int) {
        self.hours = max(hours, 1)
    }
}

enum GraphTimeRangeScope: Equatable {
    case global
}

struct GraphTimeRangePolicy {
    let availableSelections: [GraphTimeRange]
    let defaultSelection: GraphTimeRange
    let scope: GraphTimeRangeScope
    let detailDefault: GraphTimeRange
    /// Module 01 defines the seam but deliberately leaves range expansion to
    /// the later graph-navigation/cache work.
    let allowsExpansionBeyondSelection: Bool
    let maximumExpansion: GraphTimeRange?
    let expansionGestureThreshold: CGFloat?

    func selection(hours: Int) -> GraphTimeRange? {
        availableSelections.first { $0.hours == hours }
    }
}

struct WebSocketPolicy {
    let commandTimeout: TimeInterval
    let receivePolicy: HomeAssistantWebSocketReceivePolicy
    let subscriptionDeliveryCapacity: Int
    let maximumConcurrentCallbackTasks: Int
}

enum GraphHoverOverlayDefault: Equatable {
    case enabled
    case disabled

    var isEnabled: Bool { self == .enabled }
}

struct GraphInteractionPolicy {
    let hoverOverlayDefault: GraphHoverOverlayDefault
    let hoverOverlayEnvironmentVariable: String

    func hoverOverlayEnabled(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        guard let value = environment[hoverOverlayEnvironmentVariable]?.lowercased() else {
            return hoverOverlayDefault.isEnabled
        }
        switch value {
        case "0", "false", "no", "off":
            return false
        case "1", "true", "yes", "on":
            return true
        default:
            return hoverOverlayDefault.isEnabled
        }
    }
}

struct GraphRenderSchedulingPolicy {
    let realtimeStateCoalesceNanoseconds: UInt64
    let liveDataRenderDelayNanoseconds: UInt64
    let liveDataInteractionDeferNanoseconds: UInt64
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
