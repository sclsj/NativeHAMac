import NativeHACore
import SwiftUI

struct DashboardView: View {
    @StateObject private var model = DashboardViewModel()
    @State private var showGraphDemo = false

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                SidebarView()
                    .frame(width: AppConfig.sidebarWidth)

                VStack(spacing: 0) {
                    topBar

                    Divider()
                        .background(Color.white.opacity(0.12))

                    if let errorMessage = model.errorMessage {
                        errorBanner(errorMessage)
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
            model.start()
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
            topTab("Home", isSelected: true)

            ForEach(AppConfig.graphHourOptions, id: \.self) { hours in
                Button(action: {
                    AppLog("Switched graph hours to \(hours)", category: .interaction)
                    model.setGraphHours(hours)
                }) {
                    Text("\(hours)h")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 54, height: 48)
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

    private func topTab(_ title: String, isSelected: Bool) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 70, height: 46)
                .foregroundColor(isSelected ? .white : .white.opacity(0.62))
            Rectangle()
                .fill(isSelected ? Color.white.opacity(0.8) : Color.clear)
                .frame(height: 3)
        }
    }

    private var statusPill: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(model.status == "Live" ? Color.green : Color.orange)
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
        if columns.allSatisfy(\.isEmpty) {
            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.85)
                Text(model.status)
                    .foregroundColor(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private func errorBanner(_ errorMessage: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)
            Text(errorMessage)
                .font(.system(size: 13))
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.yellow.opacity(0.12))
    }
}

struct SidebarView: View {
    private let primaryItems: [(String, String, Bool)] = [
        ("Overview", "square.grid.2x2", true),
        ("All Devices", "square.grid.2x2", false),
        ("Ultrasonic", "square.grid.2x2", false),
        ("地图", "map", false),
        ("Energy", "bolt.fill", false),
        ("Activity", "list.bullet", false),
        ("History", "chart.bar", false),
        ("HACS", "shippingbox", false),
        ("Media", "play.rectangle", false),
        ("To-do lists", "checklist", false),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "line.3.horizontal")
                    .foregroundColor(.white.opacity(0.68))
                Text("Home Assistant")
                    .font(.system(size: 18, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 50)

            VStack(spacing: 4) {
                ForEach(primaryItems, id: \.0) { item in
                    sidebarRow(title: item.0, symbol: item.1, selected: item.2)
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 8)

            Spacer()

            sidebarRow(title: "Settings", symbol: "gearshape.fill", selected: false, badge: "2")
            sidebarRow(title: "Notifications", symbol: "bell.fill", selected: false)

            HStack(spacing: 12) {
                Circle()
                    .fill(Color(red: 0.68, green: 0.9, blue: 1))
                    .frame(width: 34, height: 34)
                    .overlay(Text("J").font(.system(size: 15, weight: .medium)).foregroundColor(.black))
                Text("Joy")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .background(Color(red: 0.105, green: 0.11, blue: 0.108))
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1),
            alignment: .trailing
        )
    }

    private func sidebarRow(title: String, symbol: String, selected: Bool, badge: String? = nil) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(selected ? Color.cyan : Color.white.opacity(0.64))
                .frame(width: 22)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(selected ? Color.cyan : Color.white.opacity(0.75))
            Spacer()
            if let badge = badge {
                Text(badge)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 18, height: 18)
                    .background(Color.orange)
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .background(selected ? Color.cyan.opacity(0.14) : Color.clear)
        .cornerRadius(4)
    }
}
