import SwiftData
import SwiftUI

/// Month calendar of the training plan: a grid of day cells dotted by workout
/// kind, a legend, and a detail card for the selected day. All data is real —
/// dots and detail come from the planned workouts passed in.
struct PlanMonthView: View {
    let workouts: [PlannedWorkout]
    let language: CoachLanguage
    let completedActivities: [CompletedActivity]
    @Binding var monthAnchor: Date
    @Binding var selectedDate: Date
    var onReviewRunInChat: (CompletedActivity) -> Void = { _ in }
    var onConfigureWeather: () -> Void = {}
    var showsTodaysCall = true
    var displaysOnlyTodaysCall = false
    var phaseRibbon: PlanPhaseRibbonModel? = nil
    @Query(sort: \RunningShoe.createdAt, order: .reverse) private var shoes: [RunningShoe]
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @EnvironmentObject private var runSchedule: RunScheduleController

    private let calendar = Calendar.current
    @ScaledMetric(relativeTo: .caption2) private var railWidth: CGFloat = 52
    private let summaryGutterWidth: CGFloat = 13
    private enum SelectedDateFocus: Equatable {
        case today
        case otherDay
    }
    private enum ScrollTarget: Hashable {
        case selectedDayDetail
    }
    private struct DayTrainingGroup {
        let plannedWorkouts: [PlannedWorkout]
        let completedActivity: CompletedActivity?
        let confirmedMatchedPlan: PlannedWorkout?

        init(plannedWorkouts: [PlannedWorkout], completedActivity: CompletedActivity?) {
            self.plannedWorkouts = plannedWorkouts
            self.completedActivity = completedActivity
            confirmedMatchedPlan = completedActivity.flatMap { activity in
                plannedWorkouts.first { $0.matchedActivityUUID == activity.hkUUID }
            }
        }

        var remainingPlannedWorkouts: [PlannedWorkout] {
            guard let confirmedMatchedPlan else { return plannedWorkouts }
            return plannedWorkouts.filter { $0.uuid != confirmedMatchedPlan.uuid }
        }
    }


    private var selectedDateFocus: SelectedDateFocus {
        calendar.isDateInToday(selectedDate) ? .today : .otherDay
    }

    private var regularMonthContentMaxWidth: CGFloat {
        7 * 96 + summaryGutterWidth + railWidth
    }


    var body: some View {
        if displaysOnlyTodaysCall {
            VStack(alignment: .leading, spacing: 12) {
                AdaptivePlanReviewSlot()
                if selectedDateFocus == .today {
                    todaysCall
                }
            }
        } else {
            let index = MonthIndex(
                anchor: monthAnchor,
                workouts: workouts,
                activities: completedActivities,
                calendar: calendar
            )
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if showsTodaysCall {
                            AdaptivePlanReviewSlot()
                        }
                        if showsTodaysCall && selectedDateFocus == .today {
                            todaysCall
                        }
                        monthNav
                        if let phaseRibbon {
                            PlanPhaseRibbonView(
                                model: phaseRibbon,
                                language: language,
                                onSelectWeek: selectPlanWeek
                            )
                            .frame(
                                maxWidth: horizontalSizeClass == .regular
                                    ? regularMonthContentMaxWidth
                                    : .infinity,
                                alignment: .leading
                            )
                            .frame(
                                maxWidth: .infinity,
                                alignment: horizontalSizeClass == .regular ? .center : .leading
                            )
                        }
                        if horizontalSizeClass == .regular {
                            VStack(alignment: .leading, spacing: 8) {
                                weekdayRow
                                grid(index)
                            }
                            .frame(maxWidth: regularMonthContentMaxWidth, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .center)
                        } else {
                            weekdayRow
                            grid(index)
                        }
                        selectedDayDetail
                            .id(ScrollTarget.selectedDayDetail)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
                .onChange(of: selectedDate) { _, newValue in
                    scrollToSelectedDay(proxy, selectedDate: newValue)
                }
            }
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
            if selectedDateFocus == .otherDay {
                Button {
                    selectToday()
                } label: {
                    Text(language.todayLabel)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.accent)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(language.todayLabel)
            }
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
        language.monthYear(monthAnchor)
    }

    private func shiftMonth(_ delta: Int) {
        guard let next = calendar.date(byAdding: .month, value: delta, to: monthAnchor) else { return }
        withAnimation(.easeOut(duration: 0.2)) { monthAnchor = next }
    }

    private func selectToday() {
        let today = calendar.startOfDay(for: .now)
        withAnimation(.easeOut(duration: 0.2)) {
            monthAnchor = today
            selectedDate = today
        }
    }

    private func scrollToSelectedDay(_ proxy: ScrollViewProxy, selectedDate: Date) {
        guard !calendar.isDateInToday(selectedDate) else { return }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(ScrollTarget.selectedDayDetail, anchor: .top)
            }
        }
    }

    private func selectPlanWeek(_ weekIndex: Int) {
        guard let weekStart = phaseRibbon?.weekStart(for: weekIndex) else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            selectedDate = weekStart
            monthAnchor = weekStart
        }
    }

    // MARK: - Grid

    private var weekdayRow: some View {
        HStack(spacing: 3) {
            ForEach(MonthGrid.weekdays(calendar), id: \.self) { weekday in
                Text(language.shortName(weekday))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.faint)
                    .frame(maxWidth: .infinity)
            }
            summarySeparator
            Text(language.plan.weekVolumeHeader)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.dim)
                .frame(width: railWidth, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
        }
    }

    /// Splits the seven day columns from the week summary so the rail never
    /// reads as an eighth weekday.
    private var summarySeparator: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 6)
            Rectangle()
                .fill(Theme.line)
                .frame(width: 1)
            Color.clear.frame(width: 6)
        }
        .frame(width: summaryGutterWidth)
        .accessibilityHidden(true)
    }

    private func grid(_ index: MonthIndex) -> some View {
        VStack(spacing: 3) {
            ForEach(Array(index.weekRows.enumerated()), id: \.offset) { row, week in
                HStack(spacing: 3) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, cell in
                        if let date = cell {
                            dayCell(date, kind: index.firstKind(on: date))
                                .frame(maxWidth: .infinity)
                        } else {
                            Color.clear
                                .aspectRatio(1, contentMode: .fit)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    summarySeparator
                    weekLoadRail(index.weekVolumes[row])
                }
            }
        }
    }

    private func dayCell(_ date: Date, kind: WorkoutKind?) -> some View {
        let isToday = calendar.isDateInToday(date)
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isPast = date < calendar.startOfDay(for: .now)

        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                selectedDate = calendar.startOfDay(for: date)
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(cellFill(isToday: isToday, isSelected: isSelected))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(cellBorder(isToday: isToday, isSelected: isSelected), lineWidth: 1)
                    )
                    .overlay(alignment: .topTrailing) {
                        if isToday && isSelected {
                            Circle()
                                .fill(Theme.text)
                                .frame(width: 5, height: 5)
                                .padding(6)
                                .accessibilityHidden(true)
                        }
                    }
                VStack(spacing: 5) {
                    Text("\(calendar.component(.day, from: date))")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(numberColor(isToday: isToday, isSelected: isSelected, isPast: isPast, hasWorkout: kind != nil))
                    dayMark(kind: kind, isPast: isPast)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(date, kind: kind, isToday: isToday))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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

    private func cellFill(isToday: Bool, isSelected: Bool) -> Color {
        if isSelected { return Theme.accentSoft }
        if isToday { return Theme.chip }
        return .clear
    }

    private func cellBorder(isToday: Bool, isSelected: Bool) -> Color {
        if isSelected { return Theme.accent }
        if isToday { return Theme.text }
        return .clear
    }

    private func numberColor(isToday: Bool, isSelected: Bool, isPast: Bool, hasWorkout: Bool) -> Color {
        if isSelected { return Theme.accent }
        if isToday { return Theme.text }
        if isPast { return Theme.faint }
        return hasWorkout ? Theme.text : Theme.dim
    }

    private func accessibilityLabel(_ date: Date, kind: WorkoutKind?, isToday: Bool) -> String {
        let stance: String?
        if runSchedule.showsWeatherOverlay {
            stance = language.plan.weatherStance(runSchedule.glyph(on: date))
        } else {
            stance = nil
        }
        return language.plan.dayAccessibility(date: date, kind: kind, isToday: isToday, weatherStance: stance)
    }
    @ViewBuilder
    private var todaysCall: some View {
        let today = calendar.startOfDay(for: .now)
        let group = dayTrainingGroup(on: today)
        if verticalSizeClass == .compact {
            VStack(alignment: .leading, spacing: 8) {
                compactTodaysCall(activity: group.completedActivity, workout: group.plannedWorkouts.first)
                if group.completedActivity != nil {
                    ForEach(group.remainingPlannedWorkouts) { workout in
                        stillPlannedCard(workout, scopeLabel: language.plan.stillPlannedToday)
                    }
                }
                weatherEvidence(on: today, workout: group.plannedWorkouts.first)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                TorEyebrow(language.plan.todayCall)
                    .tracking(2)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityLabel(language.plan.todayCall)
                if let activity = group.completedActivity {
                    scopeHeader(language.plan.completedToday)
                    CalendarRunSummaryCard(
                        activity: activity,
                        plannedWorkout: group.confirmedMatchedPlan,
                        compact: false,
                        reviewDestination: ChatView(contextualCompletedActivityID: activity.hkUUID),
                        onReview: { onReviewRunInChat(activity) }
                    )
                    ForEach(group.remainingPlannedWorkouts) { workout in
                        stillPlannedCard(workout, scopeLabel: language.plan.stillPlannedToday)
                    }
                } else {
                    todaysCallHero(workout: group.plannedWorkouts.first)
                }
                weatherEvidence(on: today, workout: group.plannedWorkouts.first)
            }
        }
    }
    @ViewBuilder
    private var selectedDayDetail: some View {
        if selectedDateFocus == .otherDay {
            let group = dayTrainingGroup(on: selectedDate)
            VStack(alignment: .leading, spacing: 10) {
                TorEyebrow(selectedDayEyebrow)
                    .tracking(2)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityLabel(selectedDayEyebrow)
                if runSchedule.showsWeatherOverlay || runSchedule.needsWeatherSetup {
                    weatherEvidence(on: selectedDate, workout: group.plannedWorkouts.first)
                }
                if let activity = group.completedActivity {
                    scopeHeader(language.plan.completedOnSelectedDay)
                    CalendarRunSummaryCard(
                        activity: activity,
                        plannedWorkout: group.confirmedMatchedPlan,
                        compact: false,
                        reviewDestination: ChatView(contextualCompletedActivityID: activity.hkUUID),
                        onReview: { onReviewRunInChat(activity) }
                    )
                    ForEach(group.remainingPlannedWorkouts) { workout in
                        stillPlannedCard(workout, scopeLabel: language.plan.stillPlannedOnSelectedDay)
                    }
                } else if group.plannedWorkouts.isEmpty {
                    restCard
                } else {
                    ForEach(group.plannedWorkouts) { workout in
                        detailCard(workout)
                    }
                }
            }
        }
    }

    private func weatherEvidence(on day: Date, workout: PlannedWorkout?) -> some View {
        TodayWeatherEvidenceRow(
            language: language,
            needsSetup: runSchedule.needsWeatherSetup,
            isLoading: runSchedule.isRefreshingWeather,
            failure: runSchedule.weatherUserMessage,
            weather: slotWeather(on: day, workout: workout),
            onSetup: onConfigureWeather,
            onRetry: { Task { await runSchedule.refreshWeather(force: true) } }
        )
    }

    private func slotWeather(on day: Date, workout: PlannedWorkout?) -> SlotWeather? {
        if let workout, RunScheduleTime.isTimed(workout.date), calendar.isDate(workout.date, inSameDayAs: day) {
            let duration = workout.expectedDurationSeconds ?? 3600
            return runSchedule.slotWeather(
                start: workout.date,
                end: workout.date.addingTimeInterval(duration)
            )
        }
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        return runSchedule.slotWeather(start: start, end: end)
    }

    // MARK: - Weekly rhythm

    /// Lookup tables built once per body evaluation so the grid's cells and
    /// rails do not each rescan every planned workout and completed run.
    private struct MonthIndex {
        let weekRows: [[Date?]]
        /// Planned vs completed kilometers per week row, in `weekRows` order.
        let weekVolumes: [MonthGrid.WeekVolume]
        private let workoutsByDay: [Date: [PlannedWorkout]]
        private let calendar: Calendar

        init(
            anchor: Date,
            workouts: [PlannedWorkout],
            activities: [CompletedActivity],
            calendar: Calendar
        ) {
            let cells = MonthGrid.cells(for: anchor, calendar: calendar)
            let rows = stride(from: 0, to: cells.count, by: 7).map {
                Array(cells[$0..<min($0 + 7, cells.count)])
            }
            let byDay = Dictionary(grouping: workouts) { calendar.startOfDay(for: $0.date) }
            let plannedByDay = byDay.mapValues { $0.reduce(0) { $0 + $1.distanceKm } }
            let completedByDay = Dictionary(grouping: activities) {
                calendar.startOfDay(for: $0.date)
            }.mapValues { group in
                group.reduce(0) { $0 + ($1.distanceMeters ?? 0) / 1000 }
            }
            self.calendar = calendar
            weekRows = rows
            workoutsByDay = byDay
            weekVolumes = rows.map { week in
                MonthGrid.weekVolume(
                    days: week.compactMap { $0 }.map { calendar.startOfDay(for: $0) },
                    plannedKmByDay: plannedByDay,
                    completedKmByDay: completedByDay
                )
            }
        }

        func firstKind(on date: Date) -> WorkoutKind? {
            workoutsByDay[calendar.startOfDay(for: date)]?.first?.kind
        }
    }

    /// Week summary: completed over planned, with a cyan fill toward this
    /// week's plan. Not scaled to other weeks — that bar had no unit.
    @ViewBuilder
    private func weekLoadRail(_ volume: MonthGrid.WeekVolume) -> some View {
        if volume.hasWork {
            VStack(alignment: .leading, spacing: 3) {
                Text(volume.displayLabel)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(volume.plannedKm > 0 && volume.completedKm > 0 ? Theme.text : Theme.dim)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                if volume.plannedKm > 0 {
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Theme.line)
                            .frame(width: railWidth - 4, height: 3)
                        Capsule()
                            .fill(Theme.data)
                            .frame(width: fillWidth(volume), height: 3)
                    }
                }
            }
            .frame(width: railWidth, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .center)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(volumeAccessibility(volume))
        } else {
            Color.clear.frame(width: railWidth)
        }
    }


    private func fillWidth(_ volume: MonthGrid.WeekVolume) -> CGFloat {
        let maxBar = railWidth - 4
        guard volume.progress > 0 else { return 0 }
        return max(4, maxBar * CGFloat(volume.progress))
    }

    private func volumeAccessibility(_ volume: MonthGrid.WeekVolume) -> String {
        if volume.completedKm > 0 {
            language.plan.weekVolumeAccessibility(
                completed: volume.completedDisplay,
                planned: volume.plannedDisplay
            )
        } else {
            language.plan.weekVolumePlannedAccessibility(volume.plannedDisplay)
        }
    }

    // MARK: - Selected day detail


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
                    title: language.plan.completedRun,
                    metrics: completedSubtitle(activity),
                    compactMetrics: completedCompactSubtitle(activity),
                    tint: Theme.good
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(language.plan.reviewCompletedRunAccessibility)
        } else if let workout {
            NavigationLink {
                WorkoutDetailView(workout: workout)
            } label: {
                compactTodaysCallRow(
                    symbol: workout.kind?.symbolName ?? "figure.run",
                    title: workout.kind.map(language.name) ?? language.genericRunLabel,
                    metrics: subtitle(workout),
                    compactMetrics: compactSubtitle(workout),
                    tint: workout.kind?.styleColor ?? Theme.accent
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(language.plan.openTodayWorkoutAccessibility(workout.kind.map(language.name) ?? language.plan.workout))
        } else {
            compactTodaysCallRow(
                symbol: "moon.zzz.fill",
                title: language.restDayLabel,
                metrics: language.plan.recoveryAndAdaptation,
                compactMetrics: language.recoveryLabel,
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
                        Text(workout.kind.map(language.name) ?? language.genericRunLabel)
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
                        if let shoe = assignedShoe(for: workout) {
                            HStack(spacing: 5) {
                                Image(systemName: "shoeprints.fill")
                                Text(workout.shoeAssignmentSource == .auto ? "\(shoe.displayName) · \(language.plan.autoLabel)" : shoe.displayName)
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.dim)
                        }
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
                    Text(language.restDayLabel)
                        .font(.torHeading(30, .bold))
                        .foregroundStyle(Theme.text)
                    Text(language.plan.recoveryAndAdaptation)
                        .foregroundStyle(Theme.dim)
                }
                Spacer(minLength: 8)
            }
            .padding(18)
            .torGlass(cornerRadius: 26, tint: .graphite)
        }
    }

    private func planReceipt(_ workout: PlannedWorkout) -> (symbol: String, tint: Color, text: String) {
        let phase = TrainingPhase(rawValue: workout.phaseRaw).map(language.name) ?? language.plan.trainingPlanTitle
        switch workout.scheduleUpdatedFrom {
        case "googleCalendar"?:
            return ("calendar.badge.clock", Theme.dim, language.plan.planReceipt(phase: phase, source: .calendar))
        case .some(let source) where source != "smartSchedulingUndo":
            return ("arrow.turn.up.right", Theme.dim, language.plan.planReceipt(phase: phase, source: .moved))
        default:
            return ("checkmark.seal.fill", Theme.good, language.plan.planReceipt(phase: phase, source: .onPlan))
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
        workout.kind.map(language.plan.workoutPurpose)
    }


    private var selectedDayEyebrow: String {
        language.longDate(selectedDate)
    }

    private func scopeHeader(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.dim)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(text)
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
                    Text(workout.kind.map(language.name) ?? language.genericRunLabel)
                        .font(.torHeading(17, .bold))
                        .foregroundStyle(Theme.text)
                    Text(subtitle(workout))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.dim)
                    if let shoe = assignedShoe(for: workout) {
                        HStack(spacing: 5) {
                            Image(systemName: "shoeprints.fill")
                            Text(workout.shoeAssignmentSource == .auto ? "\(shoe.displayName) · \(language.plan.autoLabel)" : shoe.displayName)
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

    private func stillPlannedCard(_ workout: PlannedWorkout, scopeLabel: String) -> some View {
        let workoutName = workout.kind.map(language.name) ?? language.genericRunLabel
        let metrics = subtitle(workout)

        return VStack(alignment: .leading, spacing: 10) {
            Text(scopeLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.dim)
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel(scopeLabel)

            HStack(spacing: 10) {
                Image(systemName: workout.kind?.symbolName ?? "figure.run")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(workout.kind?.styleColor ?? Theme.accent)
                    .frame(width: 36, height: 36)
                    .background(
                        Theme.soft(workout.kind?.styleColor ?? Theme.accent),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(workoutName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.text)
                    Text(metrics)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.dim)
                }
                Spacer(minLength: 8)
            }

            actionRow(workout)
        }
        .padding(12)
        .background(Theme.chip, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            language.plan.stillPlannedAccessibility(
                scope: scopeLabel,
                workout: workoutName,
                metrics: metrics
            )
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
            Label(language.detailsLabel, systemImage: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: fixedWidth, vertical: !fixedWidth)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Theme.chip, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(language.plan.openWorkoutDetailsAccessibility)
    }

    private func contextualCoachActionTitle(for workout: PlannedWorkout) -> String? {
        switch workout.status {
        case .planned:
            return workout.isScheduleLocked || workout.kind == .race ? language.plan.reviewWithCoach : language.plan.editWithCoach
        case .done:
            return language.plan.reviewWithCoach
        case .skipped:
            return nil
        }
    }

    private func contextualCoachAccessibilityLabel(for workout: PlannedWorkout) -> String {
        let name = workout.kind.map(language.name) ?? language.plan.workout
        return language.plan.coachActionAccessibility(contextualCoachActionTitle(for: workout) ?? language.plan.askCoach, workout: name)
    }

    @ViewBuilder
    private func statusBadge(_ workout: PlannedWorkout, isToday: Bool) -> some View {
        switch workout.status {
        case .done: badge(language.name(.done).uppercased(), Theme.good)
        case .skipped: badge(language.name(.skipped).uppercased(), Theme.warn)
        case .planned:
            if !isToday { badge(language.name(.planned).uppercased(), Theme.dim) }
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
                Text(language.restDayLabel)
                    .font(.torHeading(17, .bold))
                    .foregroundStyle(Theme.text)
                Text(language.plan.recoveryAndAdaptation)
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
        subtitleParts(workout).first ?? language.genericRunLabel
    }

    private func completedCompactSubtitle(_ activity: CompletedActivity) -> String {
        Formatters.kilometers(activity.distanceMeters).replacingOccurrences(of: " ", with: "")
    }

    // MARK: - Helpers

    private func dayTrainingGroup(on date: Date) -> DayTrainingGroup {
        DayTrainingGroup(
            plannedWorkouts: workouts(on: date),
            completedActivity: completedActivity(on: date)
        )
    }

    private func workouts(on date: Date) -> [PlannedWorkout] {
        workouts.filter { calendar.isDate($0.date, inSameDayAs: date) }
    }

    private func completedActivity(on date: Date) -> CompletedActivity? {
        completedActivities.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    private func assignedShoe(for workout: PlannedWorkout) -> RunningShoe? {
        guard let shoeID = workout.shoeID else { return nil }
        return shoes.first { $0.id == shoeID }
    }
}
