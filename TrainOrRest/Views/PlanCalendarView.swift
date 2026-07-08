import SwiftData
import SwiftUI

/// The training plan tab. Switches between a month calendar grid and the
/// week-by-week list; both share the plan's real workout data.
struct PlanCalendarView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case month = "Month"
        case week = "Week"
        var id: Self { self }
    }

    @Query(sort: \PlannedWorkout.date) private var workouts: [PlannedWorkout]

    @State private var mode: Mode = .month
    @State private var monthAnchor: Date = .now
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: .now)
    @State private var weekScrollToken = 0
    @State private var isEditingGoal = false

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            topBar
            content
        }
        .background(Theme.bg)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Today", systemImage: "calendar") { goToToday() }
                Button("Edit Goal", systemImage: "target") { isEditingGoal = true }
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
            PlanMonthView(workouts: workouts, monthAnchor: $monthAnchor, selectedDate: $selectedDate)
        } else {
            PlanWeekListView(scrollToTodayToken: weekScrollToken)
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
