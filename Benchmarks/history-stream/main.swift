import Foundation
import NativeHACore

private let initialCount = 20_000
private let chunkCount = 100
private let statesPerChunk = 200
private let iterations = 3
private let entityID = "sensor.history_benchmark"

private let initial: [HACompactHistoryState] = (0..<initialCount).map { index in
    state(sequence: index, timestamp: Double(10_000 + index))
}
private let chunks: [[HACompactHistoryState]] = (0..<chunkCount).map { chunk -> [HACompactHistoryState] in
    let base = 29_900 - chunk * statesPerChunk
    return (0..<statesPerChunk).map { offset in
        state(
            sequence: initialCount + chunk * statesPerChunk + offset,
            timestamp: Double(base + offset)
        )
    }
}

_ = runProduction()
_ = runReferenceStableSort()

let production = measure(iterations: iterations, operation: runProduction)
let reference = measure(iterations: iterations, operation: runReferenceStableSort)

guard production.result == reference.result else {
    fatalError("Candidate outputs differ")
}

let checksum = consume(production.result)
print("fixture initial=\(initialCount) chunks=\(chunkCount)x\(statesPerChunk) final=\(checksum.count)")
print("checksum \(checksum.value)")
print("production-stable-merge-ms \(format(production.samples))")
print("reference-stable-full-sort-ms \(format(reference.samples))")
print(String(format: "speedup-average %.2fx", average(reference.samples) / average(production.samples)))

private func runProduction() -> [HACompactHistoryState] {
    var accumulator = HAHistoryStreamAccumulator(range: nil)
    _ = accumulator.process(HAHistoryStreamMessage(states: [entityID: initial]))
    for chunk in chunks {
        _ = accumulator.process(HAHistoryStreamMessage(states: [entityID: chunk]))
    }
    return accumulator.combinedHistory[entityID] ?? []
}

private func runReferenceStableSort() -> [HACompactHistoryState] {
    var combined = initial
    for chunk in chunks {
        let existingLast = combined.last
        combined.append(contentsOf: chunk)
        if let incomingFirst = chunk.first,
           let existingLast = existingLast,
           incomingFirst.lastUpdatedSeconds < existingLast.lastUpdatedSeconds
        {
            combined = combined.enumerated().sorted { left, right in
                if left.element.lastUpdatedSeconds == right.element.lastUpdatedSeconds {
                    return left.offset < right.offset
                }
                return left.element.lastUpdatedSeconds < right.element.lastUpdatedSeconds
            }.map(\.element)
        }
    }
    return combined
}

private func state(sequence: Int, timestamp: Double) -> HACompactHistoryState {
    HACompactHistoryState(
        state: "state-\(sequence)",
        attributes: sequence % 1_000 == 0 ? ["sequence": .int(sequence)] : [:],
        lastChangedSeconds: sequence % 3 == 0 ? timestamp - 0.125 : nil,
        lastUpdatedSeconds: timestamp + 0.625
    )
}

private func measure(
    iterations: Int,
    operation: () -> [HACompactHistoryState]
) -> (samples: [Double], result: [HACompactHistoryState]) {
    var samples: [Double] = []
    var result: [HACompactHistoryState] = []
    for _ in 0..<iterations {
        let start = DispatchTime.now().uptimeNanoseconds
        result = operation()
        let end = DispatchTime.now().uptimeNanoseconds
        samples.append(Double(end - start) / 1_000_000)
    }
    return (samples, result)
}

private func consume(_ states: [HACompactHistoryState]) -> (count: Int, value: UInt64) {
    var checksum: UInt64 = 14_695_981_039_346_656_037
    for state in states {
        checksum ^= state.lastUpdatedSeconds.bitPattern
        checksum &*= 1_099_511_628_211
        for byte in state.state.utf8 {
            checksum = (checksum ^ UInt64(byte)) &* 1_099_511_628_211
        }
    }
    return (states.count, checksum)
}

private func average(_ values: [Double]) -> Double {
    values.reduce(0, +) / Double(max(values.count, 1))
}

private func format(_ values: [Double]) -> String {
    let samples = values.map { String(format: "%.3f", $0) }.joined(separator: ",")
    return "samples=[\(samples)] average=\(String(format: "%.3f", average(values)))"
}
