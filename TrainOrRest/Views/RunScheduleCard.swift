import SwiftUI

struct RunScheduleCard: View {
    var language: CoachLanguage
    var needsSetup: Bool
    var isLoading: Bool = false
    var failure: WeatherForecastingError? = nil
    var weather: SlotWeather?
    var onSetup: () -> Void
    var onRetry: () -> Void = {}

    var body: some View {
        TodayWeatherEvidenceRow(
            language: language,
            needsSetup: needsSetup,
            isLoading: isLoading,
            failure: failure,
            weather: weather,
            onSetup: onSetup,
            onRetry: onRetry
        )
    }

    static func color(for glyph: WeatherGlyph) -> Color {
        switch glyph {
        case .good: Theme.good
        case .rainRisk, .strongWind, .noSlot: Theme.warn
        case .noData: Theme.dim
        }
    }
}

struct TodayWeatherEvidenceRow: View {
    var language: CoachLanguage
    var needsSetup: Bool
    var isLoading: Bool
    var failure: WeatherForecastingError?
    var weather: SlotWeather?
    var onSetup: () -> Void
    var onRetry: () -> Void

    var body: some View {
        Group {
            if needsSetup {
                Button(action: onSetup) {
                    Label(language.plan.addWeatherForRun, systemImage: "cloud.sun")
                }
                .accessibilityLabel(language.plan.addWeatherForRun)
            } else if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(language.plan.updatingForecast)
                }
                .foregroundStyle(Theme.dim)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(language.plan.updatingForecast)
            } else if let failure {
                Button(action: onRetry) {
                    HStack(spacing: 8) {
                        Label(language.plan.weatherCopy(failure), systemImage: "exclamationmark.triangle")
                        Spacer(minLength: 8)
                        Text(language.plan.weatherRetry)
                    }
                }
                .foregroundStyle(Theme.warn)
                .accessibilityLabel(language.plan.weatherCopy(failure))
                .accessibilityHint(language.plan.weatherRetry)
            } else if let weather {
                let summary = weather.summary(language: language)
                VStack(alignment: .leading, spacing: 4) {
                    Label(summary, systemImage: weather.glyph.systemImage)
                        .foregroundStyle(RunScheduleCard.color(for: weather.glyph))
                        .accessibilityLabel(summary)
                    AppleWeatherAttributionRow(language: language)
                }
            } else {
                Button(action: onRetry) {
                    Label(language.plan.weatherOnNoForecast, systemImage: "questionmark.circle")
                }
                .foregroundStyle(Theme.dim)
                .accessibilityLabel(language.plan.weatherOnNoForecast)
            }
        }
        .font(.footnote.weight(.medium))
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct AppleWeatherAttributionRow: View {
    var language: CoachLanguage

    var body: some View {
        HStack(spacing: 8) {
            Text(language.plan.appleWeatherMark)
            Link(language.plan.weatherLegalSource, destination: WeatherDataAttribution.legalPageURL)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(Theme.dim)
        .accessibilityElement(children: .contain)
    }
}
