import Foundation
import Accelerate

let count = 86400
var yValues = (0..<count).map { _ in Double.random(in: 0...100) }

let start = CFAbsoluteTimeGetCurrent()

var minVal: Double = 0
var minIdx: vDSP_Length = 0
var maxVal: Double = 0
var maxIdx: vDSP_Length = 0

// Test vDSP performance on 86400 elements
vDSP_minviD(&yValues, 1, &minVal, &minIdx, vDSP_Length(count))
vDSP_maxviD(&yValues, 1, &maxVal, &maxIdx, vDSP_Length(count))

let end = CFAbsoluteTimeGetCurrent()
print("vDSP took \((end - start) * 1000) ms")
print("Min: \(minVal) at \(minIdx), Max: \(maxVal) at \(maxIdx)")

// Test bucketed performance (2000 buckets of 43 elements)
let start2 = CFAbsoluteTimeGetCurrent()
for i in 0..<2000 {
    let offset = i * 43
    let length = min(43, count - offset)
    if length > 0 {
        yValues.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return }
            vDSP_minviD(base + offset, 1, &minVal, &minIdx, vDSP_Length(length))
            vDSP_maxviD(base + offset, 1, &maxVal, &maxIdx, vDSP_Length(length))
        }
    }
}
let end2 = CFAbsoluteTimeGetCurrent()
print("vDSP 2000 buckets took \((end2 - start2) * 1000) ms")
