import SwiftData
import SwiftUI

enum AdaptivePlanReviewSlotAction: Equatable {
    case manualReview
    case retry
    case addKey
}

struct AdaptivePlanReviewSlot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var coordinator: AdaptivePlanReviewCoordinator
    @Query(sort: \AdaptivePlanReview.updatedAt, order: .reverse) private var reviews: [AdaptivePlanReview]
    @AppStorage(CoachLanguage.storageKey) private var languageRaw = CoachLanguage.en.rawValue
    @State private var candidate: CoachPlanCandidate?
    @State private var selectedProviderHasKey = false

    private var language: CoachLanguage { CoachLanguage(rawValue: languageRaw) ?? .en }
    private var review: AdaptivePlanReview? {
        reviews.first { $0.phase != .dismissed }
    }

    var body: some View {
        Group {
            if let review {
                Group {
                    if review.phase == .needsKey && selectedProviderHasKey {
                        manualReviewAction
                    } else {
                        content(for: review)
                    }
                }
                .task(id: presentationID(for: review)) {
                    candidate = nil
                    selectedProviderHasKey = coordinator.selectedProviderHasKey()
                    candidate = coordinator.candidateForPresentation(reviewID: review.id, in: modelContext)
                }
                .onAppear {
                    selectedProviderHasKey = coordinator.selectedProviderHasKey()
                }
            } else {
                manualReviewAction
            }
        }
        .animation(reduceMotion ? .linear(duration: 0.01) : .easeInOut(duration: 0.2), value: review?.phaseRaw)
    }

    @ViewBuilder
    private func content(for review: AdaptivePlanReview) -> some View {
        if (review.phase == .proposal || review.phase == .stale), let candidate {
            VStack(alignment: .leading, spacing: 8) {
                if review.phase == .stale {
                    Label(message(for: .stale), systemImage: symbol(for: .stale))
                        .font(.torHeading(15, .semibold))
                        .foregroundStyle(Theme.text)
                }
                Text(proposalScope(for: review))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
                PlanProposalCard(
                    candidate: candidate,
                    language: language,
                    onApply: {
                        Task {
                            await coordinator.handle(
                                .apply(acknowledging: candidate.loadRisks),
                                reviewID: review.id,
                                in: modelContext
                            )
                        }
                    },
                    onKeep: {
                        Task { await coordinator.handle(.dismiss, reviewID: review.id, in: modelContext) }
                    }
                )
            }
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
        } else {
            TorCard(padding: 14, cornerRadius: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    if review.phase == .preparing {
                        CoachPetView(state: .preparing, reduceMotion: reduceMotion, isActive: true)
                            .frame(width: 54, height: 54)
                            .accessibilityHidden(true)
                    }
                    Label(message(for: review.phase), systemImage: symbol(for: review.phase))
                        .font(.torHeading(15, .semibold))
                        .foregroundStyle(Theme.text)
                    actionButtons(for: review)
                }
            }
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
        }
    }

    @ViewBuilder
    private func actionButtons(for review: AdaptivePlanReview) -> some View {
        switch Self.actions(for: review, selectedProviderHasKey: selectedProviderHasKey).first {
        case .manualReview:
            manualReviewAction
        case .retry:
            retryButton(review)
        case .addKey:
            NavigationLink {
                CoachProviderSettingsView()
            } label: {
                Label(language.plan.addCoachProviderKey, systemImage: "key")
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        case nil:
            EmptyView()
        }
    }

    static func actions(
        for review: AdaptivePlanReview,
        selectedProviderHasKey: Bool
    ) -> [AdaptivePlanReviewSlotAction] {
        switch review.phase {
        case .failed:
            [.retry]
        case .needsKey where selectedProviderHasKey:
            [.manualReview]
        case .needsKey:
            [.addKey]
        case .noChange, .applied, .reverted, .superseded:
            [.manualReview]
        default:
            []
        }
    }

    private var manualReviewAction: some View {
        Button(language.plan.reviewNextSevenDays) {
            Task { await coordinator.beginManualReview(activityID: nil, in: modelContext) }
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accent)
        .font(.torHeading(15, .semibold))
    }

    private func retryButton(_ review: AdaptivePlanReview) -> some View {
        Button(language.plan.retryManually) {
            Task { await coordinator.handle(.retry, reviewID: review.id, in: modelContext) }
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accent)
    }

    private func presentationID(for review: AdaptivePlanReview) -> String {
        "\(review.id.uuidString)-\(review.phaseRaw)-\(review.updatedAt.timeIntervalSinceReferenceDate)"
    }

    private func proposalScope(for review: AdaptivePlanReview) -> String {
        let inclusiveEnd = Calendar.current.date(
            byAdding: .day,
            value: -1,
            to: review.requestedWindowEnd
        ) ?? review.requestedWindowEnd
        let dateRange = Date.IntervalFormatStyle(date: .abbreviated, time: .omitted)
            .locale(language.uiLocale)
            .format(review.requestedWindowStart..<inclusiveEnd)
        return language.plan.nextWeekReviewScope(dateRange)
    }


    private func symbol(for phase: AdaptivePlanReviewPhase) -> String {
        switch phase {
        case .queued: "clock"
        case .needsKey: "key"
        case .preparing: "sparkles"
        case .proposal: "doc.text.magnifyingglass"
        case .noChange: "checkmark.circle"
        case .failed: "exclamationmark.triangle"
        case .stale: "arrow.triangle.2.circlepath"
        case .applied: "checkmark.seal"
        case .reverted: "arrow.uturn.backward"
        case .superseded: "arrow.triangle.branch"
        case .dismissed: "xmark.circle"
        }
    }

    private func message(for phase: AdaptivePlanReviewPhase) -> String {
        switch phase {
        case .queued: language.plan.nextWeekReviewQueued
        case .needsKey: language.plan.nextWeekReviewNeedsKey
        case .preparing: language.plan.nextWeekReviewPreparing
        case .proposal: language.plan.nextWeekReviewReady
        case .noChange: language.plan.nextWeekReviewNoChange
        case .failed: language.plan.nextWeekReviewFailed
        case .stale: language.plan.nextWeekReviewStale
        case .applied: language.plan.nextWeekReviewApplied
        case .reverted: language.plan.nextWeekReviewReverted
        case .superseded: language.plan.nextWeekReviewSuperseded
        case .dismissed: ""
        }
    }
}
