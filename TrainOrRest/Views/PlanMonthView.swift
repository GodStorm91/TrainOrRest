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
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var reviewCoordinator: AdaptivePlanReviewCoordinator
    @EnvironmentObject private var runSchedule: RunScheduleController
    @Query(sort: \RunningShoe.createdAt, order: .reverse) private var shoes: [RunningShoe]
    @Query(sort: \DailyReadiness.date, order: .reverse) private var readinessDays: [DailyReadiness]
    @Query(sort: \AdaptivePlanReview.updatedAt, order: .reverse) private var adaptiveReviews: [AdaptivePlanReview]
    @Query private var syncStates: [SyncState]
    @Query private var races: [Race]
    private var season: RaceSeason {
        RaceSeason(races: races.compactMap(\.spec))
    }
    @State private var plannedOverrideSaveFailed = false
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

    private var bottomScrollContentMargin: CGFloat {
        TorTabDockMetrics.reservedBottomSpace + (pinsGoogleCalendarStatus ? 44 : 0)
    }

    private var pinsGoogleCalendarStatus: Bool {
        horizontalSizeClass != .regular
            && verticalSizeClass != .compact
            && !dynamicTypeSize.isAccessibilitySize
    }

    private var regularMonthContentMaxWidth: CGFloat {
        7 * 96 + summaryGutterWidth + railWidth
    }


    var body: some View {
        if displaysOnlyTodaysCall {
            VStack(alignment: .leading, spacing: 12) {
                if selectedDateFocus == .today {
                    todaysCall
                }
                calendarPlanReviewSlot
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
                        if showsTodaysCall && selectedDateFocus == .today {
                            todaysCall
                        }
                        if showsTodaysCall {
                            calendarPlanReviewSlot
                        }
                        monthNav
                        raceChipStrip
                        if let phaseRibbon {
                            CalendarPlanPhaseRibbon(
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
                }
                .contentMargins(.bottom, bottomScrollContentMargin, for: .scrollContent)
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
        if reduceMotion {
            selectedDate = weekStart
            monthAnchor = weekStart
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                selectedDate = weekStart
                monthAnchor = weekStart
            }
        }
    }

    @ViewBuilder
    private var raceChipStrip: some View {
        let upcomingRaces = season.upcoming
        if !upcomingRaces.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(upcomingRaces) { race in
                        Button {
                            selectRace(race)
                        } label: {
                            HStack(spacing: 7) {
                                priorityBadge(race.priority, size: 22)
                                Text(race.name)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.text)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .layoutPriority(0)
                                Text(language.shortDate(race.date))
                                    .font(.caption2.weight(.medium).monospacedDigit())
                                    .foregroundStyle(Theme.dim)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .frame(maxWidth: 160)
                            .background(Theme.chip, in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func selectRace(_ race: RaceSpec) {
        let raceDay = calendar.startOfDay(for: race.date)
        if reduceMotion {
            selectedDate = raceDay
            monthAnchor = raceDay
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                selectedDate = raceDay
                monthAnchor = raceDay
            }
        }
    }

    private func priorityBadge(_ priority: RacePriority, size: CGFloat) -> some View {
        let isPrimary = priority == .a
        let accent = priority == .b
        let cornerRadius = size * 7 / 22

        return Text(priority.rawValue)
            .font(.system(size: size * 0.55, weight: .bold, design: .rounded))
            .foregroundStyle(isPrimary ? Color.white : (accent ? Theme.accent : Theme.dim))
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isPrimary ? Theme.accent : Color.clear)
            )
            .overlay {
                if !isPrimary {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(accent ? Theme.accent : Theme.border, lineWidth: 1)
                }
            }
            .accessibilityHidden(true)
    }

    private var activeAdaptiveReview: AdaptivePlanReview? {
        adaptiveReviews.first { $0.phase != .dismissed }
    }

    private var canStartManualReview: Bool {
        guard let review = activeAdaptiveReview else { return true }
        switch review.phase {
        case .needsKey:
            return reviewCoordinator.selectedCoachIsConnected()
        case .noChange, .applied, .reverted, .superseded:
            return true
        default:
            return false
        }
    }

    @ViewBuilder
    private var calendarPlanReviewSlot: some View {
        if canStartManualReview {
            Button(language.plan.reviewNextSevenDays) {
                Task { await reviewCoordinator.beginManualReview(activityID: nil, in: modelContext) }
            }
            .buttonStyle(.bordered)
            .tint(Theme.accent)
            .font(.subheadline.weight(.semibold))
            .accessibilityLabel(language.plan.reviewNextSevenDays)
        } else {
            AdaptivePlanReviewSlot()
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
                    weekLoadRail(index.weekVolumes[row], dates: week.compactMap { $0 })
                }
            }
        }
    }

    private func dayCell(_ date: Date, kind: WorkoutKind?) -> some View {
        let isToday = calendar.isDateInToday(date)
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isPast = date < calendar.startOfDay(for: .now)
        let race = race(on: date)
        let accessibilityKind = race == nil ? kind : .race

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
                        .foregroundStyle(numberColor(
                            isToday: isToday,
                            isSelected: isSelected,
                            isPast: isPast,
                            hasWorkout: kind != nil || race != nil
                        ))
                    dayMark(race: race, kind: kind, isPast: isPast)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(date, kind: accessibilityKind, isToday: isToday))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func dayMark(race: RaceSpec?, kind: WorkoutKind?, isPast: Bool) -> some View {
        Group {
            if let race {
                priorityBadge(race.priority, size: 12)
                    .opacity(isPast ? 0.4 : 1)
            } else if let kind {
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
                if let race = race(on: selectedDate) {
                    Text(recoveryLine(for: race))
                        .font(.footnote)
                        .foregroundStyle(Theme.dim)
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
    private func weekLoadRail(_ volume: MonthGrid.WeekVolume, dates: [Date]) -> some View {
        let tag = weekRaceTag(for: dates)
        if volume.hasWork || tag != nil {
            VStack(alignment: .leading, spacing: 3) {
                Text(volume.displayLabel)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(volume.plannedKm > 0 && volume.completedKm > 0 ? Theme.text : Theme.dim)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                if let tag {
                    Text(tag.text)
                        .font(.caption2)
                        .foregroundStyle(tag.color)
                        .lineLimit(1)
                }
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
            .accessibilityLabel(volumeAccessibility(volume, tag: tag?.text))
        } else {
            Color.clear.frame(width: railWidth)
        }
    }

    private func weekRaceTag(for dates: [Date]) -> (text: String, color: Color)? {
        let raceSpecs = season.races
        if dates.contains(where: { day in
            raceSpecs.contains { race in
                race.status != .skipped && isTaperDay(day, for: race)
            }
        }) {
            return (language.season.taperTag, Theme.warn)
        }
        if dates.contains(where: { day in
            raceSpecs.contains { race in
                race.status != .skipped && isRecoveryDay(day, for: race)
            }
        }) {
            return (language.season.recoveryTag, Theme.good)
        }
        return nil
    }

    private func isTaperDay(_ date: Date, for race: RaceSpec) -> Bool {
        let taperDays: Int
        switch race.priority {
        case .a:
            taperDays = RaceTaperTable.taperDays(meters: race.distanceMeters)
        case .b:
            taperDays = RaceTaperTable.miniTaperDays
        case .c:
            return false
        }

        let raceDay = calendar.startOfDay(for: race.date)
        let day = calendar.startOfDay(for: date)
        guard let taperStart = calendar.date(byAdding: .day, value: -taperDays, to: raceDay) else {
            return false
        }
        return day >= taperStart && day < raceDay
    }

    private func isRecoveryDay(_ date: Date, for race: RaceSpec) -> Bool {
        let raceDay = calendar.startOfDay(for: race.date)
        let day = calendar.startOfDay(for: date)
        let recoveryDays = RaceTaperTable.recoveryDays(
            meters: race.distanceMeters,
            priority: race.priority
        )
        guard let recoveryEnd = calendar.date(byAdding: .day, value: recoveryDays, to: raceDay) else {
            return false
        }
        return day > raceDay && day <= recoveryEnd
    }

    private func race(on date: Date) -> RaceSpec? {
        let day = calendar.startOfDay(for: date)
        var match: RaceSpec?

        for candidate in season.races where calendar.startOfDay(for: candidate.date) == day {
            guard let current = match else {
                match = candidate
                continue
            }
            if candidate.priority < current.priority
                || (candidate.priority == current.priority && candidate.id.uuidString < current.id.uuidString) {
                match = candidate
            }
        }
        return match
    }

    private func recoveryLine(for race: RaceSpec) -> String {
        let recoveryDays = RaceTaperTable.recoveryDays(
            meters: race.distanceMeters,
            priority: race.priority
        )
        let recovery = "\(language.season.recoveryTag) \(recoveryDays)"
        let raceDay = calendar.startOfDay(for: race.date)
        guard let nextRace = season.upcoming.first(where: {
            calendar.startOfDay(for: $0.date) > raceDay
        }) else {
            return recovery
        }

        let maximumNameLength = max(0, 70 - recovery.count - 3)
        let nextRaceName = String(nextRace.name.prefix(maximumNameLength))
        guard !nextRaceName.isEmpty else { return recovery }
        return "\(recovery) → \(nextRaceName)"
    }


    private func fillWidth(_ volume: MonthGrid.WeekVolume) -> CGFloat {
        let maxBar = railWidth - 4
        guard volume.progress > 0 else { return 0 }
        return max(4, maxBar * CGFloat(volume.progress))
    }

    private func volumeAccessibility(_ volume: MonthGrid.WeekVolume, tag: String?) -> String {
        let label: String
        if volume.completedKm > 0 {
            label = language.plan.weekVolumeAccessibility(
                completed: volume.completedDisplay,
                planned: volume.plannedDisplay
            )
        } else {
            label = language.plan.weekVolumePlannedAccessibility(volume.plannedDisplay)
        }
        guard let tag else { return label }
        return "\(label), \(tag)"
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

    private func todaysCallHero(workout: PlannedWorkout?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VerdictBannerView(
                readiness: todayReadiness,
                workout: workout,
                lastSyncAt: latestSyncAt,
                language: language,
                onKeepPlanned: keepPlannedSession
            )

            if plannedOverrideSaveFailed {
                Text(language.today.plannedSessionOverrideFailed)
                    .font(.caption)
                    .foregroundStyle(Theme.bad)
            }
        }
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

    private var todayReadiness: DailyReadiness? {
        readinessDays.first { calendar.isDateInToday($0.date) }
    }

    private var latestSyncAt: Date? {
        syncStates.compactMap(\.lastSyncAt).max()
    }

    private func keepPlannedSession(for rule: ReadinessRule) {
        modelContext.insert(RuleOverride(date: calendar.startOfDay(for: .now), rule: rule))
        do {
            try modelContext.save()
            _ = try ReadinessStore.runDailyPipeline(in: modelContext, today: .now, calendar: calendar)
            plannedOverrideSaveFailed = false
        } catch {
            plannedOverrideSaveFailed = true
        }
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

private struct CalendarPlanPhaseRibbon: View {
    let model: PlanPhaseRibbonModel
    let language: CoachLanguage
    let onSelectWeek: (Int) -> Void

    private let minimumSegmentWidth: CGFloat = 160
    private let weekWidth: CGFloat = 56

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(model.segments) { segment in
                    segmentView(segment)
                }
            }
            .padding(.horizontal, 1)
            .padding(.trailing, 16)
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .contain)
    }

    private func segmentView(_ segment: PlanPhaseRibbonModel.Segment) -> some View {
        let isActive = segment.id == model.activeSegmentID
        let segmentWidth = max(minimumSegmentWidth, weekWidth * CGFloat(segment.weekCount) + 20)
        let contentWeekWidth = max(38, (segmentWidth - 20) / CGFloat(max(segment.weekCount, 1)))

        return VStack(alignment: .leading, spacing: 8) {
            Button {
                onSelectWeek(segment.ticks.first(where: \.isCurrent)?.weekIndex ?? segment.startWeekIndex)
            } label: {
                Text(segmentLabel(segment, isActive: isActive))
                    .font(.caption.weight(isActive ? .semibold : .medium))
                    .foregroundStyle(isActive ? Theme.text : Theme.dim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(segmentAccessibilityLabel(segment, isActive: isActive))

            HStack(spacing: 0) {
                ForEach(segment.ticks) { tick in
                    tickButton(tick)
                        .frame(width: contentWeekWidth)
                }
            }
        }
        .padding(10)
        .frame(width: segmentWidth, alignment: .leading)
        .background(isActive ? Theme.accentSoft : Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isActive ? Theme.accent : Theme.border, lineWidth: 1)
        )
    }

    private func tickButton(_ tick: PlanPhaseRibbonModel.Tick) -> some View {
        Button {
            onSelectWeek(tick.weekIndex)
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Circle()
                        .fill(tick.isCurrent ? Theme.accent : Theme.card)
                        .overlay(Circle().strokeBorder(tick.isCurrent ? Theme.accent : Theme.border, lineWidth: 1))
                        .frame(width: 20, height: 20)

                    if tick.isDown {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(Theme.dim)
                            .padding(2)
                            .background(Theme.card, in: Circle())
                            .offset(x: 5, y: -5)
                    }
                }
                .frame(width: 24, height: 24)

                if let target = tick.targetVolumeKm {
                    Text("\(Int(target.rounded()))")
                        .font(.caption2.weight(.medium).monospacedDigit())
                        .foregroundStyle(Theme.faint)
                        .lineLimit(1)
                }
            }
            .frame(minHeight: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tickAccessibilityLabel(tick))
        .accessibilityAddTraits(tick.isCurrent ? .isSelected : [])
    }

    private func segmentLabel(_ segment: PlanPhaseRibbonModel.Segment, isActive: Bool) -> String {
        let name = language.name(segment.phase)
        guard isActive, let currentWeek = segment.currentWeekInSegment else { return name }
        return "\(name) · \(currentWeek)/\(segment.weekCount)"
    }

    private func segmentAccessibilityLabel(_ segment: PlanPhaseRibbonModel.Segment, isActive: Bool) -> String {
        let name = language.name(segment.phase)
        guard isActive, let currentWeek = segment.currentWeekInSegment else { return name }
        return "\(name), \(language.plan.phaseProgress(week: currentWeek, total: segment.weekCount))"
    }

    private func tickAccessibilityLabel(_ tick: PlanPhaseRibbonModel.Tick) -> String {
        var parts = [language.plan.weekOfTotal(tick.weekIndex + 1, total: totalWeeks)]
        if let target = tick.targetVolumeKm {
            parts.append("\(Int(target.rounded())) km")
        }
        if tick.isCurrent {
            parts.append(language.plan.thisWeek)
        }
        if tick.isDown {
            parts.append(language.recoveryLabel)
        }
        return parts.joined(separator: ", ")
    }

    private var totalWeeks: Int {
        model.segments.reduce(0) { $0 + $1.weekCount }
    }
}
