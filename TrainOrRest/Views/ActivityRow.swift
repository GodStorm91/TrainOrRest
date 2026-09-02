import SwiftUI

struct ActivityRow: View {
    let activity: CompletedActivity
    @AppStorage(CoachLanguage.storageKey) private var languageRaw = CoachLanguage.en.rawValue

    private var language: CoachLanguage { CoachLanguage(rawValue: languageRaw) ?? .en }

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: "figure.run")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(activity.effortColor.opacity(0.92), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                dateTime
                Text(language.name(activity.effort).uppercased(with: language.uiLocale))
                    .font(.torLabel(10, .bold))
                    .tracking(0.4)
                    .foregroundStyle(activity.effortColor)
                stats
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.faint)
        }
        .padding(13)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }

    private var dateTime: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                Text(language.shortDate(activity.date))
                    .font(.torHeading(15, .bold))
                    .foregroundStyle(Theme.text)
                Text(language.time(activity.date))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.faint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(language.shortDate(activity.date))
                    .font(.torHeading(15, .bold))
                    .foregroundStyle(Theme.text)
                Text(language.time(activity.date))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.faint)
            }
        }
    }

    private var stats: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                stat(Formatters.kilometers(activity.distanceMeters).replacingOccurrences(of: " km", with: ""), "km")
                divider
                stat(Formatters.pace(activity.avgPaceSecondsPerKm).replacingOccurrences(of: " /km", with: ""), "/km")
                divider
                stat(Formatters.duration(activity.durationSeconds), nil)
            }
            VStack(alignment: .leading, spacing: 4) {
                stat(Formatters.kilometers(activity.distanceMeters).replacingOccurrences(of: " km", with: ""), "km")
                stat(Formatters.pace(activity.avgPaceSecondsPerKm).replacingOccurrences(of: " /km", with: ""), "/km")
                stat(Formatters.duration(activity.durationSeconds), nil)
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(Theme.line).frame(width: 1, height: 14)
    }

    private func stat(_ value: String, _ unit: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(value).font(.torHeading(14, .bold)).foregroundStyle(Theme.text)
            if let unit {
                Text(unit).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.faint)
            }
        }
    }
}
