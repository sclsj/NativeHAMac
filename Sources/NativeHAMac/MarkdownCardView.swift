import AppKit
import NativeHACore
import SwiftUI

enum MarkdownLinkTarget: Equatable {
    case view(String), external(URL), inert(String)
}

enum MarkdownLinkPolicy {
    static func classify(_ destination: String, baseURL: URL?, currentViewPath: String?, viewPaths: Set<String>) -> MarkdownLinkTarget {
        guard !destination.isEmpty, !destination.contains(where: { $0.isNewline || $0 == "\0" }) else { return .inert("Invalid link destination") }
        let supportedPrefixes = ["http://", "https://", "mailto:", "tel:", "ftp://", "/", "./", "../", "#"]
        guard supportedPrefixes.contains(where: destination.hasPrefix) else { return .inert("Unsupported link destination: \(destination)") }
        if destination.hasPrefix("#") { return .inert("Document fragment navigation is not supported yet: \(destination)") }
        let server = baseURL ?? AppConfig.baseURLs[0]
        let current = server.appendingPathComponent("lovelace").appendingPathComponent(currentViewPath ?? "default_view")
        guard let url = URL(string: destination, relativeTo: current)?.absoluteURL,
              let scheme = url.scheme, ["http", "https", "mailto", "tel", "ftp"].contains(scheme) else { return .inert("Unsafe link destination: \(destination)") }
        let sameServer = ([server] + AppConfig.baseURLs).contains {
            $0.host?.lowercased() == url.host?.lowercased() && ($0.port ?? ($0.scheme == "https" ? 443 : 80)) == (url.port ?? (scheme == "https" ? 443 : 80))
        }
        if sameServer {
            let parts = url.path.split(separator: "/").map(String.init)
            if parts.count == 2, parts[0] == "lovelace", viewPaths.contains(parts[1]), url.query == nil, url.fragment == nil {
                return .view(parts[1])
            }
            return .inert("Home Assistant destination is not supported: \(destination)")
        }
        return .external(url)
    }
}

enum MarkdownCardAction: Equatable {
    case none, navigate(String), details(String), external(URL), unsupported(String)
}

enum MarkdownActionPolicy {
    static func configured(_ value: JSONValue?) -> Bool {
        guard case let .object(object)? = value else { return false }
        return object["action"] != nil && object["action"] != .string("none")
    }
    static func resolve(_ value: JSONValue?, paths: Set<String>, baseURL: URL?, currentPath: String?) -> MarkdownCardAction {
        guard case let .object(object)? = value, case let .string(action)? = object["action"] else { return .none }
        guard object["confirmation"] == nil else { return .unsupported("Action confirmation is not supported yet") }
        func string(_ key: String) -> String? { if case let .string(value)? = object[key] { return value }; return nil }
        switch action {
        case "none": return .none
        case "more-info":
            guard let entity = string("entity"), !entity.isEmpty else { return .unsupported("More-info requires an explicit entity") }
            return .details(entity)
        case "navigate":
            guard let path = string("navigation_path") else { return .unsupported("Navigation action has no destination") }
            if paths.contains(path) { return .navigate(path) }
            if case let .view(resolved) = MarkdownLinkPolicy.classify(path, baseURL: baseURL, currentViewPath: currentPath, viewPaths: paths) { return .navigate(resolved) }
            return .unsupported("Navigation action destination is not supported")
        case "url":
            guard let path = string("url_path"), case let .external(url) = MarkdownLinkPolicy.classify(path, baseURL: baseURL, currentViewPath: currentPath, viewPaths: paths) else { return .unsupported("URL action destination is not supported") }
            return .external(url)
        default: return .unsupported("The \(action) action is not supported yet")
        }
    }
}

struct MarkdownCard: View {
    @EnvironmentObject private var model: DashboardViewModel
    let card: LovelacePresentationCard
    var body: some View {
        Group {
            if let state = model.markdownState(for: card) {
                MarkdownCardBody(state: state,
                    classify: { model.classifyMarkdownLink($0.absoluteString) },
                    action: { model.resolveMarkdownAction($0) },
                    perform: { model.performMarkdownAction($0) })
            } else {
                Color.clear.frame(height: 32)
            }
        }
    }
}

struct MarkdownCardBody: View {
    @ObservedObject var state: MarkdownCardState
    var classify: (URL) -> MarkdownLinkTarget = { .external($0) }
    var action: (JSONValue?) -> MarkdownCardAction = { _ in .none }
    var perform: (MarkdownCardAction) -> Void = { _ in }
    @State private var linkNotice: String?
    private var card: LovelaceCard { state.card.source }
    private var interactive: Bool { [card.tapAction, card.holdAction, card.doubleTapAction].contains(where: MarkdownActionPolicy.configured) }
    private var unsupportedNotices: [String] {
        [card.tapAction, card.holdAction, card.doubleTapAction].compactMap {
            if case let .unsupported(message) = action($0) { return message }; return nil
        }
    }
    var body: some View {
        if !state.hidden {
            VStack(alignment: .leading, spacing: 8) {
                if let alert = state.alert { notice(alert, warning: state.alertLevel == .warning) }
                if state.phase == .metadataUnavailable { notice("Current user metadata is unavailable. Retry the connection to render this card.", warning: true) }
                ForEach(Array(unsupportedNotices.enumerated()), id: \.offset) { _, text in notice(text, warning: true) }
                if let linkNotice = linkNotice { notice(linkNotice, warning: true) }
                content
                    .overlay(Group {
                        if interactive {
                            MarkdownActionTarget(label: card.title ?? "Markdown card", hasHold: MarkdownActionPolicy.configured(card.holdAction), hasDouble: MarkdownActionPolicy.configured(card.doubleTapAction)) { trigger in
                                let selected = trigger == 1 ? card.holdAction : trigger == 2 ? card.doubleTapAction : card.tapAction
                                perform(action(selected))
                            }
                        }
                    })
            }
        }
    }
    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            if card.textOnly != true, let title = card.title {
                Text(title).font(.system(size: 24)).lineSpacing(8).frame(minHeight: 48, alignment: .leading).padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 16)
            }
            MarkdownDocumentView(document: state.document) { url in
                if interactive { perform(action(card.tapAction)); return }
                switch classify(url) {
                case let .external(url): perform(.external(url))
                case let .view(path): perform(.navigate(path))
                case let .inert(message): linkNotice = message
                }
            }
            .padding(.horizontal, card.textOnly == true ? 4 : 16)
            .padding(.top, card.textOnly == true ? 2 : (card.title == nil ? 16 : 0))
            .padding(.bottom, card.textOnly == true ? 2 : 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card.textOnly == true ? Color.clear : Color(red: 0.095, green: 0.1, blue: 0.1))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(card.textOnly == true ? Color.clear : Color.white.opacity(0.1), lineWidth: 1))
        .cornerRadius(card.textOnly == true ? 0 : 8)
    }
    private func notice(_ text: String, warning: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: warning ? "exclamationmark.triangle" : "exclamationmark.circle").foregroundColor(warning ? .yellow : .red)
            Text(text).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }.font(.system(size: 14)).foregroundColor(.white.opacity(0.88)).padding(12)
            .frame(maxWidth: .infinity, alignment: .leading).background((warning ? Color.yellow : Color.red).opacity(0.12)).cornerRadius(6)
    }
}

struct MarkdownDocumentView: View {
    let document: MarkdownDocument
    var activateLink: (URL) -> Void = { _ in }
    private var tableIDs: Set<Int> {
        Set(document.blocks.compactMap { if case let .tableCell(table, _, _, _, _) = $0.kind { return table }; return nil })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let notice = document.fallbackNotice {
                Text(notice).font(.system(size: 13, weight: .semibold)).foregroundColor(.yellow)
                Text(document.source).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(groups, id: \.first!.id) { group in
                    if let first = group.first {
                        if case let .alert(label) = first.kind {
                            alert(label) { renderBlocks(group, quoteOffset: first.quoteDepth) }
                                .padding(.bottom, blockGap(group.last!))
                        } else if first.quoteID != nil {
                            renderBlocks(group, quoteOffset: 1).padding(.leading, 14)
                                .overlay(Rectangle().fill(Color.white.opacity(0.2)).frame(width: 4), alignment: .leading)
                                .padding(.bottom, blockGap(group.last!))
                        } else { renderBlocks(group).padding(.bottom, blockGap(group.last!)) }
                    }
                }
            }
        }
        .font(.system(size: AppConfig.markdownPolicy.bodySize))
        .foregroundColor(.white.opacity(0.88))
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.openURL, OpenURLAction { url in activateLink(url); return .handled })
    }
    private func rich(_ text: AttributedString) -> some View {
        Text(text).fixedSize(horizontal: false, vertical: true).textSelection(.enabled).lineSpacing(5)
    }
    private func blockGap(_ block: MarkdownBlock) -> CGFloat {
        guard let index = document.blocks.firstIndex(where: { $0.id == block.id }), index + 1 < document.blocks.count else { return 0 }
        if case .list = block.kind, case .list = document.blocks[index + 1].kind { return block.looseList ? AppConfig.markdownPolicy.bodySize * 2 : 5 }
        return AppConfig.markdownPolicy.blockSpacing
    }
    private var groups: [[MarkdownBlock]] {
        document.blocks.reduce(into: [[MarkdownBlock]]()) { result, block in
            if let quote = block.quoteID, result.last?.last?.quoteID == quote { result[result.count - 1].append(block) }
            else if case let .tableCell(table, _, _, _, _) = block.kind,
                    let previous = result.last?.last, case let .tableCell(lastTable, _, _, _, _) = previous.kind, table == lastTable {
                result[result.count - 1].append(block)
            } else { result.append([block]) }
        }
    }
    private func renderBlocks(_ blocks: [MarkdownBlock], quoteOffset: Int = 0) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(blocks) { block in
                if case let .tableCell(table, _, _, _, _) = block.kind {
                    if blocks.first(where: { if case let .tableCell(id, _, _, _, _) = $0.kind { return id == table }; return false })?.id == block.id { tableView(table) }
                } else {
                    blockView(block)
                        .padding(.leading, CGFloat(max(0, block.quoteDepth - quoteOffset)) * 14)
                        .overlay(HStack(spacing: 10) {
                            ForEach(0..<max(0, block.quoteDepth - quoteOffset), id: \.self) { _ in Rectangle().fill(Color.white.opacity(0.2)).frame(width: 4) }
                        }, alignment: .leading)
                        .padding(.bottom, block.id == blocks.last?.id ? 0 : blockGap(block))
                }
            }
        }
    }
    private func alert<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: label == "TIP" ? "checkmark.circle" : label == "WARNING" || label == "CAUTION" ? "exclamationmark.triangle" : "info.circle")
                .font(.system(size: 24)).frame(width: 24, height: 24)
                .foregroundColor(label == "TIP" ? .green : label == "WARNING" ? .yellow : label == "CAUTION" ? .red : .cyan)
            content()
        }.padding(8).frame(maxWidth: .infinity, alignment: .leading).background(Color.cyan.opacity(0.07)).cornerRadius(4)
    }
    @ViewBuilder private func blockView(_ block: MarkdownBlock) -> some View {
        switch block.kind {
        case let .heading(level):
            rich(block.text).font(.system(size: [28.0, 20, 16.38, 14, 11.62, 9.38][min(5, max(0, level - 1))], weight: .bold)).accessibilityAddTraits(.isHeader).padding(.bottom, level == 1 ? 8 : 4)
        case .code:
            ScrollView(.horizontal) {
                Text(block.text).font(.system(size: AppConfig.markdownPolicy.codeSize, design: .monospaced)).fixedSize().textSelection(.enabled).padding(8)
            }.background(Color.black.opacity(0.2)).cornerRadius(4)
        case .rule: Divider().padding(.vertical, 4)
        case let .list(marker, checked):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let checked = checked {
                    Image(systemName: checked ? "checkmark.square.fill" : "square").accessibilityLabel(checked ? "Completed" : "Not completed")
                } else { Text(marker == "•" && block.indentation > 0 ? (block.indentation == 1 ? "◦" : "▪") : marker).frame(minWidth: 15, alignment: .trailing) }
                rich(block.text)
            }.padding(.leading, CGFloat(block.indentation) * AppConfig.markdownPolicy.listIndent + 40)
        case .alert, .paragraph: rich(block.text)
        case .tableCell: EmptyView()
        }
    }
    private func tableView(_ id: Int) -> some View {
        let cells = document.blocks.filter { if case let .tableCell(table, _, _, _, _) = $0.kind { return table == id }; return false }
        let rows = Array(Set(cells.compactMap { cell -> Int? in if case let .tableCell(_, row, _, _, _) = cell.kind { return row }; return nil })).sorted()
        return ScrollView(.horizontal) { VStack(alignment: .leading, spacing: 0) {
            ForEach(rows, id: \.self) { row in
                HStack(alignment: .top, spacing: 0) {
                    ForEach(cells.filter { if case let .tableCell(_, r, _, _, _) = $0.kind { return r == row }; return false }) { cell in
                        if case let .tableCell(_, _, column, header, alignment) = cell.kind {
                            rich(cell.text).font(.system(size: 14, weight: header ? .bold : .regular))
                                .frame(width: tableColumnWidth(cells, column: column), alignment: alignment == 2 ? .trailing : alignment == 1 ? .center : .leading)
                                .frame(minHeight: AppConfig.markdownPolicy.bodySize * 1.6)
                                .padding(.horizontal, 7).padding(.vertical, 3.5).overlay(Rectangle().stroke(Color.white.opacity(0.15)))
                        }
                    }
                }
            }
        }.fixedSize() }
    }
    private func tableColumnWidth(_ cells: [MarkdownBlock], column: Int) -> CGFloat {
        cells.compactMap { cell -> CGFloat? in
            guard case let .tableCell(_, _, c, header, _) = cell.kind, c == column else { return nil }
            return ceil((String(cell.text.characters) as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 14, weight: header ? .bold : .regular)]).width)
        }.max() ?? 0
    }
}

struct MarkdownActionTarget: NSViewRepresentable {
    let label: String
    let hasHold: Bool
    let hasDouble: Bool
    let activate: (Int) -> Void
    func makeNSView(context: Context) -> MarkdownActionButton { MarkdownActionButton(frame: .zero) }
    func updateNSView(_ button: MarkdownActionButton, context: Context) {
        button.setAccessibilityLabel(label); button.hasHold = hasHold; button.hasDouble = hasDouble; button.activate = activate
    }
}

final class MarkdownActionButton: NSButton {
    var activate: (Int) -> Void = { _ in }
    var hasHold = false, hasDouble = false
    private var hold: Timer?, tap: Timer?
    private var held = false
    override init(frame: NSRect) { super.init(frame: frame); configure() }
    required init?(coder: NSCoder) { super.init(coder: coder); configure() }
    private func configure() { title = ""; isTransparent = true; isBordered = false; target = self; action = #selector(pressed) }
    @objc private func pressed() { activate(0) }
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self); held = false
        if hasHold { hold = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in self?.held = true } }
    }
    override func mouseUp(with event: NSEvent) {
        hold?.invalidate(); hold = nil
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        if held { activate(1); held = false; return }
        if hasDouble, event.clickCount >= 2 { tap?.invalidate(); tap = nil; activate(2) }
        else if hasDouble { tap = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in self?.tap = nil; self?.activate(0) } }
        else { activate(0) }
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 49 {
            if hasDouble, tap != nil { tap?.invalidate(); tap = nil; activate(2) }
            else if hasDouble { tap = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in self?.tap = nil; self?.activate(0) } }
            else { activate(0) }
        } else { super.keyDown(with: event) }
    }
    override func mouseDragged(with event: NSEvent) { hold?.invalidate(); hold = nil }
    override func scrollWheel(with event: NSEvent) { hold?.invalidate(); hold = nil; super.scrollWheel(with: event) }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if window == nil { hold?.invalidate(); tap?.invalidate() } }
    deinit { hold?.invalidate(); tap?.invalidate() }
}

extension DashboardViewModel {
    func classifyMarkdownLink(_ destination: String) -> MarkdownLinkTarget {
        MarkdownLinkPolicy.classify(destination, baseURL: activeBaseURL,
            currentViewPath: homeView?.path, viewPaths: Set(views.compactMap(\.path)))
    }
    func resolveMarkdownAction(_ value: JSONValue?) -> MarkdownCardAction {
        MarkdownActionPolicy.resolve(value, paths: Set(views.compactMap(\.path)), baseURL: activeBaseURL, currentPath: homeView?.path)
    }
    func performMarkdownAction(_ action: MarkdownCardAction) {
        switch action {
        case let .navigate(path): navigateToView(path: path)
        case let .details(entity): openDetails(entityID: entity)
        case let .external(url): NSWorkspace.shared.open(url)
        case .none, .unsupported: break
        }
    }
}
