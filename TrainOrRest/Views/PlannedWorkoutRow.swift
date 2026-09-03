import SwiftUI

struct PlannedWorkoutRow: View {
    let workout: PlannedWorkout

    @AppStorage(CoachLanguage.storageKey) private var languageRaw = CoachLanguage.en.rawValue

    private var language: CoachLanguage { CoachLanguage(rawValue: languageRaw) ?? .en }

    private var isToday: Bool { Calendar.current.isDateInToday(workout.date) }

    private var weekday: String {
        let rawValue = Calendar.current.component(.weekday, from: workout.date)
        let day = Weekday(rawValue: rawValue) ?? .monday
        return language.shortName(day).uppercased()
    }

    private var sessionName: String {
        let kind = workout.kind.map(language.name) ?? language.genericRunLabel
        return "\(kind) · \(Formatters.kilometers(workout.distanceKm * 1000))"
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(weekday)
                .font(.torHeading(15, .bold))
                .foregroundStyle(isToday ? Theme.accent : Theme.dim)
                .frame(width: 34, alignment: .leading)

            Image(systemName: workout.kind?.symbolName ?? "questionmark")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(isToday ? Theme.accent : Theme.faint)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(sessionName)
                    .font(.torHeading(15, .semibold))
                    .foregroundStyle(Theme.text)
                if let band = workout.paceBand {
                    Text(Formatters.paceBand(band))
                        .font(.torMono(11))
                        .foregroundStyle(Theme.faint)
                }
            }

            Spacer(minLength: 8)

            statusBadge
        }
        .padding(.vertical, 6)
        .animation(.easeOut(duration: 0.18), value: workout.statusRaw)
    }

    @ViewBuilder
    private var statusBadge: some View {
        if isToday {
            badge(language.todayLabel.uppercased(), Theme.accent)
        } else {
            badge(language.name(workout.status).uppercased(), workout.status.color)
        }
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.torLabel(10, .bold))
            .tracking(0.6)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.soft(color), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
