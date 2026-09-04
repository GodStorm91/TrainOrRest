import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import TrainOrRest

/// Measures how long the calendar views take to lay out a year of plan data.
@MainActor
final class CalendarRenderPerformanceTests: XCTestCase {
    private let calendar = Calendar.current
    private let width: CGFloat = 393

    func testMonthViewSweepsTwelveMonths() throws {
        let container = try makeContainer()
        let (workouts, activities) = try seedYear(in: container.mainContext)
        let anchors = (0..<12).compactMap { calendar.date(byAdding: .month, value: $0 - 6, to: .now) }
        let model = MonthHostModel(anchor: anchors[0])
        let host = UIHostingController(
            rootView: MonthHost(model: model, workouts: workouts, activities: activities)
                .modelContainer(container)
        )
        let window = UIWindow(frame: CGRect(origin: .zero, size: CGSize(width: width, height: 852)))
        window.rootViewController = host
        window.makeKeyAndVisible()
        pump()

        measure {
            for anchor in anchors {
                model.anchor = anchor
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
            }
        }
        window.isHidden = true
    }

    /// Lets SwiftUI flush the pending body update for the last state change.
    private func pump() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }

    func testWeekListExpandsEveryWeek() throws {
        let container = try makeContainer()
        _ = try seedYear(in: container.mainContext)
        let model = WeekHostModel()
        let host = UIHostingController(rootView: WeekHost(model: model).modelContainer(container))
        let window = UIWindow(frame: CGRect(origin: .zero, size: CGSize(width: width, height: 852)))
        window.rootViewController = host
        window.makeKeyAndVisible()
        pump()

        measure {
            for _ in 0..<26 {
                model.token += 1
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
            }
        }
        window.isHidden = true
    }

    private struct MonthHost: View {
        @ObservedObject var model: MonthHostModel
        let workouts: [PlannedWorkout]
        let activities: [CompletedActivity]
        @State private var selected = Date.now
        private let runSchedule = RunScheduleController()

        var body: some View {
            NavigationStack {
                PlanMonthView(
                    workouts: workouts,
                    language: .en,
                    completedActivities: activities,
                    monthAnchor: $model.anchor,
                    selectedDate: $selected
                )
                .environmentObject(runSchedule)
            }
        }
    }

    private final class MonthHostModel: ObservableObject {
        @Published var anchor: Date
        init(anchor: Date) { self.anchor = anchor }
    }

    private struct WeekHost: View {
        @ObservedObject var model: WeekHostModel

        var body: some View {
            NavigationStack {
                PlanWeekListView(scrollToTodayToken: model.token, language: .en)
            }
        }
    }

    private final class WeekHostModel: ObservableObject {
        @Published var token = 0
    }

    private func seedYear(in context: ModelContext) throws -> ([PlannedWorkout], [CompletedActivity]) {
        let start = calendar.date(byAdding: .month, value: -6, to: calendar.startOfDay(for: .now))!
        let kinds: [WorkoutKind] = [.easy, .tempo, .easy, .long]
        var workouts: [PlannedWorkout] = []
        var activities: [CompletedActivity] = []
        for week in 0..<52 {
            for (offset, kind) in zip([0, 2, 4, 6], kinds) {
                let date = calendar.date(byAdding: .day, value: week * 7 + offset, to: start)!
                let workout = PlannedWorkout(
                    spec: PlannedWorkoutSpec(date: date, kind: kind, distanceKm: 8 + Double(offset), paceBand: nil, details: "", structure: []),
                    weekIndex: week,
                    phase: .build
                )
                context.insert(workout)
                workouts.append(workout)
                if date < .now {
                    let activity = CompletedActivity(
                        hkUUID: UUID(),
                        date: date.addingTimeInterval(6 * 3600),
                        distanceMeters: workout.distanceKm * 1000,
                        durationSeconds: workout.distanceKm * 330,
                        avgHeartRate: 150,
                        maxHeartRate: 170,
                        avgPaceSecondsPerKm: 330,
                        sourceName: "Garmin"
                    )
                    context.insert(activity)
                    activities.append(activity)
                }
            }
        }
        try context.save()
        return (workouts, activities)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            CompletedActivity.self, DailyWellness.self, SyncState.self, Goal.self,
            TrainingPlan.self, PlannedWorkout.self, DailyReadiness.self, DailyCheckIn.self,
            RuleOverride.self, PlanSnapshot.self, ChatThread.self, ChatMessage.self,
            CoachRequestSnapshot.self, PlanEdit.self, RunningShoe.self
        ])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }
}
