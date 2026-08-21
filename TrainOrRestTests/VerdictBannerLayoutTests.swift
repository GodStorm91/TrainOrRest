import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import TrainOrRest

@MainActor
final class VerdictBannerLayoutTests: XCTestCase {
    private static let seWidth: CGFloat = 320
    private static let epsilon: CGFloat = 0.5

    private let today = PlanEngineTestSupport.date(2026, 1, 5)
    private let dynamicTypeSizes: [DynamicTypeSize] = [.large, .accessibility3, .accessibility5]

    func testConflictBannerFitsIPhoneSEWidthAcrossAccessibilityDynamicType() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let readiness = makeHedgedDownshiftReadiness()
        let workout = makeQualityWorkout()
        context.insert(readiness)
        context.insert(workout)
        try context.save()

        let measurements = measureBanner(readiness: readiness, workout: workout)

        record(measurements, label: "conflict")
        assertValidMeasurements(measurements, label: "conflict")
        assertHeightsAreMonotonic(measurements, label: "conflict")
        XCTAssertGreaterThan(
            try height(for: .accessibility5, in: measurements),
            try height(for: .large, in: measurements),
            "Content-rich conflict banner should grow at AX5 instead of collapsing or clipping."
        )
    }

    func testInsufficientDataBannerFitsIPhoneSEWidthAcrossAccessibilityDynamicType() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let readiness = makeInsufficientDataReadiness()
        context.insert(readiness)
        try context.save()

        let measurements = measureBanner(readiness: readiness, workout: nil)

        record(measurements, label: "insufficient data")
        assertValidMeasurements(measurements, label: "insufficient data")
        assertHeightsAreMonotonic(measurements, label: "insufficient data")
    }

    private func measureBanner(readiness: DailyReadiness?, workout: PlannedWorkout?) -> [LayoutMeasurement] {
        dynamicTypeSizes.map { size in
            let banner = VerdictBannerView(
                readiness: readiness,
                workout: workout,
                lastSyncAt: .distantFuture
            )
            .dynamicTypeSize(size)
            .frame(width: Self.seWidth, alignment: .leading)

            let hostingController = UIHostingController(rootView: banner)
            hostingController.view.bounds = CGRect(
                origin: .zero,
                size: CGSize(width: Self.seWidth, height: 1)
            )
            hostingController.view.setNeedsLayout()
            hostingController.view.layoutIfNeeded()

            let fittingSize = hostingController.sizeThatFits(in: CGSize(
                width: Self.seWidth,
                height: .greatestFiniteMagnitude
            ))
            return LayoutMeasurement(dynamicTypeSize: size, fittingSize: fittingSize)
        }
    }

    private func assertValidMeasurements(_ measurements: [LayoutMeasurement], label: String) {
        for measurement in measurements {
            XCTAssertTrue(
                measurement.fittingSize.height.isFinite,
                "\(label) \(measurement.dynamicTypeSize) height must be finite."
            )
            XCTAssertGreaterThan(
                measurement.fittingSize.height,
                0,
                "\(label) \(measurement.dynamicTypeSize) height must be positive."
            )
            XCTAssertLessThanOrEqual(
                measurement.fittingSize.width,
                Self.seWidth + Self.epsilon,
                "\(label) \(measurement.dynamicTypeSize) must fit within iPhone SE width."
            )
        }
    }

    private func record(_ measurements: [LayoutMeasurement], label: String) {
        let summary = measurements
            .map { "\($0.dynamicTypeSize): \(format($0.fittingSize.width)) x \(format($0.fittingSize.height))" }
            .joined(separator: ", ")
        print("VerdictBannerLayout \(label): \(summary)")
    }

    private func format(_ value: CGFloat) -> String {
        String(format: "%.1f", Double(value))
    }

    private func assertHeightsAreMonotonic(_ measurements: [LayoutMeasurement], label: String) {
        for index in 1..<measurements.count {
            let previous = measurements[index - 1]
            let current = measurements[index]
            XCTAssertGreaterThanOrEqual(
                current.fittingSize.height,
                previous.fittingSize.height - Self.epsilon,
                "\(label) height should not shrink from \(previous.dynamicTypeSize) to \(current.dynamicTypeSize)."
            )
        }
    }

    private func height(for size: DynamicTypeSize, in measurements: [LayoutMeasurement]) throws -> CGFloat {
        try XCTUnwrap(measurements.first { $0.dynamicTypeSize == size }?.fittingSize.height)
    }

    private func makeHedgedDownshiftReadiness() -> DailyReadiness {
        DailyReadiness(
            date: today,
            assessment: ReadinessAssessment(
                verdict: .goEasy,
                score: 58,
                reasons: [
                    "HRV 42 ms below 58 ms baseline band while training load is ramping fast (1.42x your usual)"
                ],
                ruleIDs: [.hrvLow, .loadRamp, .persistenceHold],
                hedged: true,
                primaryRule: .hrv,
                corroboratedFlagCount: 2,
                baselineDayCount: 42,
                snapshot: ReadinessAssessment.Snapshot(
                    hrvMean7: 42,
                    hrvMean28: 58,
                    rhrMean7: 58,
                    rhrMean28: 51,
                    sleepLastNight: 5.4,
                    sleepMean14: 7.2,
                    acuteChronicRatio: 1.42,
                    hrvBaseline: 58,
                    hrvSD: 6,
                    rhrBaseline: 51,
                    rhrSD: 3
                )
            ),
            computedAt: today
        )
    }

    private func makeInsufficientDataReadiness() -> DailyReadiness {
        DailyReadiness(
            date: today,
            assessment: ReadinessAssessment(
                verdict: .insufficientData,
                score: nil,
                reasons: [],
                baselineDayCount: 5,
                snapshot: ReadinessAssessment.Snapshot(
                    hrvMean7: nil,
                    hrvMean28: nil,
                    rhrMean7: nil,
                    rhrMean28: nil,
                    sleepLastNight: nil,
                    sleepMean14: nil,
                    acuteChronicRatio: nil
                )
            ),
            computedAt: today
        )
    }

    private func makeQualityWorkout() -> PlannedWorkout {
        PlannedWorkout(
            spec: PlannedWorkoutSpec(
                date: today,
                kind: .intervals,
                distanceKm: 11.2,
                paceBand: PaceBand(fastSecondsPerKm: 250, slowSecondsPerKm: 265),
                details: "6 x 800m at 5K pace with controlled float recoveries",
                structure: [
                    WorkoutStepGroup(steps: [
                        WorkoutStep(role: .warmUp, distanceKm: 2),
                    ]),
                    WorkoutStepGroup(repeatCount: 6, steps: [
                        WorkoutStep(
                            role: .work,
                            distanceKm: 0.8,
                            paceBand: PaceBand(fastSecondsPerKm: 250, slowSecondsPerKm: 265)
                        ),
                        WorkoutStep(role: .recovery, durationSeconds: 120),
                    ]),
                    WorkoutStepGroup(steps: [
                        WorkoutStep(role: .coolDown, distanceKm: 2),
                    ]),
                ]
            ),
            weekIndex: 0,
            phase: .build
        )
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            CompletedActivity.self, DailyWellness.self, SyncState.self, Goal.self,
            TrainingPlan.self, PlannedWorkout.self, DailyReadiness.self, DailyCheckIn.self,
            RuleOverride.self, PlanSnapshot.self, ChatThread.self, ChatMessage.self, CoachRequestSnapshot.self, PlanEdit.self
        ])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    private struct LayoutMeasurement {
        let dynamicTypeSize: DynamicTypeSize
        let fittingSize: CGSize
    }
}
