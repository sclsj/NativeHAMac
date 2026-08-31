import AppKit
import NativeHACore
import SwiftUI

struct DashboardView: View {
    @StateObject private var model: DashboardViewModel
    @State private var showGraphDemo = false
    private let startsOnAppear: Bool
    private let retryBootstrapOverride: (() -> Void)?
    private let retryLovelaceOverride: (() -> Void)?
    private let reconnectRealtimeOverride: (() -> Void)?

    @MainActor
    init() {
        _model = StateObject(wrappedValue: DashboardViewModel())
        startsOnAppear = true
        retryBootstrapOverride = nil
        retryLovelaceOverride = nil
        reconnectRealtimeOverride = nil
    }

    @MainActor
    init(
        model: DashboardViewModel,
        startsOnAppear: Bool = true,
        retryBootstrapOverride: (() -> Void)? = nil,
        retryLovelaceOverride: (() -> Void)? = nil,
        reconnectRealtimeOverride: (() -> Void)? = nil
    ) {
        _model = StateObject(wrappedValue: model)
        self.startsOnAppear = startsOnAppear
        self.retryBootstrapOverride = retryBootstrapOverride
        self.retryLovelaceOverride = retryLovelaceOverride
        self.reconnectRealtimeOverride = reconnectRealtimeOverride
    }

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                SidebarView()
                    .frame(width: AppConfig.sidebarWidth)

                VStack(spacing: 0) {
                    topBar

                    Divider()
                        .background(Color.white.opacity(0.12))

                    if model.hasLoadedDashboard {
                        lifecycleBanners
                    }

                    content
                }
            }
            .allowsHitTesting(model.selectedEntityID == nil)

            if let selectedEntityID = model.selectedEntityID {
                entityDetailOverlay(entityID: selectedEntityID)
            }
        }
        .background(Color(red: 0.045, green: 0.05, blue: 0.052))
        .foregroundColor(.white)
        .environmentObject(model)
        .animation(.easeOut(duration: 0.12), value: model.selectedEntityID)
        .sheet(isPresented: $showGraphDemo) {
            GraphDemoView()
                .environmentObject(model)
        }
        .onAppear {
            if startsOnAppear {
                model.viewDidAppear()
            }
        }
        .onDisappear {
            guard startsOnAppear else { return }
            model.viewDidDisappear()
        }
    }

    private func entityDetailOverlay(entityID: String) -> some View {
        ZStack {
            Color.black.opacity(0.46)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    model.closeDetails()
                }

            EntityDetailSheet(entityID: entityID)
                .environmentObject(model)
                .shadow(color: Color.black.opacity(0.38), radius: 24, x: 0, y: 14)
        }
        .transition(.opacity)
        .zIndex(10)
    }

    private var topBar: some View {
        HStack(spacing: 0) {
            if model.homeView?.subview == true {
                Button(action: { model.navigateBack() }) {
                    Image(systemName: "chevron.left")
                        .frame(width: 42, height: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Back")
                .accessibilityLabel("Back")
            }

            Text(model.navigationItems.first(where: { $0.isSelected })?.title
                ?? model.homeView.map {
                    LovelaceViewNavigation(
                        dashboard: model.presentationDashboard.resolved,
                        currentUserID: nil,
                        policy: AppConfig.lovelaceNavigationPolicy
                    ).displayTitle(for: $0)
                }
                ?? "Dashboard")
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 16)
                .frame(maxWidth: 220, alignment: .leading)

            ForEach(AppConfig.graphHourOptions, id: \.self) { hours in
                Button(action: {
                    AppLog("Switched graph hours to \(hours)", category: .interaction)
                    model.setGraphHours(hours)
                }) {
                    Text("\(hours)h")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 54, height: 48)
                        .contentShape(Rectangle())
                        .foregroundColor(model.selectedGraphHours == hours ? .white : .white.opacity(0.62))
                        .background(
                            Rectangle()
                                .fill(model.selectedGraphHours == hours ? Color.white.opacity(0.08) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Toggle("IDs", isOn: $model.showEntityIDs)
                .toggleStyle(.checkbox)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.62))
                .padding(.trailing, 14)

            Button("Graph Demo") {
                showGraphDemo = true
            }
            .buttonStyle(.plain)
            .padding(.trailing, 12)

            Button(action: {
                model.refreshHistories()
            }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh history graphs")
            .padding(.trailing, 12)

            if let activeBaseURL = model.activeBaseURL {
                Text(activeBaseURL.host ?? activeBaseURL.absoluteString)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.52))
                    .padding(.trailing, 12)
            }

            statusPill
                .padding(.trailing, 18)
        }
        .frame(height: 50)
        .background(Color(red: 0.09, green: 0.095, blue: 0.095))
    }

    private var statusPill: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(model.lifecycle.phase == .ready ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(model.status)
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.08))
        .cornerRadius(7)
    }

    @ViewBuilder
    private var content: some View {
        let columns = model.dashboardColumns
        if model.lifecycle.phase == .failed && !model.hasLoadedDashboard {
            fatalErrorView
        } else if columns.allSatisfy(\.isEmpty) {
            if model.hasLoadedDashboard {
                VStack(spacing: 10) {
                    Image(systemName: "rectangle.stack.badge.minus")
                        .font(.system(size: 24))
                        .foregroundColor(.white.opacity(0.48))
                    Text(model.activePresentationView == nil
                        ? "No dashboard view is available"
                        : "This view has no cards")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.85)
                    Text(model.status)
                        .foregroundColor(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if model.activePresentationView?.resolved.source.panel == true ||
                    model.activePresentationView?.resolved.source.type == "panel"
        {
            ScrollView(.vertical) {
                if let card = columns.first?.first {
                    CardRenderer(card: card)
                        .frame(maxWidth: .infinity)
                        .padding(AppConfig.dashboardOuterPadding)
                }
            }
        } else {
            ScrollView([.vertical, .horizontal]) {
                HStack(alignment: .top, spacing: AppConfig.dashboardColumnSpacing) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                        VStack(spacing: AppConfig.dashboardColumnSpacing) {
                            ForEach(column, id: \.nativeID) { card in
                                CardRenderer(card: card)
                                    .frame(width: AppConfig.dashboardColumnWidth)
                            }
                        }
                    }
                }
                .padding(AppConfig.dashboardOuterPadding)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private var fatalErrorView: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 30))
                .foregroundColor(.yellow)
            Text("NativeHA could not start")
                .font(.system(size: 18, weight: .semibold))
            Text(model.errorMessage ?? "The dashboard bootstrap failed.")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            Module05ShellAccessibilityButton(
                title: "Retry connection",
                accessibilityLabel: "Retry dashboard connection",
                identifier: "nativeha.shell.retry-bootstrap",
                isDefaultAction: true,
                action: retryBootstrap
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var lifecycleBanners: some View {
        if model.lifecycle.phase == .reconnecting {
            statusBanner("Reconnecting; showing the last accepted dashboard", icon: "arrow.triangle.2.circlepath")
        } else if model.lifecycle.phase == .disconnected {
            HStack {
                statusBanner("Disconnected; showing the last accepted dashboard", icon: "wifi.slash")
                Module05ShellAccessibilityButton(
                    title: "Reconnect",
                    accessibilityLabel: "Reconnect realtime connection",
                    identifier: "nativeha.shell.reconnect-realtime",
                    action: reconnectRealtime
                )
                    .padding(.trailing, 14)
            }
            .background(Color.orange.opacity(0.12))
        }
        ForEach(model.componentFailures, id: \.0) { component, message in
            componentErrorBanner(component: component, message: message)
        }
    }

    private func statusBanner(_ message: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon).foregroundColor(.orange)
            Text(message).font(.system(size: 13))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Color.orange.opacity(0.12))
    }

    private func componentErrorBanner(component: DashboardComponent, message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.yellow)
            Text("\(component.rawValue.capitalized): \(message)")
                .font(.system(size: 13))
                .lineLimit(2)
            Spacer()
            if component == .lovelace {
                Module05ShellAccessibilityButton(
                    title: "Retry",
                    accessibilityLabel: "Retry Lovelace configuration",
                    identifier: "nativeha.shell.retry-lovelace",
                    action: retryLovelace
                )
            } else if component == .bootstrap {
                Module05ShellAccessibilityButton(
                    title: "Retry",
                    accessibilityLabel: "Retry dashboard connection",
                    identifier: "nativeha.shell.retry-bootstrap",
                    action: retryBootstrap
                )
            } else if component == .entities || component == .realtime {
                Module05ShellAccessibilityButton(
                    title: "Reconnect",
                    accessibilityLabel: "Reconnect realtime connection",
                    identifier: "nativeha.shell.reconnect-realtime",
                    action: reconnectRealtime
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.yellow.opacity(0.12))
    }

    private func retryBootstrap() {
        if let retryBootstrapOverride = retryBootstrapOverride {
            retryBootstrapOverride()
        } else {
            model.retryBootstrap()
        }
    }

    private func retryLovelace() {
        if let retryLovelaceOverride = retryLovelaceOverride {
            retryLovelaceOverride()
        } else {
            model.retryLovelace()
        }
    }

    private func reconnectRealtime() {
        if let reconnectRealtimeOverride = reconnectRealtimeOverride {
            reconnectRealtimeOverride()
        } else {
            model.reconnectRealtime()
        }
    }
}

private struct Module05ShellAccessibilityButton: View {
    let title: String
    let accessibilityLabel: String
    let identifier: String
    var isDefaultAction = false
    let action: () -> Void

    var body: some View {
        Representable(
            title: title,
            accessibilityLabel: accessibilityLabel,
            identifier: identifier,
            isDefaultAction: isDefaultAction,
            action: action
        )
        // NSViewRepresentable otherwise accepts the HStack/VStack's complete
        // proposal even though NSButton has a compact intrinsic size. Keeping
        // both axes ideal-sized prevents shell actions from inflating retained
        // banners or the fatal-error page while preserving the concrete AppKit
        // accessibility element and its complete hit bounds.
        .fixedSize(horizontal: true, vertical: true)
    }

    private struct Representable: NSViewRepresentable {
        let title: String
        let accessibilityLabel: String
        let identifier: String
        let isDefaultAction: Bool
        let action: () -> Void

        func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

        func makeNSView(context: Context) -> Module05ShellAccessibilityNSButton {
            let button = Module05ShellAccessibilityNSButton(frame: .zero)
            button.target = context.coordinator
            button.action = #selector(Coordinator.activate)
            configure(button)
            return button
        }

        func updateNSView(_ button: Module05ShellAccessibilityNSButton, context: Context) {
            context.coordinator.parent = self
            configure(button)
        }

        private func configure(_ button: Module05ShellAccessibilityNSButton) {
            button.title = title
            button.bezelStyle = isDefaultAction ? .rounded : .inline
            button.keyEquivalent = isDefaultAction ? "\r" : ""
            button.setContentHuggingPriority(.required, for: .horizontal)
            button.setContentHuggingPriority(.required, for: .vertical)
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
            button.setContentCompressionResistancePriority(.required, for: .vertical)
            button.setAccessibilityElement(true)
            button.setAccessibilityRole(.button)
            button.setAccessibilityLabel(accessibilityLabel)
            button.setAccessibilityIdentifier(identifier)
        }

        final class Coordinator: NSObject {
            var parent: Representable
            init(parent: Representable) { self.parent = parent }
            @objc func activate() { parent.action() }
        }
    }
}

final class Module05ShellAccessibilityNSButton: NSButton {
    override var acceptsFirstResponder: Bool { isEnabled && !isHidden }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 49:
            performClick(self)
        default:
            super.keyDown(with: event)
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject private var model: DashboardViewModel
    @State private var focusedIdentity: LovelaceResolvedIdentity?
    private let focusedIdentityForRendering: LovelaceResolvedIdentity?
    private let focusObserver: ((LovelaceResolvedIdentity?) -> Void)?

    init(
        focusedIdentityForRendering: LovelaceResolvedIdentity? = nil,
        focusObserver: ((LovelaceResolvedIdentity?) -> Void)? = nil
    ) {
        self.focusedIdentityForRendering = focusedIdentityForRendering
        self.focusObserver = focusObserver
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "line.3.horizontal")
                    .foregroundColor(.white.opacity(0.68))
                Text("NativeHA")
                    .font(.system(size: 18, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 50)

            ScrollView(.vertical) {
                VStack(spacing: 4) {
                    ForEach(model.navigationItems) { item in
                        sidebarRow(item)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.top, 8)
            }

            Spacer()
        }
        .background(Color(red: 0.105, green: 0.11, blue: 0.108))
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1),
            alignment: .trailing
        )
    }

    private func sidebarRow(_ item: LovelaceNavigationItem) -> some View {
        let isFocused = focusedIdentityForRendering == item.identity || focusedIdentity == item.identity
        return ZStack {
            HStack(spacing: 12) {
                if item.displayMode != .title {
                    Image(systemName: nativeSymbol(for: item.rawIcon))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(item.isSelected ? Color.cyan : Color.white.opacity(0.64))
                        .frame(width: 22)
                }
                if item.displayMode != .icon {
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundColor(item.isSelected ? Color.cyan : Color.white.opacity(0.75))
                }
                Spacer()
                if item.isSelected {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.cyan)
                        .frame(width: 3, height: 20)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            SidebarAccessibilityButton(
                identity: item.identity,
                sourceIndex: item.sourceIndex,
                title: item.title,
                isSelected: item.isSelected,
                onActivate: { model.selectView(item.identity) },
                onFocusChange: { focused in
                    if focused {
                        focusedIdentity = item.identity
                        focusObserver?(item.identity)
                    } else if focusedIdentity == item.identity {
                        focusedIdentity = nil
                        focusObserver?(nil)
                    }
                }
            )
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .background(
            item.isSelected
                ? Color.cyan.opacity(0.14)
                : (isFocused ? Color.white.opacity(0.09) : Color.clear)
        )
        .cornerRadius(4)
        .contentShape(Rectangle())
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isFocused ? Color.white.opacity(0.78) : Color.clear, lineWidth: 1.5)
        )
        .help(item.title)
    }

    private func nativeSymbol(for mdiName: String?) -> String {
        switch mdiName {
        case "mdi:home", "mdi:home-outline": return "house.fill"
        case "mdi:weather-cloudy", "mdi:weather-partly-cloudy": return "cloud.sun.fill"
        case "mdi:map", "mdi:map-outline": return "map.fill"
        case "mdi:flash", "mdi:lightning-bolt": return "bolt.fill"
        case "mdi:history": return "clock.arrow.circlepath"
        default: return "square.grid.2x2"
        }
    }
}

private struct SidebarAccessibilityButton: NSViewRepresentable {
    let identity: LovelaceResolvedIdentity
    let sourceIndex: Int
    let title: String
    let isSelected: Bool
    let onActivate: () -> Void
    let onFocusChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> SidebarAccessibilityNSButton {
        let button = SidebarAccessibilityNSButton(frame: .zero)
        button.target = context.coordinator
        button.action = #selector(Coordinator.activate)
        let coordinator = context.coordinator
        button.focusChanged = { focused in
            coordinator.parent.onFocusChange(focused)
        }
        configure(button, context: context)
        return button
    }

    func updateNSView(_ button: SidebarAccessibilityNSButton, context: Context) {
        context.coordinator.parent = self
        configure(button, context: context)
    }

    private func configure(
        _ button: SidebarAccessibilityNSButton,
        context: Context
    ) {
        button.title = ""
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.focusRingType = .none
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.clear.cgColor
        button.setAccessibilityElement(true)
        button.setAccessibilityRole(.button)
        button.setAccessibilityLabel(title)
        button.setAccessibilityIdentifier("nativeha.sidebar.view.\(sourceIndex)")
        button.setAccessibilitySelected(isSelected)
        button.setAccessibilityValue(isSelected ? "selected" : "not selected")
    }

    final class Coordinator: NSObject {
        var parent: SidebarAccessibilityButton

        init(parent: SidebarAccessibilityButton) {
            self.parent = parent
        }

        @objc func activate() {
            parent.onActivate()
        }
    }
}

final class SidebarAccessibilityNSButton: NSButton {
    var focusChanged: ((Bool) -> Void)?

    override var acceptsFirstResponder: Bool { isEnabled && !isHidden }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { focusChanged?(true) }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { focusChanged?(false) }
        return resigned
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 48:
            moveSidebarFocus(backward: event.modifierFlags.contains(.shift))
        case 36, 49:
            performClick(self)
        default:
            super.keyDown(with: event)
        }
    }

    private func moveSidebarFocus(backward: Bool) {
        guard let window = window, let contentView = window.contentView else { return }
        var buttons: [SidebarAccessibilityNSButton] = []
        collectSidebarButtons(in: contentView, into: &buttons)
        buttons.sort { lhs, rhs in
            let lhsY = window.convertToScreen(lhs.convert(lhs.bounds, to: nil)).midY
            let rhsY = window.convertToScreen(rhs.convert(rhs.bounds, to: nil)).midY
            return lhsY > rhsY
        }
        guard let index = buttons.firstIndex(where: { $0 === self }), !buttons.isEmpty else {
            return
        }
        let offset = backward ? -1 : 1
        let nextIndex = (index + offset + buttons.count) % buttons.count
        window.makeFirstResponder(buttons[nextIndex])
    }

    private func collectSidebarButtons(
        in view: NSView,
        into buttons: inout [SidebarAccessibilityNSButton]
    ) {
        if let button = view as? SidebarAccessibilityNSButton {
            buttons.append(button)
        }
        for subview in view.subviews {
            collectSidebarButtons(in: subview, into: &buttons)
        }
    }
}
