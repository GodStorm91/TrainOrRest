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

    @State private var mode: Mode = .month
    @State private var monthAnchor: Date = .now
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: .now)
    @State private var weekScrollToken = 0
    @State private var isEditingGoal = false
    @State private var revertError: String?
    @State private var forceSyncStatus: String?

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            topBar
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
            TorCard(padding: 12, cornerRadius: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.uturn.backward.circle")
                            .foregroundStyle(Theme.accent)
                        Text("Recent coach changes")
                            .font(.torHeading(16, .semibold))
                            .foregroundStyle(Theme.text)
                    }

                    ForEach(edits) { edit in
                        row(edit)
                    }

                    if let error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Theme.bad)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private func row(_ edit: PlanEdit) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(summary(for: edit))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                Text(edit.appliedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(Theme.faint)
            }
            Spacer(minLength: 8)
            Button {
                onRevert(edit)
            } label: {
                Label("Revert", systemImage: "arrow.uturn.backward")
                    .labelStyle(.titleAndIcon)
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Revert coach change")
        }
        .padding(.vertical, 2)
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
