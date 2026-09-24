import Foundation
import SwiftData
import SwiftUI

/// The training plan tab. Switches between a month calendar grid and the
/// week-by-week list; both share the plan's real workout data.
struct PlanCalendarView: View {
    var onReviewRunInChat: (CompletedActivity) -> Void
    enum Mode: CaseIterable, Identifiable {
        case month
        case week

        var id: Self { self }
    }

    private enum DismissibleBanner: Hashable {
        case recentCoachChanges(String)
        case googleCalendarStatus(String)
    }

    @Query(sort: \PlannedWorkout.date) private var workouts: [PlannedWorkout]
    @Query(sort: \CompletedActivity.date, order: .reverse) private var completedActivities: [CompletedActivity]
    @Query(sort: \PlanEdit.appliedAt, order: .reverse) private var planEdits: [PlanEdit]
    @Query private var goals: [Goal]
    @Query private var plans: [TrainingPlan]
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var pushService: WorkoutPushService
    @EnvironmentObject private var googleCalendar: GoogleCalendarSyncService
    @EnvironmentObject private var runSchedule: RunScheduleController
    @Query private var googleConnections: [GoogleCalendarConnection]
    @Query private var googleCalendarChanges: [GoogleCalendarInboundChange]
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize


    @AppStorage(CoachLanguage.storageKey) private var languageRaw = CoachLanguage.en.rawValue

    private var language: CoachLanguage { CoachLanguage(rawValue: languageRaw) ?? .en }
    @State private var mode: Mode = .month
    @State private var monthAnchor: Date = .now
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: .now)
    @State private var weekScrollToken = 0
    @State private var isEditingGoal = false
    @State private var revertError: String?
    @State private var forceSyncStatus: ForceSyncStatus?
    @State private var isShowingGoogleCalendarStatus = false
    @State private var dismissedBanners: Set<DismissibleBanner> = []
    @State private var didCheckGoogleCalendarOnOpen = false
    @State private var isShowingRunScheduleSetup = false


    init(onReviewRunInChat: @escaping (CompletedActivity) -> Void = { _ in }) {
        self.onReviewRunInChat = onReviewRunInChat
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if environment["TOR_DEV_CAL_MODE"] == "week" {
            _mode = State(initialValue: .week)
        }
        if let offset = environment["TOR_DEV_SELECTED_OFFSET"].flatMap(Int.init) {
            let date = calendar.date(
                byAdding: .day,
                value: offset,
                to: calendar.startOfDay(for: .now)
            ) ?? .now
            _selectedDate = State(initialValue: date)
            _monthAnchor = State(initialValue: date)
        }
        #endif
    }
    private let calendar = Calendar.current
    private var monthPhaseRibbon: PlanPhaseRibbonModel? {
        guard let plan = plans.first,
              let summary = ActivePlanSummaryBuilder.build(
                goal: goals.first,
                plan: plan,
                activities: completedActivities,
                calendar: calendar
              ) else {
            return nil
        }
        return PlanPhaseRibbonModel(plan: plan, summary: summary, calendar: calendar)
    }


    var body: some View {
        VStack(spacing: 0) {
            if verticalSizeClass != .compact {
                topBar
            }
            ForceIntervalsSyncStatusView(status: forceSyncStatus, language: language, onRetry: forceSyncIntervals)
            if isBannerVisible(coachChangesBanner) {
                RecentCoachChangesView(
                    edits: recentCoachEdits,
                    error: revertError,
                    language: language,
                    onRevert: revert,
                    onDismiss: { dismiss(coachChangesBanner) }
                )
            }
            content
        }
        .background(Theme.bg)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if pinsGoogleCalendarStatus {
                    googleCalendarStatusRow
                }
                Color.clear.frame(height: 82)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if verticalSizeClass == .compact {
                ToolbarItem(placement: .principal) {
                    modeToggle
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    forceSyncIntervals()
                } label: {
                    if pushService.isPushing {
                        ProgressView()
                    } else {
                        Label(language.plan.syncIntervals, systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(pushService.isPushing)
                Button(language.todayLabel, systemImage: "calendar") { goToToday() }
                Button {
                    isEditingGoal = true
                } label: {
                    Label(goalButtonTitle, systemImage: "target")
                }
                if (verticalSizeClass == .compact || (horizontalSizeClass != .regular && !pinsGoogleCalendarStatus)),
                   isBannerVisible(googleStatusBanner) {
                    Button {
                        isShowingGoogleCalendarStatus = true
                    } label: {
                        Label(googleCalendarStatusText, systemImage: googleCalendarStatusIcon)
                            .foregroundStyle(googleCalendarStatusTint)
                    }
                    .accessibilityLabel(googleCalendarAccessibilityLabel)
                    Button {
                        dismiss(googleStatusBanner)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.dim)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(language.plan.dismissGoogleCalendarStatusAccessibility)
                }
            }
        }
        .sheet(isPresented: $isEditingGoal) { GoalEntryView() }
        .sheet(isPresented: $isShowingGoogleCalendarStatus) {
            GoogleCalendarStatusSheet()
        }
        .sheet(isPresented: $isShowingRunScheduleSetup) {
            RunScheduleSetupSheet()
        }
        .task {
            guard !didCheckGoogleCalendarOnOpen,
                  googleConnection?.allowsSchedulingFromGoogle == true || googleConnection?.smartSchedulingEnabled == true else { return }
            didCheckGoogleCalendarOnOpen = true
            if googleConnection?.allowsSchedulingFromGoogle == true {
                await googleCalendar.reconcile(reason: "openTrainingCalendar")
            }
            if googleConnection?.smartSchedulingEnabled == true {
                await googleCalendar.refreshAvailability(reason: "openTrainingCalendar")
            }
        }
        .task {
            if runSchedule.setupCompleted || runSchedule.showsWeatherOverlay {
                await runSchedule.refreshWeather()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if workouts.isEmpty {
            ContentUnavailableView {
                Label(language.plan.noPlanYet, systemImage: "calendar.badge.plus")
            } description: {
                Text(language.plan.noPlanDescription)
            } actions: {
                Button {
                    isEditingGoal = true
                } label: {
                    Text(language.plan.setRaceGoal)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if horizontalSizeClass == .regular {
            HStack(alignment: .top, spacing: TorLayout.screenGutter(.regular)) {
                planContent(hidesTodaysCall: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        PlanMonthView(
                            workouts: workouts,
                            language: language,
                            completedActivities: completedActivities,
                            monthAnchor: $monthAnchor,
                            selectedDate: $selectedDate,
                            onReviewRunInChat: onReviewRunInChat,
                            onConfigureWeather: { isShowingRunScheduleSetup = true },
                            displaysOnlyTodaysCall: true
                        )
                        if isBannerVisible(googleStatusBanner) {
                            googleCalendarStatusRow
                        }
                    }
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
                .frame(width: TorLayout.sidePaneWidth)
            }
            .padding(.horizontal, TorLayout.screenGutter(.regular))
        } else {
            planContent(hidesTodaysCall: false)
        }
    }

    @ViewBuilder
    private func planContent(hidesTodaysCall: Bool) -> some View {
        if mode == .month {
            PlanMonthView(
                workouts: workouts,
                language: language,
                completedActivities: completedActivities,
                monthAnchor: $monthAnchor,
                selectedDate: $selectedDate,
                onReviewRunInChat: onReviewRunInChat,
                onConfigureWeather: { isShowingRunScheduleSetup = true },
                showsTodaysCall: !hidesTodaysCall,
                phaseRibbon: monthPhaseRibbon
            )
        } else {
            PlanWeekListView(
                scrollToTodayToken: weekScrollToken,
                language: language,
                onReviewRunInChat: onReviewRunInChat,
                showsAdaptiveReviewSlot: horizontalSizeClass != .regular
            )
        }
    }

    // A pinned row costs too much height on landscape phones (about 320 pt) and at accessibility sizes.
    private var pinsGoogleCalendarStatus: Bool {
        horizontalSizeClass != .regular
            && verticalSizeClass != .compact
            && !dynamicTypeSize.isAccessibilitySize
    }

    private var topBar: some View {
        // Segment labels never break mid-word: when "Month | Week" no longer fits
        // beside the eyebrow (large Dynamic Type), the toggle drops below it.
        ViewThatFits(in: .horizontal) {
            HStack {
                TorEyebrow(language.plan.trainingPlanTitle).tracking(2)
                Spacer()
                modeToggle
            }
            VStack(alignment: .leading, spacing: 10) {
                TorEyebrow(language.plan.trainingPlanTitle).tracking(2)
                modeToggle
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var googleCalendarStatusRow: some View {
        HStack(spacing: 0) {
            Button {
                isShowingGoogleCalendarStatus = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: googleCalendarStatusIcon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(googleCalendarStatusTint)
                    Text(googleCalendarStatusText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.dim)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.faint)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.leading, 16)
                .padding(.trailing, 6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(googleCalendarAccessibilityLabel)

            Button {
                dismiss(googleStatusBanner)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(language.plan.dismissGoogleCalendarStatusAccessibility)
        }
        .background(Theme.card)
    }

    private var modeToggle: some View {
        HStack(spacing: 4) {
            ForEach(Mode.allCases) { option in
                segment(option)
            }
        }
        .padding(3)
        .background(Theme.chip, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func segment(_ option: Mode) -> some View {
        let selected = option == mode
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { mode = option }
            if option == .week {
                weekScrollToken += 1
            }
        } label: {
            Text(modeName(option))
                .font(.caption.weight(selected ? .bold : .semibold))
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(selected ? Color.white : Theme.faint)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(
                    selected ? Theme.accent : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func modeName(_ mode: Mode) -> String {
        mode == .month ? language.plan.monthMode : language.plan.weekMode
    }

    private var goalButtonTitle: String {
        goals.isEmpty ? language.plan.setEnteredRace : language.plan.changeGoal
    }

    private var googleConnection: GoogleCalendarConnection? {
        googleConnections.first
    }

    private var googleCalendarStatusText: String {
        guard let connection = googleConnection else { return language.plan.connectGoogleCalendar }
        switch connection.connectionStatus {
        case .connected:
            if pendingGoogleCalendarReviews > 0 {
                return language.plan.googleChangesNeedReview(pendingGoogleCalendarReviews)
            }
            return language.plan.googleUpToDate
        case .syncing, .initialSync:
            return language.plan.googleSyncing
        case .needsReconnect:
            return language.plan.googleReconnectRequired
        case .offlineQueued:
            return language.plan.googleWaitingForConnection
        case .partialFailure, .calendarMissing:
            return language.plan.googleNeedsAttention
        default:
            return language.plan.connectGoogleCalendar
        }
    }

    private var googleCalendarStatusIcon: String {
        guard let connection = googleConnection else { return "calendar.badge.plus" }
        switch connection.connectionStatus {
        case .connected: return "calendar.badge.checkmark"
        case .syncing, .initialSync: return "arrow.triangle.2.circlepath"
        case .needsReconnect, .offlineQueued, .partialFailure, .calendarMissing: return "exclamationmark.triangle"
        default: return "calendar.badge.plus"
        }
    }

    private var googleCalendarStatusTint: Color {
        guard let connection = googleConnection else { return Theme.accent }
        if pendingGoogleCalendarReviews > 0 { return Theme.warn }
        switch connection.connectionStatus {
        case .connected: return Theme.good
        case .needsReconnect, .offlineQueued, .partialFailure, .calendarMissing: return Theme.warn
        default: return Theme.accent
        }
    }

    private var googleCalendarAccessibilityLabel: String {
        if pendingGoogleCalendarReviews > 0 {
            return language.plan.googleChangesNeedReviewAccessibility
        }
        switch googleConnection?.connectionStatus {
        case .connected: return language.plan.googleConnectedAccessibility
        case .syncing, .initialSync: return language.plan.googleSyncingAccessibility
        case .needsReconnect: return language.plan.googleReconnectAccessibility
        default: return language.plan.manageGoogleSyncAccessibility
        }
    }

    private var pendingGoogleCalendarReviews: Int {
        guard let connection = googleConnection else { return 0 }
        return googleCalendarChanges.filter {
            $0.connectionID == connection.uuid && $0.status == .pendingReview
        }.count
    }

    private var recentCoachEdits: [PlanEdit] {
        let cutoff = calendar.date(
            byAdding: .day,
            value: -PlanEditStore.revertWindowDays,
            to: .now
        ) ?? .now
        return planEdits.filter {
            $0.source == "coach" && $0.revertedAt == nil && $0.appliedAt >= cutoff
        }
    }
    private var coachChangesBanner: DismissibleBanner {
        let editSignature = recentCoachEdits.map { edit in
            [
                edit.id.uuidString,
                edit.appliedAt.timeIntervalSince1970.description,
                edit.summaryText ?? ""
            ].joined(separator: ":")
        }
        .joined(separator: "|")
        return .recentCoachChanges([editSignature, revertError ?? ""].joined(separator: "|"))
    }

    private var googleStatusBanner: DismissibleBanner {
        guard let connection = googleConnection else {
            return .googleCalendarStatus("none")
        }
        return .googleCalendarStatus([
            connection.uuid.uuidString,
            connection.connectionStatus.rawValue,
            "\(pendingGoogleCalendarReviews)",
            connection.lastSyncErrorCategoryRaw ?? "",
            connection.lastSyncSummary ?? ""
        ].joined(separator: "|"))
    }

    private func goToToday() {
        let today = calendar.startOfDay(for: .now)
        withAnimation(.easeOut(duration: 0.2)) {
            monthAnchor = .now
            selectedDate = today
        }
        weekScrollToken += 1
    }

    private func isBannerVisible(_ banner: DismissibleBanner) -> Bool {
        !dismissedBanners.contains(banner)
    }

    private func dismiss(_ banner: DismissibleBanner) {
        withAnimation(.easeOut(duration: 0.15)) {
            _ = dismissedBanners.insert(banner)
        }
    }


    private func forceSyncIntervals() {
        forceSyncStatus = .syncing
        Task {
            await pushService.reconcile(requireEnabled: false, forceRecreate: true)
            await MainActor.run {
                if let error = pushService.lastPushError {
                    forceSyncStatus = .failed(error)
                } else if let skip = pushService.lastPushSkipReason {
                    forceSyncStatus = .skipped(skip)
                } else if let lastPushAt = pushService.lastPushAt {
                    forceSyncStatus = .synced(lastPushAt)
                } else {
                    forceSyncStatus = .skipped(language.plan.noWorkoutsToSync)
                }
            }
        }
    }

    private func revert(_ edit: PlanEdit) {
        do {
            try PlanEditStore.revert(edit.id, in: modelContext, today: .now, calendar: calendar)
            revertError = nil
        } catch {
            revertError = error.localizedDescription
        }
    }
}

private enum ForceSyncStatus: Equatable {
    case syncing
    case synced(Date)
    case skipped(String)
    case failed(String)
}

private struct ForceIntervalsSyncStatusView: View {
    var status: ForceSyncStatus?
    let language: CoachLanguage
    var onRetry: () -> Void

    var body: some View {
        if let status {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: icon(status))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint(status))
                Text(message(status))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if case .failed = status {
                    Button(language.plan.retry, action: onRetry)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.accent)
                        .buttonStyle(.plain)
                        .frame(minHeight: 36)
                        .accessibilityLabel(language.plan.retryIntervalsAccessibility)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Theme.card)
        }
    }

    private func icon(_ status: ForceSyncStatus) -> String {
        switch status {
        case .syncing: "arrow.triangle.2.circlepath"
        case .synced: "checkmark.circle.fill"
        case .skipped: "minus.circle"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private func tint(_ status: ForceSyncStatus) -> Color {
        switch status {
        case .syncing: Theme.dim
        case .synced: Theme.good
        case .skipped: Theme.faint
        case .failed: Theme.bad
        }
    }

    private func message(_ status: ForceSyncStatus) -> String {
        switch status {
        case .syncing: language.plan.syncingIntervals
        case .synced(let date): language.plan.syncedIntervals(date)
        case .skipped(let reason): language.plan.syncSkipped(reason)
        case .failed(let reason): language.plan.syncFailed(reason)
        }
    }
}

private struct RecentCoachChangesView: View {
    var edits: [PlanEdit]
    var error: String?
    let language: CoachLanguage
    var onRevert: (PlanEdit) -> Void
    var onDismiss: () -> Void

    var body: some View {
        if !edits.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(edits.prefix(1)) { edit in
                    row(edit)
                }
                if edits.count > 1 {
                    Text(language.plan.moreRecentChanges(edits.count - 1))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Theme.faint)
                        .padding(.leading, 12)
                }
                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Theme.bad)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private func row(_ edit: PlanEdit) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "arrow.uturn.backward")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text(language.plan.coachUpdatedWorkout(summary(for: edit)))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Spacer(minLength: 8)
            Button {
                onRevert(edit)
            } label: {
                Text(language.plan.undo)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.accent)
                    .frame(minWidth: 54, minHeight: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(language.plan.undoCoachWorkoutChangeAccessibility)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(language.plan.dismissRecentCoachChangesAccessibility)
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .frame(minHeight: 44)
        .background(Theme.chip, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }

    private func summary(for edit: PlanEdit) -> String {
        if let summary = edit.summaryText {
            return summary
        }
        return language.plan.workoutChangeSummary(
            beforeKind: kindName(edit.kindRaw),
            beforeDistance: km(edit.distanceKm),
            afterKind: kindName(edit.afterKindRaw),
            afterDistance: km(edit.afterDistanceKm)
        )
    }

    private func kindName(_ raw: String) -> String {
        WorkoutKind(rawValue: raw).map(language.name) ?? language.genericRunLabel
    }

    private func km(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}

extension WorkoutKind {
    var displayName: String {
        switch self {
        case .easy: "Easy"
        case .long: "Long run"
        case .tempo: "Tempo"
        case .threshold: "Threshold"
        case .intervals: "Intervals"
        case .race: "Race"
        }
    }

    var symbolName: String {
        switch self {
        case .easy: "figure.run"
        case .long: "arrow.up.right.circle"
        case .tempo: "gauge.with.needle"
        case .threshold: "speedometer"
        case .intervals: "timer"
        case .race: "flag.checkered"
        }
    }
}

extension WorkoutStatus {
    var symbolName: String {
        switch self {
        case .planned: "circle"
        case .done: "checkmark.circle.fill"
        case .skipped: "slash.circle"
        }
    }

    var color: Color {
        switch self {
        case .planned: Theme.dim
        case .done: Theme.good
        case .skipped: Theme.warn
        }
    }
}

extension Formatters {
    static func paceBand(_ band: PaceBand) -> String {
        let fast = pace(band.fastSecondsPerKm).replacingOccurrences(of: " /km", with: "")
        return "\(fast)–\(pace(band.slowSecondsPerKm))"
    }
}
