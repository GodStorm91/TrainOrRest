import Foundation
import SwiftData
import SwiftUI

/// The training plan tab. Switches between a month calendar grid and the
/// week-by-week list; both share the plan's real workout data.
struct PlanCalendarView: View {
    var onReviewRunInChat: (CompletedActivity) -> Void = { _ in }
    enum Mode: String, CaseIterable, Identifiable {
        case month = "Month"
        case week = "Week"
        var id: Self { self }
    }

    @Query(sort: \PlannedWorkout.date) private var workouts: [PlannedWorkout]
    @Query(sort: \CompletedActivity.date, order: .reverse) private var completedActivities: [CompletedActivity]
    @Query(sort: \PlanEdit.appliedAt, order: .reverse) private var planEdits: [PlanEdit]
    @Query private var goals: [Goal]
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var pushService: WorkoutPushService
    @EnvironmentObject private var googleCalendar: GoogleCalendarSyncService
    @Query private var googleConnections: [GoogleCalendarConnection]
    @Query private var googleCalendarChanges: [GoogleCalendarInboundChange]

    @State private var mode: Mode = .month
    @State private var monthAnchor: Date = .now
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: .now)
    @State private var weekScrollToken = 0
    @State private var isEditingGoal = false
    @State private var revertError: String?
    @State private var forceSyncStatus: String?
    @State private var isShowingGoogleCalendarStatus = false
    @State private var didCheckGoogleCalendarOnOpen = false

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            topBar
            googleCalendarStatusRow
            ForceIntervalsSyncStatusView(status: forceSyncStatus)
            RecentCoachChangesView(
                edits: recentCoachEdits,
                error: revertError,
                onRevert: revert
            )
            content
        }
        .background(Theme.bg)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 82)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    forceSyncIntervals()
                } label: {
                    if pushService.isPushing {
                        ProgressView()
                    } else {
                        Label("Sync intervals.icu", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(pushService.isPushing)
                Button("Today", systemImage: "calendar") { goToToday() }
                Button {
                    isEditingGoal = true
                } label: {
                    Label(goalButtonTitle, systemImage: "target")
                }
            }
        }
        .sheet(isPresented: $isEditingGoal) { GoalEntryView() }
        .sheet(isPresented: $isShowingGoogleCalendarStatus) {
            GoogleCalendarStatusSheet()
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
    }

    @ViewBuilder
    private var content: some View {
        if workouts.isEmpty {
            ContentUnavailableView(
                "No Plan Yet",
                systemImage: "calendar.badge.plus",
                description: Text("Set a race goal to generate your training plan.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if mode == .month {
            PlanMonthView(
                workouts: workouts,
                completedActivities: completedActivities,
                monthAnchor: $monthAnchor,
                selectedDate: $selectedDate,
                onReviewRunInChat: onReviewRunInChat
            )
        } else {
            PlanWeekListView(scrollToTodayToken: weekScrollToken, onReviewRunInChat: onReviewRunInChat)
        }
    }

    private var topBar: some View {
        HStack {
            TorEyebrow("Training plan").tracking(2)
            Spacer()
            modeToggle
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var googleCalendarStatusRow: some View {
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
            .frame(minHeight: 36)
            .padding(.horizontal, 16)
            .background(Theme.card)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(googleCalendarAccessibilityLabel)
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
        return Text(option.rawValue)
            .font(.torHeading(12, selected ? .bold : .semibold))
            .foregroundStyle(selected ? Color.white : Theme.faint)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(
                selected ? Theme.accent : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.15)) { mode = option }
                if option == .week {
                    weekScrollToken += 1
                }
            }
    }

    private var goalButtonTitle: String {
        goals.isEmpty ? "Set race goal" : "Change goal"
    }

    private var googleConnection: GoogleCalendarConnection? {
        googleConnections.first
    }

    private var googleCalendarStatusText: String {
        guard let connection = googleConnection else { return "Connect Google Calendar" }
        switch connection.connectionStatus {
        case .connected:
            if pendingGoogleCalendarReviews > 0 {
                return "Google Calendar · \(pendingGoogleCalendarReviews) changes need review"
            }
            return "Google Calendar · Up to date"
        case .syncing, .initialSync:
            return "Google Calendar · Syncing"
        case .needsReconnect:
            return "Google Calendar · Reconnect required"
        case .offlineQueued:
            return "Google Calendar · Waiting for connection"
        case .partialFailure, .calendarMissing:
            return "Google Calendar · Needs attention"
        default:
            return "Connect Google Calendar"
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
            return "Google Calendar changes need review"
        }
        switch googleConnection?.connectionStatus {
        case .connected: return "Google Calendar connected"
        case .syncing, .initialSync: return "Google Calendar syncing"
        case .needsReconnect: return "Google Calendar needs reconnect"
        default: return "Manage Google Calendar sync"
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

    private func goToToday() {
        let today = calendar.startOfDay(for: .now)
        withAnimation(.easeOut(duration: 0.2)) {
            monthAnchor = .now
            selectedDate = today
        }
        weekScrollToken += 1
    }


    private func forceSyncIntervals() {
        forceSyncStatus = "Syncing planned workouts to intervals.icu…"
        Task {
            await pushService.reconcile()
            await MainActor.run {
                if let error = pushService.lastPushError {
                    forceSyncStatus = "intervals.icu sync failed: \(error)"
                } else if let lastPushAt = pushService.lastPushAt {
                    forceSyncStatus = "intervals.icu synced \(lastPushAt.formatted(date: .abbreviated, time: .shortened))"
                } else {
                    forceSyncStatus = "intervals.icu sync skipped. Enable Watch push in Profile first."
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

private struct ForceIntervalsSyncStatusView: View {
    var status: String?

    var body: some View {
        if let status {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                Text(status)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Theme.card)
        }
    }
}

private struct RecentCoachChangesView: View {
    var edits: [PlanEdit]
    var error: String?
    var onRevert: (PlanEdit) -> Void

    var body: some View {
        if !edits.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(edits.prefix(1)) { edit in
                    row(edit)
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
            Text("Coach updated 1 workout · \(summary(for: edit))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Spacer(minLength: 8)
            Button {
                onRevert(edit)
            } label: {
                Text("Undo")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.accent)
                    .frame(minWidth: 54, minHeight: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Undo Coach workout change")
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .frame(minHeight: 44)
        .background(Theme.chip, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }

    private func summary(for edit: PlanEdit) -> String {
        "\(kindName(edit.kindRaw)) \(km(edit.distanceKm)) km -> \(kindName(edit.afterKindRaw)) \(km(edit.afterDistanceKm)) km"
    }

    private func kindName(_ raw: String) -> String {
        WorkoutKind(rawValue: raw)?.displayName ?? raw.capitalized
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
        case .intervals: "Intervals"
        case .race: "Race"
        }
    }

    var symbolName: String {
        switch self {
        case .easy: "figure.run"
        case .long: "arrow.up.right.circle"
        case .tempo: "gauge.with.needle"
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
