import Foundation

struct HAWebSocketScannedEnvelope: Equatable {
    let objectRange: Range<Int>
    let type: String?
    let id: Int?
    let eventRange: Range<Int>?
    let canRouteDirectly: Bool
}

enum HAWebSocketEnvelopeScanner {
    static func scan(_ data: Data) throws -> [HAWebSocketScannedEnvelope] {
        try data.withUnsafeBytes { rawBuffer in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            var scanner = Scanner(bytes: bytes)
            return try scanner.scan()
        }
    }
}

private struct Scanner {
    private let bytes: UnsafeBufferPointer<UInt8>
    private var index = 0

    init(bytes: UnsafeBufferPointer<UInt8>) {
        self.bytes = bytes
    }

    mutating func scan() throws -> [HAWebSocketScannedEnvelope] {
        skipWhitespace()
        let envelopes: [HAWebSocketScannedEnvelope]
        switch peek() {
        case Self.openBrace:
            envelopes = [try scanEnvelope()]
        case Self.openBracket:
            envelopes = try scanEnvelopeArray()
        default:
            throw HomeAssistantWebSocketError.invalidMessage
        }
        skipWhitespace()
        guard index == bytes.count else {
            throw HomeAssistantWebSocketError.invalidMessage
        }
        return envelopes
    }

    private mutating func scanEnvelopeArray() throws -> [HAWebSocketScannedEnvelope] {
        try consume(Self.openBracket)
        skipWhitespace()
        if peek() == Self.closeBracket {
            index += 1
            return []
        }

        var envelopes: [HAWebSocketScannedEnvelope] = []
        while true {
            skipWhitespace()
            guard peek() == Self.openBrace else {
                throw HomeAssistantWebSocketError.invalidMessage
            }
            envelopes.append(try scanEnvelope())
            skipWhitespace()
            if peek() == Self.comma {
                index += 1
                continue
            }
            try consume(Self.closeBracket)
            return envelopes
        }
    }

    private mutating func scanEnvelope() throws -> HAWebSocketScannedEnvelope {
        let objectStart = index
        try consume(Self.openBrace)
        skipWhitespace()

        var type: String?
        var id: Int?
        var eventRange: Range<Int>?
        var canRouteDirectly = true

        if peek() == Self.closeBrace {
            index += 1
            return HAWebSocketScannedEnvelope(
                objectRange: objectStart..<index,
                type: nil,
                id: nil,
                eventRange: nil,
                canRouteDirectly: false
            )
        }

        while true {
            skipWhitespace()
            let keyRange = try scanString()
            skipWhitespace()
            try consume(Self.colon)
            skipWhitespace()
            let valueStart = index
            try skipValue()
            let valueRange = valueStart..<index

            if matchesASCII(keyRange, "type") {
                type = decodedString(in: valueRange)
            } else if matchesASCII(keyRange, "id") {
                id = decodedInteger(in: valueRange)
            } else if matchesASCII(keyRange, "event") {
                eventRange = valueRange
            } else {
                // A standard Home Assistant event envelope contains only
                // id/type/event. Preserve full JSONDecoder validation for any
                // extended or escaped-key envelope we do not recognize.
                canRouteDirectly = false
            }

            skipWhitespace()
            if peek() == Self.comma {
                index += 1
                continue
            }
            try consume(Self.closeBrace)
            return HAWebSocketScannedEnvelope(
                objectRange: objectStart..<index,
                type: type,
                id: id,
                eventRange: eventRange,
                canRouteDirectly: canRouteDirectly &&
                    type != nil &&
                    id != nil &&
                    eventRange != nil
            )
        }
    }

    private mutating func skipValue() throws {
        guard let byte = peek() else {
            throw HomeAssistantWebSocketError.invalidMessage
        }
        switch byte {
        case Self.quote:
            _ = try scanString()
        case Self.openBrace:
            try skipObject()
        case Self.openBracket:
            try skipArray()
        default:
            try skipScalar()
        }
    }

    private mutating func skipObject() throws {
        try consume(Self.openBrace)
        skipWhitespace()
        if peek() == Self.closeBrace {
            index += 1
            return
        }
        while true {
            skipWhitespace()
            _ = try scanString()
            skipWhitespace()
            try consume(Self.colon)
            skipWhitespace()
            try skipValue()
            skipWhitespace()
            if peek() == Self.comma {
                index += 1
                continue
            }
            try consume(Self.closeBrace)
            return
        }
    }

    private mutating func skipArray() throws {
        try consume(Self.openBracket)
        skipWhitespace()
        if peek() == Self.closeBracket {
            index += 1
            return
        }
        while true {
            skipWhitespace()
            try skipValue()
            skipWhitespace()
            if peek() == Self.comma {
                index += 1
                continue
            }
            try consume(Self.closeBracket)
            return
        }
    }

    private mutating func skipScalar() throws {
        let start = index
        while let byte = peek(), !Self.scalarTerminators.contains(byte) {
            index += 1
        }
        guard
            index > start,
            Self.isValidScalar(bytes[start..<index])
        else {
            throw HomeAssistantWebSocketError.invalidMessage
        }
    }

    /// Returns the range inside the quotes. Escaped metadata keys fall back to
    /// generic decoding; escaped content is still skipped correctly.
    private mutating func scanString() throws -> Range<Int> {
        try consume(Self.quote)
        let start = index
        var escaped = false
        while let byte = peek() {
            index += 1
            if escaped {
                if byte == 0x75 {
                    guard index + 4 <= bytes.count else {
                        throw HomeAssistantWebSocketError.invalidMessage
                    }
                    for hexByte in bytes[index..<(index + 4)] where !Self.isHexDigit(hexByte) {
                        throw HomeAssistantWebSocketError.invalidMessage
                    }
                    index += 4
                } else if !Self.simpleEscapeBytes.contains(byte) {
                    throw HomeAssistantWebSocketError.invalidMessage
                }
                escaped = false
                continue
            }
            if byte == Self.backslash {
                escaped = true
            } else if byte == Self.quote {
                return start..<(index - 1)
            } else if byte < 0x20 {
                throw HomeAssistantWebSocketError.invalidMessage
            }
        }
        throw HomeAssistantWebSocketError.invalidMessage
    }

    private func decodedString(in range: Range<Int>) -> String? {
        guard
            range.count >= 2,
            bytes[range.lowerBound] == Self.quote,
            bytes[range.upperBound - 1] == Self.quote
        else { return nil }
        let content = (range.lowerBound + 1)..<(range.upperBound - 1)
        guard !bytes[content].contains(Self.backslash) else { return nil }
        return String(bytes: bytes[content], encoding: .utf8)
    }

    private func decodedInteger(in range: Range<Int>) -> Int? {
        guard !range.isEmpty else { return nil }
        return Int(String(decoding: bytes[range], as: UTF8.self))
    }

    private func matchesASCII(_ range: Range<Int>, _ value: StaticString) -> Bool {
        value.withUTF8Buffer { expected in
            guard range.count == expected.count else { return false }
            for offset in expected.indices where bytes[range.lowerBound + offset] != expected[offset] {
                return false
            }
            return true
        }
    }

    private mutating func skipWhitespace() {
        while let byte = peek(), Self.whitespace.contains(byte) {
            index += 1
        }
    }

    private mutating func consume(_ byte: UInt8) throws {
        guard peek() == byte else {
            throw HomeAssistantWebSocketError.invalidMessage
        }
        index += 1
    }

    private func peek() -> UInt8? {
        index < bytes.count ? bytes[index] : nil
    }

    private static let quote: UInt8 = 0x22
    private static let backslash: UInt8 = 0x5c
    private static let openBrace: UInt8 = 0x7b
    private static let closeBrace: UInt8 = 0x7d
    private static let openBracket: UInt8 = 0x5b
    private static let closeBracket: UInt8 = 0x5d
    private static let comma: UInt8 = 0x2c
    private static let colon: UInt8 = 0x3a
    private static let whitespace: Set<UInt8> = [0x20, 0x09, 0x0a, 0x0d]
    private static let scalarTerminators: Set<UInt8> = whitespace.union([
        comma, closeBrace, closeBracket,
    ])
    private static let simpleEscapeBytes: Set<UInt8> = [
        quote, backslash, 0x2f, 0x62, 0x66, 0x6e, 0x72, 0x74,
    ]

    private static func isHexDigit(_ byte: UInt8) -> Bool {
        (0x30...0x39).contains(byte) ||
            (0x41...0x46).contains(byte) ||
            (0x61...0x66).contains(byte)
    }

    private static func isValidScalar(_ bytes: Slice<UnsafeBufferPointer<UInt8>>) -> Bool {
        if bytes.elementsEqual([0x74, 0x72, 0x75, 0x65]) ||
            bytes.elementsEqual([0x66, 0x61, 0x6c, 0x73, 0x65]) ||
            bytes.elementsEqual([0x6e, 0x75, 0x6c, 0x6c]) {
            return true
        }

        var offset = bytes.startIndex
        if bytes.indices.contains(offset), bytes[offset] == 0x2d {
            offset += 1
        }
        guard bytes.indices.contains(offset) else { return false }

        if bytes[offset] == 0x30 {
            offset += 1
            if bytes.indices.contains(offset), (0x30...0x39).contains(bytes[offset]) {
                return false
            }
        } else {
            guard (0x31...0x39).contains(bytes[offset]) else { return false }
            repeat {
                offset += 1
            } while bytes.indices.contains(offset) && (0x30...0x39).contains(bytes[offset])
        }

        if bytes.indices.contains(offset), bytes[offset] == 0x2e {
            offset += 1
            guard bytes.indices.contains(offset), (0x30...0x39).contains(bytes[offset]) else {
                return false
            }
            repeat {
                offset += 1
            } while bytes.indices.contains(offset) && (0x30...0x39).contains(bytes[offset])
        }

        if bytes.indices.contains(offset), bytes[offset] == 0x65 || bytes[offset] == 0x45 {
            offset += 1
            if bytes.indices.contains(offset), bytes[offset] == 0x2b || bytes[offset] == 0x2d {
                offset += 1
            }
            guard bytes.indices.contains(offset), (0x30...0x39).contains(bytes[offset]) else {
                return false
            }
            repeat {
                offset += 1
            } while bytes.indices.contains(offset) && (0x30...0x39).contains(bytes[offset])
        }

        return offset == bytes.endIndex
    }
}
