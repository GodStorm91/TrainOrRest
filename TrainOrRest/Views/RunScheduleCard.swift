import SwiftUI

struct RunScheduleCard: View {
    var language: CoachLanguage
    var needsSetup: Bool
    var weather: SlotWeather?
    var onSetup: () -> Void

    var body: some View {
        if needsSetup {
            Button(action: onSetup) {
                Label(language.plan.setupRunSchedule, systemImage: "cloud.sun")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .accessibilityLabel(language.plan.setupRunSchedule)
        } else if let weather {
            Label(weather.summary, systemImage: weather.glyph.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Self.color(for: weather.glyph))
                .accessibilityLabel(weather.summary)
        }
    }

    static func color(for glyph: WeatherGlyph) -> Color {
        switch glyph {
        case .good: Theme.good
        case .rainRisk, .strongWind: Theme.warn
        case .noSlot: Theme.warn
        case .noData: Theme.faint
        }
    }
}
