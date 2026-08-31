import SwiftData
import SwiftUI

/// Month calendar of the training plan: a grid of day cells dotted by workout
/// kind, a legend, and a detail card for the selected day. All data is real —
/// dots and detail come from the planned workouts passed in.
struct PlanMonthView: View {
    let workouts: [PlannedWorkout]
    let completedActivities: [CompletedActivity]
    @Binding var monthAnchor: Date
    @Binding var selectedDate: Date
    var onReviewRunInChat: (CompletedActivity) -> Void = { _ in }
    @Query(sort: \RunningShoe.createdAt, order: .reverse) private var shoes: [RunningShoe]

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                todaysCall
                monthNav
                weekdayRow
                grid
                legend
                selectedDayDetail
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Month navigation

    private var monthNav: some View {
        HStack(spacing: 12) {
            navButton("chevron.left") { shiftMonth(-1) }
            Text(monthTitle)
                .font(.torHeading(24, .bold))
                .foregroundStyle(Theme.text)
                .contentTransition(.numericText())
            navButton("chevron.right") { shiftMonth(1) }
            Spacer()
        }
    }

    private func navButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.dim)
                .frame(width: 30, height: 30)
                .background(Theme.chip, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var monthTitle: String {
        monthAnchor.formatted(.dateTime.month(.wide).year())
    }

    private func shiftMonth(_ delta: Int) {
        guard let next = calendar.date(byAdding: .month, value: delta, to: monthAnchor) else { return }
        withAnimation(.easeOut(duration: 0.2)) { monthAnchor = next }
    }

    // MARK: - Grid

    private var weekdayRow: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(Array(MonthGrid.weekdaySymbols(calendar).enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.torLabel(11))
                    .foregroundStyle(Theme.faint)
            }
        }
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 3) {
            ForEach(Array(MonthGrid.cells(for: monthAnchor, calendar: calendar).enumerated()), id: \.offset) { _, cell in
                if let date = cell {
                    dayCell(date)
                } else {
                    Color.clear.aspectRatio(1, contentMode: .fit)
                }
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let isToday = calendar.isDateInToday(date)
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isPast = date < calendar.startOfDay(for: .now)
        let kind = workouts(on: date).first?.kind
        let dot = kind?.styleColor ?? .clear

        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                selectedDate = calendar.startOfDay(for: date)
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isToday || isSelected ? Theme.chip : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(cellBorder(isToday: isToday, isSelected: isSelected), lineWidth: 1)
                    )
                VStack(spacing: 5) {
                    Text("\(calendar.component(.day, from: date))")
                        .font(.torHeading(15, .bold))
                        .foregroundStyle(numberColor(isToday: isToday, isPast: isPast, hasWorkout: kind != nil))
                    Circle()
                        .fill(isPast ? dot.opacity(0.4) : dot)
                        .frame(width: 6, height: 6)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(date, kind: kind, isToday: isToday))
    }

    private func cellBorder(isToday: Bool, isSelected: Bool) -> Color {
        if isToday { return Theme.text }
        if isSelected { return Theme.border }
        return .clear
    }

    private func numberColor(isToday: Bool, isPast: Bool, hasWorkout: Bool) -> Color {
        if isToday { return Theme.text }
        if isPast { return Theme.faint }
        return hasWorkout ? Theme.text : Theme.dim
    }

    private func accessibilityLabel(_ date: Date, kind: WorkoutKind?, isToday: Bool) -> String {
        let day = date.formatted(.dateTime.month().day())
        let session = kind?.displayName ?? "Rest"
        return "\(day)\(isToday ? ", today" : ""), \(session)"
    }

    // MARK: - Legend

    private var legend: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 92), spacing: 12, alignment: .leading)],
            alignment: .leading,
            spacing: 10
        ) {
            ForEach(monthKinds, id: \.self) { kind in
                legendItem(color: kind.styleColor, label: kind.displayName)
            }
            legendItem(color: nil, label: "Rest")
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }

    private func legendItem(color: Color?, label: String) -> some View {
        HStack(spacing: 7) {
            Group {
                if let color {
                    Circle().fill(color)
                } else {
                    Circle().strokeBorder(Theme.faint, lineWidth: 1.5)
                }
            }
            .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.dim)
        }
    }

    /// Kinds that actually appear in the displayed month, in canonical order.
    private var monthKinds: [WorkoutKind] {
        let present = Set(
            workouts
                .filter { calendar.isDate($0.date, equalTo: monthAnchor, toGranularity: .month) }
                .compactMap { $0.kind }
        )
        return WorkoutKind.allCases.filter { present.contains($0) }
    }

    // MARK: - Selected day detail

    private var todaysCall: some View {
        let today = calendar.startOfDay(for: .now)
        let dayWorkouts = workouts(on: today)
        let activity = completedActivity(on: today)
        return VStack(alignment: .leading, spacing: 10) {
            TorEyebrow("Today's call").tracking(2)
            if let activity {
                CalendarRunSummaryCard(
                    activity: activity,
                    plannedWorkout: matchedWorkout(for: activity) ?? dayWorkouts.first,
                    compact: false,
                    reviewDestination: AnyView(ChatView(contextualCompletedActivityID: activity.hkUUID)),
                    onReview: { onReviewRunInChat(activity) }
                )
                ForEach(dayWorkouts) { workout in
                    detailCard(workout)
                }
            } else {
                todaysCallHero(workout: dayWorkouts.first)
            }
        }
    }

    /// The bold hero for today's prescription: a graphite-glass card whose peak
    /// is the workout word, not color. Kind reads from the glyph shape and the
    /// word; violet appears only on the interactive Coach action.
    @ViewBuilder
    private func todaysCallHero(workout: PlannedWorkout?) -> some View {
        if let workout {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    Image(systemName: workout.kind?.symbolName ?? "figure.run")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.text)
                        .frame(width: 52, height: 52)
                        .background(Theme.chip, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(workout.kind?.displayName ?? "Run")
                            .font(.torHeading(30, .bold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(subtitle(workout))
                            .font(.torMono(13, .medium))
                            .foregroundStyle(Theme.dim)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 8)
                    statusBadge(workout, isToday: true)
                }
                actionRow(workout)
            }
            .padding(18)
            .torGlass(cornerRadius: 26, tint: .graphite)
        } else {
            HStack(spacing: 14) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 52, height: 52)
                    .background(Theme.chip, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rest day")
                        .font(.torHeading(30, .bold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("Recovery and adaptation")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.dim)
                }
                Spacer(minLength: 8)
            }
            .padding(18)
            .torGlass(cornerRadius: 26, tint: .graphite)
        }
    }

    @ViewBuilder
    private var selectedDayDetail: some View {
        if !calendar.isDateInToday(selectedDate) {
            let dayWorkouts = workouts(on: selectedDate)
            let activity = completedActivity(on: selectedDate)
            VStack(alignment: .leading, spacing: 10) {
                TorEyebrow(selectedDayEyebrow).tracking(2)
                if let activity {
                    CalendarRunSummaryCard(
                        activity: activity,
                        plannedWorkout: matchedWorkout(for: activity) ?? dayWorkouts.first,
                        compact: false,
                        reviewDestination: AnyView(ChatView(contextualCompletedActivityID: activity.hkUUID)),
                        onReview: { onReviewRunInChat(activity) }
                    )
                }
                if dayWorkouts.isEmpty && activity == nil {
                    restCard
                } else {
                    ForEach(dayWorkouts) { workout in
                        detailCard(workout)
                    }
                }
            }
        }
    }

    private var selectedDayEyebrow: String {
        selectedDate.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    private func detailCard(_ workout: PlannedWorkout) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: workout.kind?.symbolName ?? "figure.run")
                    .font(.system(size: 22))
                    .foregroundStyle(workout.kind?.styleColor ?? Theme.accent)
                    .frame(width: 46, height: 46)
                    .background(
                        Theme.soft(workout.kind?.styleColor ?? Theme.accent),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Circle().fill(workout.kind?.styleColor ?? Theme.dim).frame(width: 7, height: 7)
                        TorEyebrow(workout.kind?.displayName ?? "Session").tracking(1.5)
                    }
                    Text(workout.kind?.displayName ?? "Run")
                        .font(.torHeading(17, .bold))
                        .foregroundStyle(Theme.text)
                    Text(subtitle(workout))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.dim)
                    if let shoe = assignedShoe(for: workout) {
                        HStack(spacing: 5) {
                            Image(systemName: "shoeprints.fill")
                            Text(workout.shoeAssignmentSource == .auto ? "\(shoe.displayName) · Auto" : shoe.displayName)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                    }
                }
                Spacer(minLength: 8)
                statusBadge(workout, isToday: false)
            }

            actionRow(workout)
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
    }

    private func actionRow(_ workout: PlannedWorkout) -> some View {
        HStack(spacing: 8) {
            if contextualCoachActionTitle(for: workout) != nil {
                NavigationLink {
                    ChatView(contextualWorkoutID: workout.uuid)
                } label: {
                    Label(contextualCoachActionTitle(for: workout) ?? "Edit with Coach", systemImage: "sparkles")
                        .font(.torHeading(13, .bold))
                        .foregroundStyle(Theme.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(contextualCoachAccessibilityLabel(for: workout))
            }

            NavigationLink {
                WorkoutDetailView(workout: workout)
            } label: {
                Label("Details", systemImage: "chevron.right")
                    .font(.torHeading(13, .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .frame(width: 104, height: 44)
                    .background(Theme.chip, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open workout details")
        }
    }

    private func contextualCoachActionTitle(for workout: PlannedWorkout) -> String? {
        switch workout.status {
        case .planned:
            return workout.isScheduleLocked || workout.kind == .race ? "Review with Coach" : "Edit with Coach"
        case .done:
            return "Review with Coach"
        case .skipped:
            return nil
        }
    }

    private func contextualCoachAccessibilityLabel(for workout: PlannedWorkout) -> String {
        let name = workout.kind?.displayName ?? "workout"
        return "\(contextualCoachActionTitle(for: workout) ?? "Ask Coach") \(name)"
    }

    @ViewBuilder
    private func statusBadge(_ workout: PlannedWorkout, isToday: Bool) -> some View {
        switch workout.status {
        case .done: badge("DONE", Theme.good)
        case .skipped: badge("SKIPPED", Theme.warn)
        case .planned:
            if !isToday { badge("PLANNED", Theme.dim) }
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

    private var restCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 20))
                .foregroundStyle(Theme.dim)
                .frame(width: 46, height: 46)
                .background(Theme.chip, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Rest day")
                    .font(.torHeading(17, .bold))
                    .foregroundStyle(Theme.text)
                Text("Recovery and adaptation")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.dim)
            }
            Spacer()
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }

    private func subtitle(_ workout: PlannedWorkout) -> String {
        var parts = [String(format: "%.2f km", workout.distanceKm)]
        if let band = workout.paceBand { parts.append(Formatters.paceBand(band).replacingOccurrences(of: " /km", with: "/km")) }
        if let seconds = workout.expectedDurationSeconds {
            parts.append("~\(Int((seconds / 60).rounded())) min")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Helpers

    private func workouts(on date: Date) -> [PlannedWorkout] {
        workouts.filter { calendar.isDate($0.date, inSameDayAs: date) }
    }

    private func completedActivity(on date: Date) -> CompletedActivity? {
        completedActivities.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    private func matchedWorkout(for activity: CompletedActivity) -> PlannedWorkout? {
        workouts.first(where: { $0.matchedActivityUUID == activity.hkUUID }) ?? workouts(on: activity.date).first
    }

    private func assignedShoe(for workout: PlannedWorkout) -> RunningShoe? {
        guard let shoeID = workout.shoeID else { return nil }
        return shoes.first { $0.id == shoeID }
    }
}
