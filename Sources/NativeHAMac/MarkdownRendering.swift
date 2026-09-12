import Foundation

struct MarkdownDocument: Equatable {
    let source: String
    var blocks: [MarkdownBlock]
    var fallbackNotice: String?
    static let blank = MarkdownDocument(source: "", blocks: [], fallbackNotice: nil)
}

struct MarkdownBlock: Equatable, Identifiable {
    let id: Int
    var text: AttributedString
    var kind: Kind
    var indentation: Int
    var quoteDepth: Int
    var escapedMarker = false
    var quoteID: Int?
    var listID: Int?
    var looseList = false
    enum Kind: Equatable {
        case paragraph, heading(Int), code, rule
        case list(String, Bool?)
        case tableCell(table: Int, row: Int, column: Int, header: Bool, alignment: Int)
        case alert(String)
    }
}

/// Foundation supplies CommonMark/GFM syntax and inline ranges. Presentation
/// intents are laid out explicitly; they are not flattened into one Text.
enum MarkdownParser {
    static func parse(_ source: String) throws -> MarkdownDocument {
        try Task.checkCancellation()
        let sentinels = Array((0xE000...0xF8FF).compactMap(UnicodeScalar.init).lazy.map(String.init).filter { !source.contains($0) }.prefix(3))
        let sentinel = sentinels.first ?? "NATIVEHA_ESCAPED_BRACKET"
        let looseMarker = sentinels.count > 2 ? sentinels[1] : "NATIVEHA_LOOSE_LIST"
        let emptyCell = sentinels.last ?? "NATIVEHA_EMPTY_CELL"
        var shielded = ""
        let characters = Array(source)
        var cursor = 0
        while cursor < characters.count {
            if characters[cursor] == "\\", cursor + 1 < characters.count {
                let lineStart = characters[..<cursor].lastIndex(of: "\n").map { $0 + 1 } ?? 0
                let before = String(characters[lineStart..<cursor])
                let taskPosition = before.range(of: #"^\s*(?:>\s*)*(?:[-+*]|[0-9]+[.)])\s+$"#, options: .regularExpression) != nil
                if characters[cursor + 1] == "[", taskPosition { shielded += sentinel }
                else { shielded.append(characters[cursor]); shielded.append(characters[cursor + 1]) }
                cursor += 2
            } else { shielded.append(characters[cursor]); cursor += 1 }
        }
        shielded = shielded.replacingOccurrences(of: #"(\n[ \t]*\n[ \t]*(?:[-+*]|[0-9]+[.)])[ \t]+)"#, with: "$1" + looseMarker, options: .regularExpression)
        shielded = fillEmptyTableCells(shielded, marker: emptyCell)
        let attributed = try AttributedString(markdown: shielded,
            options: .init(interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible))
        var blocks: [MarkdownBlock] = []
        var firstOrderedOrdinals: [Int: Int] = [:]
        var seenListItems = Set<Int>()
        var looseListIDs = Set<Int>()
        var seenListIDs = Set<Int>()
        var declaredColumns: [Int: Int] = [:]
        for run in attributed.runs {
            try Task.checkCancellation()
            let inline = run.inlinePresentationIntent
            if run.imageURL != nil || inline?.contains(.inlineHTML) == true || inline?.contains(.blockHTML) == true {
                return MarkdownDocument(source: source, blocks: [],
                    fallbackNotice: "HTML, media and custom elements are not supported yet. Showing the complete source.")
            }
            let components = run.presentationIntent?.components ?? []
            let identifier = components.first?.identity ?? 0
            var text = AttributedString(attributed[run.range])
            let followsListBlank = String(text.characters).contains(looseMarker)
            if followsListBlank { text = AttributedString(String(text.characters).replacingOccurrences(of: looseMarker, with: ""), attributes: run.attributes) }
            let hasEscapedMarker = String(text.characters).hasPrefix(sentinel)
            if String(text.characters).contains(sentinel) {
                let isCode = inline?.contains(.code) == true || components.contains { if case .codeBlock = $0.kind { return true }; return false }
                let replacement = String(text.characters).replacingOccurrences(of: sentinel, with: isCode ? "\\[" : "[")
                text = AttributedString(replacement, attributes: run.attributes)
            }
            if String(text.characters).contains(emptyCell) {
                text = AttributedString(String(text.characters).replacingOccurrences(of: emptyCell, with: ""), attributes: run.attributes)
            }
            text.presentationIntent = nil
            if inline?.contains(.softBreak) == true { text = AttributedString("\n"); text.inlinePresentationIntent = .lineBreak }
            if blocks.last?.id == identifier {
                blocks[blocks.count - 1].text.append(text)
                continue
            }
            var kind = MarkdownBlock.Kind.paragraph
            var indentation = 0
            var quoteDepth = 0
            var quoteID: Int?
            var listID: Int?
            var item: Int?
            var itemID: Int?
            var table = 0, row = 0, column = 0, alignment = 0
            var isTable = false, header = false
            for component in components {
                switch component.kind {
                case let .header(level): kind = .heading(level)
                case .codeBlock: kind = .code
                case .thematicBreak: kind = .rule
                case let .listItem(ordinal): if item == nil { item = ordinal; itemID = component.identity }
                case .unorderedList:
                    if listID == nil { listID = component.identity }
                    indentation += 1
                    if indentation == 1, item != nil, kind == .paragraph { kind = .list("•", nil) }
                case .orderedList:
                    if listID == nil { listID = component.identity }
                    indentation += 1
                    if indentation == 1, let item = item, kind == .paragraph {
                        let first = firstOrderedOrdinals[component.identity] ?? item
                        firstOrderedOrdinals[component.identity] = first
                        kind = .list("\(item - first + 1).", nil)
                    }
                case .blockQuote: quoteDepth += 1; quoteID = component.identity
                case let .tableCell(index): column = index; isTable = true
                case let .tableRow(index): row = index
                case .tableHeaderRow: header = true
                case let .table(columns):
                    table = component.identity
                    declaredColumns[table] = columns.count
                    if column < columns.count {
                        switch columns[column].alignment {
                        case .center: alignment = 1
                        case .right: alignment = 2
                        default: break
                        }
                    }
                default: break
                }
            }
            if let listID = listID {
                if followsListBlank && seenListIDs.contains(listID) { looseListIDs.insert(listID) }
                seenListIDs.insert(listID)
            }
            if let itemID = itemID, !seenListItems.insert(itemID).inserted {
                if let listID = listID { looseListIDs.insert(listID) }
                if case .list = kind { kind = .list("", nil) }
            }
            if isTable { kind = .tableCell(table: table, row: row, column: column, header: header, alignment: alignment) }
            blocks.append(MarkdownBlock(id: identifier, text: text, kind: kind,
                                        indentation: max(0, indentation - 1), quoteDepth: quoteDepth, escapedMarker: hasEscapedMarker, quoteID: quoteID, listID: listID))
        }
        var convertedQuotes = Set<Int>()
        for index in blocks.indices {
            if let listID = blocks[index].listID { blocks[index].looseList = looseListIDs.contains(listID) }
            let plain = String(blocks[index].text.characters)
            if case let .list(marker, _) = blocks[index].kind, !marker.isEmpty,
               !blocks[index].escapedMarker, blocks[index].text.runs.first?.inlinePresentationIntent?.contains(.code) != true,
               plain.hasPrefix("[ ] ") || plain.hasPrefix("[x] ") || plain.hasPrefix("[X] ") {
                blocks[index].kind = .list(marker, !plain.hasPrefix("[ ]"))
                blocks[index].text.removeSubrange(blocks[index].text.startIndex..<blocks[index].text.index(blocks[index].text.startIndex, offsetByCharacters: 4))
            }
        }
        var removedAlertBlocks = Set<Int>()
        for index in blocks.indices {
            guard let quoteID = blocks[index].quoteID, convertedQuotes.insert(quoteID).inserted,
                  let firstRun = blocks[index].text.runs.first else { continue }
            let firstText = String(blocks[index].text[firstRun.range].characters)
            guard let label = ["NOTE", "TIP", "IMPORTANT", "WARNING", "CAUTION"].first(where: { firstText.range(of: "[!\($0)]", options: .caseInsensitive) != nil }) else { continue }
            blocks[index].kind = .alert(label)
            var encounteredList = false
            for child in blocks.indices where blocks[child].quoteID == quoteID {
                var filtered = AttributedString("")
                let original = blocks[child].text
                for run in original.runs {
                    let text = String(original[run.range].characters)
                    if text != firstText && run.inlinePresentationIntent?.contains(.lineBreak) != true {
                        filtered.append(AttributedString(original[run.range]))
                    }
                }
                blocks[child].text = filtered
                if case .list = blocks[child].kind { encounteredList = true }
                if child != index, !encounteredList {
                    blocks[index].text.append(filtered)
                    removedAlertBlocks.insert(blocks[child].id)
                }
            }
        }
        blocks.removeAll { removedAlertBlocks.contains($0.id) }
        // Foundation omits empty table-cell runs. Restore the source table
        // geometry, including completely empty rows, before native layout.
        let tableIDs = blocks.compactMap { block -> Int? in
            if case let .tableCell(table, _, _, _, _) = block.kind { return table }; return nil
        }.reduce(into: [Int]()) { if !$0.contains($1) { $0.append($1) } }
        var syntheticID = -1
        for table in tableIDs {
            let cells = blocks.filter { if case let .tableCell(id, _, _, _, _) = $0.kind { return id == table }; return false }
            let columns = declaredColumns[table] ?? cells.compactMap { cell -> Int? in if case let .tableCell(_, _, column, _, _) = cell.kind { return column }; return nil }.max().map { $0 + 1 } ?? 0
            let maxRow = cells.compactMap { cell -> Int? in if case let .tableCell(_, row, _, _, _) = cell.kind { return row }; return nil }.max() ?? 0
            let rowCount = maxRow + 1
            var completed: [MarkdownBlock] = []
            for row in 0..<rowCount {
                for column in 0..<columns {
                    if let cell = cells.first(where: { if case let .tableCell(_, r, c, _, _) = $0.kind { return r == row && c == column }; return false }) { completed.append(cell) }
                    else {
                        let alignment = cells.compactMap { cell -> Int? in if case let .tableCell(_, _, c, _, a) = cell.kind, c == column { return a }; return nil }.first ?? 0
                        completed.append(MarkdownBlock(id: syntheticID, text: AttributedString(""), kind: .tableCell(table: table, row: row, column: column, header: row == 0, alignment: alignment), indentation: 0, quoteDepth: 0))
                        syntheticID -= 1
                    }
                }
            }
            if let start = blocks.firstIndex(where: { if case let .tableCell(id, _, _, _, _) = $0.kind { return id == table }; return false }) {
                blocks.removeAll { if case let .tableCell(id, _, _, _, _) = $0.kind { return id == table }; return false }
                blocks.insert(contentsOf: completed, at: start)
            }
        }
        return MarkdownDocument(source: source, blocks: blocks, fallbackNotice: nil)
    }
    /// Empty GFM cells have no Foundation runs. A private placeholder gives
    /// every declared cell a presentation intent, then is removed losslessly.
    private static func fillEmptyTableCells(_ source: String, marker: String) -> String {
        var lines = source.components(separatedBy: "\n")
        var fence: String?
        func parts(_ line: String) -> (String, [String]) {
            var text = line
            var prefix = ""
            while let first = text.first, first == " " || first == ">" || first == "\t" { prefix.append(text.removeFirst()) }
            if text.first == "|" { text.removeFirst() }
            if text.last == "|" { text.removeLast() }
            var cells = [String](), cell = "", escaped = false
            for character in text {
                if character == "|", !escaped { cells.append(cell); cell = "" }
                else { cell.append(character) }
                if character == "\\" { escaped.toggle() } else { escaped = false }
            }
            cells.append(cell)
            return (prefix, cells)
        }
        func fill(_ line: String, columns: Int) -> String {
            let (prefix, raw) = parts(line)
            let cells = raw
            guard cells.contains(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return line }
            return prefix + "|" + cells.map { $0.trimmingCharacters(in: .whitespaces).isEmpty ? marker : $0 }.joined(separator: "|") + "|"
        }
        var index = 0
        while index < lines.count {
            let trimmed = lines[index].replacingOccurrences(of: #"^\s*(?:>\s*)+"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
            let fenceCandidate = fence == nil ? trimmed.replacingOccurrences(of: #"^(?:(?:>[ \t]*)|(?:(?:[-+*]|[0-9]+[.)])[ \t]+))+"#, with: "", options: .regularExpression) : trimmed
            if fenceCandidate.hasPrefix("```") || fenceCandidate.hasPrefix("~~~") {
                let marker = fenceCandidate.first!
                let run = String(fenceCandidate.prefix(while: { $0 == marker }))
                if let opened = fence {
                    if marker == opened.first, run.count >= opened.count,
                       fenceCandidate.dropFirst(run.count).trimmingCharacters(in: .whitespaces).isEmpty { fence = nil }
                } else { fence = run }
            }
            let delimiter = parts(lines[index]).1
            let isDelimiter = !delimiter.isEmpty && delimiter.allSatisfy { cell in
                cell.trimmingCharacters(in: .whitespaces).range(of: #"^:?-+:?$"#, options: .regularExpression) != nil
            }
            if fence == nil, index > 0, !lines[index].hasPrefix("    "), !lines[index].hasPrefix("\t"), lines[index].contains("|"), isDelimiter, lines[index - 1].contains("|") {
                let columns = delimiter.count
                lines[index - 1] = fill(lines[index - 1], columns: columns)
                index += 1
                while index < lines.count, lines[index].contains("|"), !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                    let body = lines[index].replacingOccurrences(of: #"^\s*(?:>\s*)+"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
                    if !body.hasPrefix("|"), body.range(of: #"^(?:#{1,6}\s|[-+*]\s|[0-9]+[.)]\s|```|~~~|>)"#, options: .regularExpression) != nil { break }
                    lines[index] = fill(lines[index], columns: columns); index += 1
                }
                continue
            }
            index += 1
        }
        return lines.joined(separator: "\n")
    }

}

actor MarkdownPreparationCache {
    static let shared = MarkdownPreparationCache(byteBudget: AppConfig.markdownPolicy.preparedCacheBytes)
    private var values: [String: MarkdownDocument] = [:]
    private var order: [String] = []
    private var bytes = 0
    private let byteBudget: Int
    init(byteBudget: Int) { self.byteBudget = max(0, byteBudget) }
    func prepare(_ source: String) throws -> MarkdownDocument {
        try Task.checkCancellation()
        if let cached = values[source] { return cached }
        let document = try MarkdownParser.parse(source)
        // Conservative estimate includes source, characters and attributed runs.
        let cost = estimate(document)
        if cost <= byteBudget {
            while bytes + cost > byteBudget, let oldest = order.first {
                order.removeFirst()
                if let removed = values.removeValue(forKey: oldest) { bytes -= estimate(removed) }
            }
            values[source] = document; order.append(source); bytes += cost
        }
        return document
    }
    private func estimate(_ document: MarkdownDocument) -> Int {
        document.source.utf8.count * 4 + document.blocks.reduce(0) { $0 + $1.text.characters.count * 8 + $1.text.runs.count * 256 + 128 }
    }
    var retainedBytes: Int { bytes }
}
