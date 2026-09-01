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
    var showsTodaysCall = true
    var displaysOnlyTodaysCall = false
    @Query(sort: \RunningShoe.createdAt, order: .reverse) private var shoes: [RunningShoe]
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private let calendar = Calendar.current
    private let railWidth: CGFloat = 40

    var body: some View {
        if displaysOnlyTodaysCall {
            todaysCall
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if showsTodaysCall {
                        todaysCall
                    }
                    monthNav
                    if horizontalSizeClass == .regular {
                        VStack(alignment: .leading, spacing: 8) {
                            weekdayRow
                            grid
                        }
                        .frame(maxWidth: 7 * 96 + railWidth, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        weekdayRow
                        grid
                    }
                    selectedDayDetail
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
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
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
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
        HStack(spacing: 3) {
            ForEach(Array(MonthGrid.weekdaySymbols(calendar).enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.faint)
                    .frame(maxWidth: .infinity)
            }
            Text("KM")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.faint)
                .frame(width: railWidth, alignment: .leading)
        }
    }

    private var grid: some View {
        VStack(spacing: 3) {
            ForEach(Array(weekRows.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 3) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, cell in
                        if let date = cell {
                            dayCell(date)
                                .frame(maxWidth: .infinity)
                        } else {
                            Color.clear
                                .aspectRatio(1, contentMode: .fit)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    weekLoadRail(week)
                }
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let isToday = calendar.isDateInToday(date)
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isPast = date < calendar.startOfDay(for: .now)
        let kind = workouts(on: date).first?.kind

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
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(numberColor(isToday: isToday, isPast: isPast, hasWorkout: kind != nil))
                    dayMark(kind: kind, isPast: isPast)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(date, kind: kind, isToday: isToday))
    }

    private func dayMark(kind: WorkoutKind?, isPast: Bool) -> some View {
        Group {
            if let kind {
                Image(systemName: kind.symbolName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isPast ? kind.styleColor.opacity(0.4) : kind.styleColor)
            } else {
                Color.clear
            }
        }
        .frame(height: 12)
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

    // MARK: - Weekly rhythm

    /// Month cells grouped into calendar weeks so each row can carry its own
    /// planned volume — the training block's rhythm, read down the month.
    private var weekRows: [[Date?]] {
        let cells = MonthGrid.cells(for: monthAnchor, calendar: calendar)
        return stride(from: 0, to: cells.count, by: 7).map {
            Array(cells[$0..<min($0 + 7, cells.count)])
        }
    }

    /// Planned kilometers for the in-month days of one week row.
    private func weekLoad(_ week: [Date?]) -> Double {
        week.compactMap { $0 }
            .filter { calendar.isDate($0, equalTo: monthAnchor, toGranularity: .month) }
            .flatMap { workouts(on: $0) }
            .reduce(0) { $0 + $1.distanceKm }
    }

    /// The heaviest week in the month, used to scale the volume bars.
    private var peakWeekLoad: Double {
        weekRows.map(weekLoad).max() ?? 0
    }

    /// A week's planned volume: a number plus a cyan bar scaled to the peak
    /// week, so build, recovery, and taper weeks read as a shape down the rail.
    @ViewBuilder
    private func weekLoadRail(_ week: [Date?]) -> some View {
        let km = weekLoad(week)
        if km > 0 {
            VStack(alignment: .leading, spacing: 5) {
                Text("\(Int(km.rounded()))")
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
                Capsule()
                    .fill(Theme.data)
                    .frame(width: barWidth(km), height: 3)
            }
            .frame(width: railWidth, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .center)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Week volume \(Int(km.rounded())) kilometers")
        } else {
            Color.clear.frame(width: railWidth)
        }
    }

    private func barWidth(_ km: Double) -> CGFloat {
        guard peakWeekLoad > 0 else { return 0 }
        let maxBar = railWidth - 4
        return max(4, CGFloat(km / peakWeekLoad) * maxBar)
    }

    // MARK: - Selected day detail

    @ViewBuilder
    private var todaysCall: some View {
        let today = calendar.startOfDay(for: .now)
        let dayWorkouts = workouts(on: today)
        let activity = completedActivity(on: today)
        if verticalSizeClass == .compact {
            compactTodaysCall(activity: activity, workout: dayWorkouts.first)
        } else {
            VStack(alignment: .leading, spacing: 10) {
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
    }

    @ViewBuilder
    private func compactTodaysCall(
        activity: CompletedActivity?,
        workout: PlannedWorkout?
    ) -> some View {
        if let activity {
            NavigationLink {
                ChatView(contextualCompletedActivityID: activity.hkUUID)
            } label: {
                compactTodaysCallRow(
                    symbol: "figure.run",
                    title: "Completed run",
                    metrics: completedSubtitle(activity),
                    compactMetrics: completedCompactSubtitle(activity),
                    tint: Theme.good
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Review completed run with Coach")
        } else if let workout {
            NavigationLink {
                WorkoutDetailView(workout: workout)
            } label: {
                compactTodaysCallRow(
                    symbol: workout.kind?.symbolName ?? "figure.run",
                    title: workout.kind?.displayName ?? "Run",
                    metrics: subtitle(workout),
                    compactMetrics: compactSubtitle(workout),
                    tint: workout.kind?.styleColor ?? Theme.accent
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open today’s \(workout.kind?.displayName ?? "workout")")
        } else {
            compactTodaysCallRow(
                symbol: "moon.zzz.fill",
                title: "Rest day",
                metrics: "Recovery and adaptation",
                compactMetrics: "Recovery",
                tint: Theme.dim,
                showsChevron: false
            )
        }
    }

    private func compactTodaysCallRow(
        symbol: String,
        title: String,
        metrics: String,
        compactMetrics: String,
        tint: Color,
        showsChevron: Bool = true
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(Theme.chip, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.text)
            ViewThatFits(in: .horizontal) {
                Text(metrics)
                    .fixedSize(horizontal: true, vertical: false)
                Text(compactMetrics)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(Theme.dim)
            .frame(maxWidth: .infinity, alignment: .trailing)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.faint)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 52)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }

    /// The bold hero for today's prescription: a graphite-glass card whose peak
    /// is the workout word, not color. Kind reads from the glyph shape and the
    /// word; violet appears only on the interactive Coach action.
    @ViewBuilder
    private func todaysCallHero(workout: PlannedWorkout?) -> some View {
        if let workout {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: workout.kind?.symbolName ?? "figure.run")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.text)
                        .frame(width: 52, height: 52)
                        .background(Theme.chip, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(workout.kind?.displayName ?? "Run")
                            .font(.torHeading(30, .bold))
                            .foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                        workoutMetricLine(workout)
                        if let why = purpose(workout) {
                            Text(why)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(Theme.dim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        receiptLine(workout)
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
                    Text("Recovery and adaptation")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.dim)
                }
                Spacer(minLength: 8)
            }
            .padding(18)
            .torGlass(cornerRadius: 26, tint: .graphite)
        }
    }

    private func planReceipt(_ workout: PlannedWorkout) -> (symbol: String, tint: Color, text: String) {
        let phase = TrainingPhase(rawValue: workout.phaseRaw)?.displayName ?? "Plan"
        switch workout.scheduleUpdatedFrom {
        case "googleCalendar"?:
            return ("calendar.badge.clock", Theme.dim, "\(phase) phase · synced from calendar")
        case .some(let source) where source != "smartSchedulingUndo":
            return ("arrow.turn.up.right", Theme.dim, "\(phase) phase · moved to fit your week")
        default:
            return ("checkmark.seal.fill", Theme.good, "\(phase) phase · on plan")
        }
    }

    @ViewBuilder
    private func receiptLine(_ workout: PlannedWorkout) -> some View {
        let receipt = planReceipt(workout)
        HStack(spacing: 5) {
            Image(systemName: receipt.symbol)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(receipt.tint)
            Text(receipt.text)
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 2)
    }

    /// The plain-language reason this session sits on today's plan - the "why"
    /// behind the prescription, from the workout's role in the training block.
    private func purpose(_ workout: PlannedWorkout) -> String? {
        switch workout.kind {
        case .easy: return "Aerobic base at an easy, conversational effort."
        case .long: return "Extends endurance for race distance."
        case .tempo: return "Sustained, comfortably-hard race effort."
        case .threshold: return "Raises your lactate threshold."
        case .intervals: return "Short, fast reps that sharpen speed."
        case .race: return "Your goal race. The plan builds to this."
        case nil: return nil
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
                    Text(workout.kind?.displayName ?? "Run")
                        .font(.torHeading(17, .bold))
                        .foregroundStyle(Theme.text)
                    Text(subtitle(workout))
                        .font(.caption.weight(.medium))
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
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                coachAction(workout, fixedWidth: true)
                detailsAction(workout, fixedWidth: true)
            }
            VStack(alignment: .leading, spacing: 8) {
                coachAction(workout, fixedWidth: false)
                detailsAction(workout, fixedWidth: false)
            }
        }
    }

    @ViewBuilder
    private func coachAction(_ workout: PlannedWorkout, fixedWidth: Bool) -> some View {
        if let actionTitle = contextualCoachActionTitle(for: workout) {
            NavigationLink {
                ChatView(contextualWorkoutID: workout.uuid)
            } label: {
                Label(actionTitle, systemImage: "sparkles")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.accent)
                    .fixedSize(horizontal: fixedWidth, vertical: !fixedWidth)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Theme.chip, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.accent.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(contextualCoachAccessibilityLabel(for: workout))
        }
    }

    private func detailsAction(_ workout: PlannedWorkout, fixedWidth: Bool) -> some View {
        NavigationLink {
            WorkoutDetailView(workout: workout)
        } label: {
            Label("Details", systemImage: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: fixedWidth, vertical: !fixedWidth)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Theme.chip, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open workout details")
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
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.dim)
            }
            Spacer()
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }

    private func workoutMetricLine(_ workout: PlannedWorkout) -> some View {
        let parts = subtitleParts(workout)
        return ViewThatFits(in: .horizontal) {
            Text(parts.joined(separator: " · "))
                .fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 2) {
                Text(parts[0])
                if parts.count > 1 {
                    Text(parts.dropFirst().joined(separator: " · "))
                }
            }
        }
        .font(.system(.footnote, design: .monospaced).weight(.medium))
        .foregroundStyle(Theme.dim)
    }

    private func subtitle(_ workout: PlannedWorkout) -> String {
        subtitleParts(workout).joined(separator: " · ")
    }

    private func subtitleParts(_ workout: PlannedWorkout) -> [String] {
        var parts = [String(format: "%.2f km", workout.distanceKm)]
        if let band = workout.paceBand {
            parts.append(Formatters.paceBand(band).replacingOccurrences(of: " /km", with: "/km"))
        }
        if let seconds = workout.expectedDurationSeconds {
            parts.append("~\(Int((seconds / 60).rounded())) min")
        }
        return parts
    }

    private func completedSubtitle(_ activity: CompletedActivity) -> String {
        [
            Formatters.kilometers(activity.distanceMeters).replacingOccurrences(of: " ", with: ""),
            Formatters.pace(activity.avgPaceSecondsPerKm).replacingOccurrences(of: " /km", with: "/km"),
            Formatters.duration(activity.durationSeconds).replacingOccurrences(of: " ", with: "")
        ]
        .joined(separator: " · ")
    }

    private func compactSubtitle(_ workout: PlannedWorkout) -> String {
        subtitleParts(workout).first ?? "Run"
    }

    private func completedCompactSubtitle(_ activity: CompletedActivity) -> String {
        Formatters.kilometers(activity.distanceMeters).replacingOccurrences(of: " ", with: "")
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
