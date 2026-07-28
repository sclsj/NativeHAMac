import Foundation
import NativeHACore

private struct TypedEventEnvelope: Decodable {
    let type: String
    let event: HAHistoryStreamMessage?
}

private let iterations = 5

guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: HistoryFetchDecodeBench <captured-stream-event.json>")
}

let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))

func consume(_ message: HAHistoryStreamMessage) -> Int {
    message.states.values.reduce(0) { $0 + $1.count }
}

func currentTwoStageDecode() throws -> Int {
    let generic = try JSONDecoder().decode(JSONValue.self, from: data)
    guard
        case let .object(envelope) = generic,
        let event = envelope["event"]
    else {
        return 0
    }
    let eventData = try JSONEncoder().encode(event)
    return consume(try JSONDecoder().decode(HAHistoryStreamMessage.self, from: eventData))
}

func directTypedDecode() throws -> Int {
    let envelope = try JSONDecoder().decode(TypedEventEnvelope.self, from: data)
    return envelope.event.map(consume) ?? 0
}

private let decodedForProjection = try JSONDecoder().decode(TypedEventEnvelope.self, from: data)
guard let projectionMessage = decodedForProjection.event else {
    fatalError("Captured frame has no history event")
}

func projectToCurrentGraphModel() -> Int {
    HAHistoryProjection.series(
        from: projectionMessage.states,
        orderedEntityIDs: Array(projectionMessage.states.keys).sorted()
    ).reduce(0) { $0 + $1.points.count }
}

func measure(_ operation: () throws -> Int) rethrows -> (samples: [Double], count: Int) {
    var samples: [Double] = []
    var count = 0
    for _ in 0..<iterations {
        let start = DispatchTime.now().uptimeNanoseconds
        count = try operation()
        let end = DispatchTime.now().uptimeNanoseconds
        samples.append(Double(end - start) / 1_000_000_000)
    }
    return (samples, count)
}

func format(_ values: [Double]) -> String {
    let sorted = values.sorted()
    let mean = values.reduce(0, +) / Double(values.count)
    return String(
        format: "mean=%.3fs median=%.3fs min=%.3fs max=%.3fs",
        mean,
        sorted[sorted.count / 2],
        sorted.first ?? 0,
        sorted.last ?? 0
    )
}

_ = try currentTwoStageDecode()
_ = try directTypedDecode()
_ = projectToCurrentGraphModel()
let current = try measure(currentTwoStageDecode)
let direct = try measure(directTypedDecode)
let projection = measure(projectToCurrentGraphModel)
guard current.count == direct.count else {
    fatalError("Decode paths produced different sample counts")
}
guard current.count == projection.count else {
    fatalError("Projection changed the sample count")
}

let currentMean = current.samples.reduce(0, +) / Double(current.samples.count)
let directMean = direct.samples.reduce(0, +) / Double(direct.samples.count)
print("payload_bytes=\(data.count) samples=\(current.count) iterations=\(iterations)")
print("current_generic_then_reencode \(format(current.samples))")
print("direct_typed_envelope       \(format(direct.samples))")
print("compact_to_graph_projection \(format(projection.samples))")
print(String(
    format: "direct_speedup=%.2fx saved=%.3fs",
    currentMean / directMean,
    currentMean - directMean
))
