import NativeHACore
import SwiftUI

struct WeatherDetailView: View {
    @EnvironmentObject private var model: DashboardViewModel
    @ObservedObject var coordinator: DashboardWeatherDetailCoordinator
    let state: HAState
    @State private var now: Date
    private let nowProvider: () -> Date
    private let cadenceNanoseconds: UInt64

    init(
        state: HAState,
        coordinator: DashboardWeatherDetailCoordinator,
        now: @escaping () -> Date = { Date() },
        cadenceNanoseconds: UInt64 = 60_000_000_000
    ) {
        self.state = state
        self.coordinator = coordinator
        self.nowProvider = now
        self.cadenceNanoseconds = cadenceNanoseconds
        _now = State(initialValue: now())
    }

    var body: some View {
        let presentation = WeatherDetailPresentationResolver.resolve(
            state: state,
            selectedType: coordinator.selectedType,
            modernEvent: coordinator.modernEvent,
            serverUnitSystem: model.homeAssistantConfig?.unitSystem,
            serverTimeZone: model.homeAssistantConfig?.timeZone,
            preferences: model.frontendLocalePreferences,
            now: now
        )
        VStack(alignment: .leading, spacing: 0) {
            currentConditions(presentation)

            if !presentation.measurements.isEmpty {
                VStack(spacing: 0) {
                    ForEach(presentation.measurements) { measurement in
                        measurementRow(measurement)
                    }
                }
                .padding(.top, 8)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(Text("Weather measurements"))
            }

            if !presentation.supportedTypes.isEmpty,
               let forecast = presentation.forecast {
                forecastSection(
                    forecast,
                    supportedTypes: presentation.supportedTypes
                )
            }

            if let attribution = presentation.attribution {
                Text(attribution)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16)
                    .accessibilityLabel(Text("Weather attribution"))
                    .accessibilityValue(Text(attribution))
            }
        }
        .task {
            now = nowProvider()
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: cadenceNanoseconds)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                now = nowProvider()
            }
        }
    }

    private func currentConditions(_ presentation: WeatherDetailPresentation) -> some View {
        HStack(alignment: .center, spacing: 16) {
            weatherIcon(presentation.icon, size: 64)
                .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 3) {
                Text(presentation.condition)
                    .font(.system(size: 24, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(presentation.relativeLastChanged)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.55))
                    .help(presentation.timestampHelp)
                    .accessibilityLabel(Text("Last changed"))
                    .accessibilityValue(Text(presentation.timestampHelp))
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 4) {
                if let temperature = presentation.temperature {
                    Text(temperature)
                        .font(.system(size: 25, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .accessibilityLabel(Text("Temperature"))
                        .accessibilityValue(Text(temperature))
                }
                if let secondary = presentation.secondary {
                    HStack(spacing: 4) {
                        if let symbol = secondary.kind.symbolName {
                            Image(systemName: symbol)
                                .font(.system(size: 11, weight: .semibold))
                        }
                        Text(secondary.value)
                    }
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(.bottom, 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Current weather"))
    }

    private func measurementRow(_ measurement: WeatherDetailMeasurement) -> some View {
        HStack(spacing: 0) {
            Image(systemName: measurement.kind.symbolName)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Color(red: 0.45, green: 0.7, blue: 0.9))
                .frame(width: 32, height: 32)
            Text(measurement.kind.label)
                .font(.system(size: 14))
                .padding(.leading, 16)
            Spacer(minLength: 16)
            Text(measurement.value)
                .font(.system(size: 14, weight: .medium))
                .multilineTextAlignment(.trailing)
        }
        .frame(height: 32)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(measurement.kind.label))
        .accessibilityValue(Text(measurement.value))
    }

    private func forecastSection(
        _ forecast: WeatherDetailForecastPresentation,
        supportedTypes: [HAWeatherForecastType]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Forecast")
                .font(.system(size: 17, weight: .medium))
                .padding(.top, 14)

            if supportedTypes.count > 1 {
                HStack(spacing: 0) {
                    ForEach(supportedTypes, id: \.self) { type in
                        forecastTypeButton(type, selected: forecast.selectedType == type)
                    }
                }
                .background(Color.white.opacity(0.04))
                .cornerRadius(7)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(Text("Forecast type"))
            }

            if forecast.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white.opacity(0.78)))
                        .accessibilityLabel(Text("Loading weather forecast"))
                    Spacer()
                }
                .frame(height: 120)
            } else {
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(alignment: .top, spacing: 6) {
                        ForEach(forecast.groups) { group in
                            forecastGroup(group)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
                }
                .frame(minHeight: 126)
                .accessibilityLabel(Text("Weather forecast, \(forecast.itemCount) items"))
            }
        }
    }

    private func forecastTypeButton(
        _ type: HAWeatherForecastType,
        selected: Bool
    ) -> some View {
        Button(action: { model.selectWeatherForecastType(type) }) {
            Text(type.displayName)
                .font(.system(size: 13, weight: selected ? .semibold : .medium))
                .foregroundColor(selected ? .cyan : .white.opacity(0.68))
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(selected ? Color.white.opacity(0.08) : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(type.displayName))
        .accessibilityValue(Text(selected ? "Selected" : "Not selected"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func forecastGroup(_ group: WeatherDetailForecastGroup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let header = group.header {
                Text(header)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 54)
            }
            HStack(alignment: .top, spacing: 0) {
                ForEach(group.items) { item in
                    VStack(spacing: 4) {
                        Text(item.label)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.58))
                            .lineLimit(1)
                        if let icon = item.icon {
                            weatherIcon(icon, size: 40)
                                .frame(width: 40, height: 40)
                        } else {
                            Color.clear.frame(width: 40, height: 40)
                        }
                        Text(item.high)
                            .font(.system(size: 14, weight: .medium))
                        if let low = item.low {
                            Text(low)
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                    .frame(width: 62)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(forecastItemAccessibility(item)))
                }
            }
        }
    }

    @ViewBuilder
    private func weatherIcon(_ icon: WeatherIconPresentation, size: CGFloat) -> some View {
        if let symbol = icon.symbolName {
            Image(systemName: symbol)
                .font(.system(size: size * 0.72, weight: .semibold))
                .foregroundColor(weatherIconColor(icon.colorRole))
                .accessibilityLabel(Text(icon.semanticLabel))
        } else {
            Text(icon.fallbackText ?? "?")
                .font(.system(size: size * 0.65, weight: .semibold))
                .foregroundColor(weatherIconColor(icon.colorRole))
                .accessibilityLabel(Text(icon.semanticLabel))
        }
    }

    private func forecastItemAccessibility(_ item: WeatherDetailForecastItem) -> String {
        [item.label, item.icon?.semanticLabel, "High \(item.high)", item.low.map { "Low \($0)" }]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}
