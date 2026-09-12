import AppKit
import SwiftUI
import XCTest
@testable import NativeHACore
@testable import NativeHAMac

final class MarkdownParserTests: XCTestCase {
    private var root: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }
    func testReferenceCorpusAndDeferredSourceArePreserved() throws {
        let data = try Data(contentsOf: root.appendingPathComponent("Tests/Fixtures/Markdown/cases.json"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for fixture in try XCTUnwrap(json["cases"] as? [[String: Any]]) {
            let source = try XCTUnwrap(fixture["source"] as? String)
            let id = try XCTUnwrap(fixture["id"] as? String)
            let document = try MarkdownParser.parse(source)
            XCTAssertEqual(document.source, source, id)
            if fixture["nativeFallback"] != nil || id == "link-entities" {
                XCTAssertNotNil(document.fallbackNotice, id)
                XCTAssertTrue(document.blocks.isEmpty, id)
            } else {
                XCTAssertNil(document.fallbackNotice, id)
                if !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { XCTAssertFalse(document.blocks.isEmpty, id) }
            }
        }
    }
    func testExactAlertConversionOracleAndQuoteListIdentities() throws {
        let data = try Data(contentsOf: root.appendingPathComponent("Tests/Fixtures/Markdown/alert-cases.json"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for fixture in try XCTUnwrap(json["cases"] as? [[String: Any]]) {
            let source = try XCTUnwrap(fixture["source"] as? String)
            let expected = try XCTUnwrap(fixture["expectedAlerts"] as? [[String: Any]])
            let doc = try MarkdownParser.parse(source)
            let alerts = doc.blocks.filter { if case .alert = $0.kind { return true }; return false }
            XCTAssertEqual(alerts.count, expected.count, source)
            if let alert = alerts.first {
                if case let .alert(label) = alert.kind {
                    let type = label == "TIP" ? "success" : label == "WARNING" ? "warning" : label == "CAUTION" ? "error" : "info"
                    XCTAssertEqual(type, expected[0]["type"] as? String, source)
                }
                let actual = doc.blocks.filter { $0.quoteID == alert.quoteID }.reduce(into: "") { result, block in
                    if case .list = block.kind {
                        if !result.hasSuffix("\n") { result += "\n" }
                        result += String(block.text.characters) + "\n"
                    } else { result += String(block.text.characters) }
                }
                XCTAssertEqual(actual, expected[0]["text"] as? String, source)
            }
        }
        let loose = try MarkdownParser.parse("- first\n\n- second")
        XCTAssertTrue(loose.blocks.allSatisfy(\.looseList))
        let quotes = try MarkdownParser.parse("> first\n>\n> second\n\nordinary\n\n> separate")
        XCTAssertEqual(quotes.blocks[0].quoteID, quotes.blocks[1].quoteID)
        XCTAssertNotEqual(quotes.blocks[0].quoteID, quotes.blocks.last?.quoteID)
    }
    func testBlockSemanticsAndReferenceBreaks() throws {
        let document = try MarkdownParser.parse("# Title\n\nfirst\nsecond\n\n~strike~ **bold** `code`\n\n---\n\n> [!note]\n> Message")
        XCTAssertEqual(document.blocks[0].kind, .heading(1))
        XCTAssertEqual(String(document.blocks[1].text.characters), "first\nsecond")
        XCTAssertTrue(document.blocks.contains { $0.kind == .rule })
        XCTAssertTrue(document.blocks.contains { $0.kind == .alert("NOTE") && String($0.text.characters) == "Message" })
        XCTAssertTrue(document.blocks[2].text.runs.contains { $0.inlinePresentationIntent?.contains(.strikethrough) == true })
        let sameLine = try MarkdownParser.parse("> [!note] Same line")
        XCTAssertEqual(sameLine.blocks.first?.kind, .alert("NOTE"))
        XCTAssertEqual(String(sameLine.blocks[0].text.characters), "")
    }
    func testEscapedAndCodeMarkersStayLiteral() throws {
        for source in ["- \\[x] fake", "- `[x]` fake"] {
            let document = try MarkdownParser.parse(source)
            XCTAssertEqual(document.blocks.first?.kind, .list("•", nil), source)
            XCTAssertEqual(String(document.blocks[0].text.characters), "[x] fake")
        }
        for source in ["> \\[!NOTE]\n> text", "> `[!NOTE]`\n> text"] {
            let doc = try MarkdownParser.parse(source)
            XCTAssertTrue(doc.blocks.contains { if case .alert = $0.kind { return true }; return false }, source)
        }
        for source in ["`<video>![x](a)</video>`", "```\n<script>\\[x]\n```", "\\<tag>"] {
            XCTAssertNil(try MarkdownParser.parse(source).fallbackNotice, source)
        }
    }
    func testEscapedLinkDestinationAndStatusEmphasis() throws {
        let linked = try MarkdownParser.parse("[go](https://example.org/a\\[b)")
        XCTAssertTrue(linked.blocks[0].text.runs.first?.link?.absoluteString.contains("a%5Bb") == true)
        let source = try String(contentsOf: root.appendingPathComponent("tools/markdown-reference/status.md"))
        let status = try MarkdownParser.parse(source)
        let paragraph = status.blocks[1].text
        XCTAssertEqual(paragraph.runs.filter { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true }.map { String(paragraph[$0.range].characters) }, ["Heater last run", "8.9"])
    }
    func testListsRenumberAndContinuationDoesNotDuplicateMarker() throws {
        let ordered = try MarkdownParser.parse("3. third\n4. fourth")
        XCTAssertEqual(ordered.blocks.map(\.kind), [.list("1.", nil), .list("2.", nil)])
        let loose = try MarkdownParser.parse("- first\n\n  second paragraph\n\n  - nested\n\n- next")
        XCTAssertEqual(loose.blocks[1].kind, .list("", nil))
        XCTAssertEqual(loose.blocks[2].indentation, 1)
    }
    func testTableRestoresEmptyRowsAndTrailingColumns() throws {
        for source in ["| A | B |\n| - | - |\n| | |", "| A | |\n|---|---|\n| B | |", "| | |\n|-|-|\n| | |", "> | A | |\n> |-|-|\n> | | |"] {
            let table = try MarkdownParser.parse(source)
            XCTAssertEqual(table.blocks.count, 4, source)
            XCTAssertTrue(table.blocks.contains { if case .tableCell(_, 1, 1, false, _) = $0.kind { return true }; return false })
        }
    }
    func testTableLookalikesPreserveCodeAndFollowingHeading() throws {
        let code = "    | A | B |\n    |---|---|\n    | x | y | extra |"
        let parsed = try MarkdownParser.parse(code)
        XCTAssertEqual(parsed.blocks.first?.kind, .code)
        XCTAssertTrue(String(parsed.blocks[0].text.characters).contains("extra"))
        let fencedSource = "````\n```\n| A | |\n|---|---|\n| x | |\n````"
        let fenced = try MarkdownParser.parse(fencedSource)
        XCTAssertEqual(fenced.blocks.count, 1)
        XCTAssertEqual(String(fenced.blocks[0].text.characters), "```\n| A | |\n|---|---|\n| x | |\n")
        for (opener, prefix) in [("- ```", "  "), ("1. ```", "   "), ("> - ```", ">   "), ("> 1. ```", ">    ")] {
            let codeLines = ["| A | |", "|---|---|", "| x | |"]
            let source = opener + "\n" + (codeLines + ["```"]).map { prefix + $0 }.joined(separator: "\n")
            let document = try MarkdownParser.parse(source)
            XCTAssertEqual(document.blocks.count, 1, source)
            XCTAssertEqual(document.blocks.first?.kind, .code, source)
            XCTAssertEqual(String(document.blocks[0].text.characters), codeLines.joined(separator: "\n") + "\n", source)
        }
        let boundary = try MarkdownParser.parse("| A | B |\n| - | - |\n# Heading | text")
        XCTAssertEqual(boundary.blocks.last?.kind, .heading(1))
        XCTAssertEqual(String(boundary.blocks.last!.text.characters), "Heading | text")
    }
    func testLinkAndActionPolicyHasNoSideEffects() {
        let base = URL(string: "http://example.test:8123")!
        let paths: Set<String> = ["home", "other"]
        XCTAssertEqual(MarkdownLinkPolicy.classify("/lovelace/other", baseURL: base, currentViewPath: "home", viewPaths: paths), .view("other"))
        XCTAssertEqual(MarkdownLinkPolicy.classify("./other", baseURL: base, currentViewPath: "home", viewPaths: paths), .view("other"))
        for link in ["javascript:alert(1)", "data:image/png;base64,AAAA", "file:///tmp/a", "HTTPS://outside.test", "relative/path", "#anchor", "/unknown"] {
            guard case .inert = MarkdownLinkPolicy.classify(link, baseURL: base, currentViewPath: "home", viewPaths: paths) else { return XCTFail(link) }
        }
        for action in ["toggle", "perform-action", "call-service", "assist", "fire-dom-event"] {
            guard case .unsupported = MarkdownActionPolicy.resolve(.object(["action": .string(action)]), paths: paths, baseURL: base, currentPath: "home") else { return XCTFail(action) }
        }
        XCTAssertEqual(MarkdownActionPolicy.resolve(.object(["action": .string("more-info"), "entity": .string("sensor.a")]), paths: paths, baseURL: base, currentPath: "home"), .details("sensor.a"))
    }
    func testDecoderSingularSelectorsEmptyAndName() throws {
        for selector in [JSONValue.string("sensor.a"), .array([.string("sensor.a"), .string("sensor.b")])] {
            let card = try markdownCard(content: " ", additions: ["entity_id": selector, "extra": .bool(true)])
            XCTAssertNil(card.diagnostic); XCTAssertEqual(card.templateEntityIDs, selector)
            if case let .object(raw) = card.rawValue { XCTAssertEqual(raw["extra"], .bool(true)) } else { XCTFail() }
        }
        XCTAssertNotNil(try markdownCard(content: "").diagnostic)
        XCTAssertNil(try markdownCard(content: "hello", additions: ["entity_ids": .string("sensor.a")]).templateEntityIDs)
        XCTAssertNil(try JSONDecoder().decode(HACurrentUser.self, from: Data("{\"id\":\"a\"}".utf8)).name)
        XCTAssertEqual(try JSONDecoder().decode(HACurrentUser.self, from: Data("{\"id\":\"a\",\"name\":\"\"}".utf8)).name, "")
    }
}

@MainActor
final class MarkdownRenderingTests: XCTestCase {
    func testProductionStatusAndStateArtifactsAtTwoWidths() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("tools/markdown-reference/status.md"))
        let capture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("Tests/Fixtures/Markdown/live-template-capture.json"))) as? [String: Any])
        let cards = try XCTUnwrap(capture["cards"] as? [[String: Any]])
        let live = try XCTUnwrap((cards[0]["event"] as? [String: Any])?["result"] as? String)
        let core = try String(contentsOf: root.appendingPathComponent("tools/markdown-reference/core.md"))
        for width in [496.0, 320.0] {
            for mode in ["status", "status-text-only", "text-only", "pending", "error", "fallback", "core", "live-result"] {
                var additions: [String: JSONValue] = [:]
                if mode.contains("text-only") { additions["text_only"] = .bool(true) }
                if mode == "pending" { additions["title"] = .string("Pending template") }
                if mode == "error" { additions["title"] = .string("Template result retained") }
                if mode == "core" { additions["title"] = .string("Markdown reference") }
                let content = mode == "core" ? core : ["live-result", "error", "text-only"].contains(mode) ? live : source
                let card = try markdownCard(content: content, additions: additions)
                let state = MarkdownCardState(card: .standalone(card))
                if mode != "pending" {
                    state.document = try MarkdownParser.parse(mode == "fallback" ? "<video src=\"/local/movie.mp4\">Movie</video>" : content)
                }
                if mode == "error" { state.alert = "TemplateError: fixture failure"; state.alertLevel = .error }
                let sizing = NSHostingView(rootView: MarkdownCardBody(state: state).frame(width: width).fixedSize(horizontal: false, vertical: true))
                let height = max(80, ceil(sizing.fittingSize.height))
                let rendered = try MacViewPNGRenderer.render(
                    MarkdownCardBody(state: state).frame(width: width, height: height, alignment: .top)
                        .background(Color(red: 0.055, green: 0.06, blue: 0.06)),
                    size: CGSize(width: width, height: height), displayScale: 2, settleTime: 0.02)
                let bitmap = try XCTUnwrap(NSBitmapImageRep(data: rendered.pngData))
                XCTAssertEqual(bitmap.pixelsWide, Int(width * 2))
                XCTAssertEqual(bitmap.pixelsHigh, Int(height * 2))
                XCTAssertGreaterThan(rendered.nonBackgroundSampleCount, 20)
                let name = "markdown-\(mode)-\(Int(width)).png"
                let directory = root.appendingPathComponent(".build/render-artifacts")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try rendered.pngData.write(to: directory.appendingPathComponent(name))
                try ApprovedVisualReference.compareIfPresent(actualPNG: rendered.pngData, name: name)
            }
        }
    }
}

final class MarkdownPerformanceTests: XCTestCase {
    func testColdOneMegabytePreparation() throws {
        let unit = "# Heading\n\nParagraph with **bold** and a [link](https://example.org).\n\n- first\n- second\n\n"
        let source = String(repeating: unit, count: 1_048_576 / unit.utf8.count + 1)
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()]) {
            let document = try! MarkdownParser.parse(source)
            XCTAssertGreaterThan(document.blocks.count, 10_000)
        }
    }
    func testWarmCacheAndBudget() async throws {
        let source = String(repeating: "Text **bold**\n\n", count: 75_000)
        let cache = MarkdownPreparationCache(byteBudget: 64 * 1_024 * 1_024)
        let initial = try await cache.prepare(source)
        let start = Date()
        for _ in 0..<100 { let prepared = try await cache.prepare(source); XCTAssertEqual(prepared.blocks.count, initial.blocks.count) }
        let duration = Date().timeIntervalSince(start)
        print("Markdown warm 1MB x100: \(duration)s")
        let bytes = await cache.retainedBytes
        XCTAssertLessThanOrEqual(bytes, 64 * 1_024 * 1_024)
        print("Markdown warm fixture source bytes: \(source.utf8.count); estimated retained bytes at 64MiB: \(bytes)")
        let production = MarkdownPreparationCache(byteBudget: AppConfig.markdownPolicy.preparedCacheBytes)
        _ = try await production.prepare(source)
        let productionStart = Date()
        _ = try await production.prepare(source)
        let productionBytes = await production.retainedBytes
        print("Markdown production 16MiB repeated 1MB preparation: \(Date().timeIntervalSince(productionStart))s; retained bytes: \(productionBytes)")
        XCTAssertEqual(productionBytes, 0, "Oversized document is rendered completely but bypasses the production cache")
    }
}

func markdownCard(content: String, additions: [String: JSONValue] = [:]) throws -> LovelaceCard {
    var object = additions; object["type"] = .string("markdown"); object["content"] = .string(content)
    return try LovelaceConfig(rawValue: .object(["views": .array([.object(["cards": .array([.object(object)])])])])).views[0].cards[0]
}

@MainActor
final class MarkdownInteractionTests: XCTestCase {
    func testNativeTapHoldReleaseDoubleAndKeyboardTiming() async throws {
        let button = MarkdownActionButton(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        var actions: [Int] = []
        button.activate = { actions.append($0) }
        func mouse(_ type: NSEvent.EventType, clicks: Int = 1) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: NSPoint(x: 20, y: 20), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
        }
        func key(_ code: UInt16) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: code == 49 ? " " : "\r", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
        }
        button.mouseDown(with: mouse(.leftMouseDown)); button.mouseUp(with: mouse(.leftMouseUp))
        XCTAssertEqual(actions, [0]); actions = []
        button.hasHold = true
        button.mouseDown(with: mouse(.leftMouseDown))
        try await Task.sleep(nanoseconds: 550_000_000)
        XCTAssertTrue(actions.isEmpty, "Hold fires on release")
        button.mouseUp(with: mouse(.leftMouseUp)); XCTAssertEqual(actions, [1]); actions = []
        button.hasDouble = true
        button.mouseDown(with: mouse(.leftMouseDown)); button.mouseUp(with: mouse(.leftMouseUp))
        XCTAssertTrue(actions.isEmpty)
        button.mouseDown(with: mouse(.leftMouseDown, clicks: 2)); button.mouseUp(with: mouse(.leftMouseUp, clicks: 2))
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(actions, [2]); actions = []
        button.keyDown(with: key(36)); XCTAssertTrue(actions.isEmpty)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(actions, [0]); actions = []
        button.keyDown(with: key(49)); button.keyDown(with: key(49))
        XCTAssertEqual(actions, [2])
    }

    func testInteractiveCardOverlayConsumesLinkHitAndExposesAccessibleButton() throws {
        let card = try markdownCard(content: "[Link](https://example.org)", additions: ["title": .string("Action fixture"), "tap_action": .object(["action": .string("more-info"), "entity": .string("sensor.fixture")])])
        let state = MarkdownCardState(card: .standalone(card)); state.document = try MarkdownParser.parse(card.content!)
        var classified = 0, performed = 0
        let host = NSHostingView(rootView: MarkdownCardBody(state: state, classify: { url in classified += 1; return .external(url) }, action: { _ in .details("sensor.fixture") }, perform: { _ in performed += 1 }).frame(width: 320, height: 180))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 180), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host; host.layoutSubtreeIfNeeded()
        func buttons(_ view: NSView) -> [MarkdownActionButton] { (view as? MarkdownActionButton).map { [$0] } ?? view.subviews.flatMap { buttons($0) } }
        let button = try XCTUnwrap(buttons(host).first)
        XCTAssertEqual(button.accessibilityLabel(), "Action fixture")
        XCTAssertTrue(button.acceptsFirstResponder)
        XCTAssertTrue(button.hitTest(NSPoint(x: button.bounds.midX, y: button.bounds.midY)) === button)
        button.performClick(nil)
        XCTAssertEqual(performed, 1); XCTAssertEqual(classified, 0)
        window.contentView = nil
    }
}
