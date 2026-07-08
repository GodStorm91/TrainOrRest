import SwiftUI

struct PlannedWorkoutRow: View {
    let workout: PlannedWorkout

    private var isToday: Bool { Calendar.current.isDateInToday(workout.date) }

    private var weekday: String {
        workout.date.formatted(.dateTime.weekday(.abbreviated)).uppercased()
    }

    private var sessionName: String {
        let kind = workout.kind?.displayName ?? workout.kindRaw
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
            badge("TODAY", Theme.accent)
        } else {
            switch workout.status {
            case .done: badge("DONE", Theme.good)
            case .skipped: badge("SKIPPED", Theme.warn)
            case .planned: badge("PLANNED", Theme.dim)
            }
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
