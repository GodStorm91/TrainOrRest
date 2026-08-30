import SwiftUI

struct CoachResponseCard: View {
    let response: CoachStructuredResponse
    let language: CoachLanguage

    var body: some View {
        TorCard(padding: 16, cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 14) {
                if let status = response.status {
                    TorEyebrow(language.coachStatusLabel(for: status), color: statusColor(status))
                }

                if !response.title.isEmpty {
                    Text(response.title)
                        .font(.torHeading(22, .bold))
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !response.summary.isEmpty {
                    Text(response.summary)
                        .font(.subheadline)
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !response.metrics.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(response.metrics) { metric in
                            metricRow(metric)
                        }
                    }
                }

                if !response.recommendations.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(response.recommendations.enumerated()), id: \.element.id) { index, recommendation in
                            recommendationRow(index + 1, recommendation)
                        }
                    }
                }

                if !response.sources.isEmpty {
                    Text(language.coachBasedOnSourcesLabel(count: response.sources.count))
                        .font(.caption)
                        .foregroundStyle(Theme.faint)
                }
            }
        }
    }

    private func metricRow(_ metric: CoachMetric) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(metric.label)
                .font(.subheadline)
                .foregroundStyle(Theme.dim)

            Spacer(minLength: 8)

            Text(metric.value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.text)

            if let interpretation = metric.interpretation {
                Text("· \(interpretation)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(metricColor(metric.status))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(metricAccessibilityLabel(metric))
    }

    private func metricAccessibilityLabel(_ metric: CoachMetric) -> String {
        "\(metric.label): \(metric.value)\(metric.interpretation.map { " · \($0)" } ?? "")"
    }

    private func recommendationRow(_ number: Int, _ recommendation: CoachRecommendation) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(recommendation.title)
                    .font(.subheadline)
                    .foregroundStyle(Theme.text)

                if let description = recommendation.description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(Theme.dim)
                }
            }
        }
    }

    private func statusColor(_ status: CoachResponseStatus) -> Color {
        switch status {
        case .ready: Theme.verdictTrain
        case .recoveryRecommended: Theme.verdictRest
        case .adjustmentRecommended: Theme.accent
        case .attention: Theme.warn
        case .insufficientData: Theme.faint
        }
    }

    private func metricColor(_ status: CoachMetric.Status) -> Color {
        switch status {
        case .positive: Theme.good
        case .neutral: Theme.dim
        case .attention: Theme.warn
        case .unknown: Theme.faint
        }
    }
}

#Preview("Full") {
    CoachResponseCard(
        response: CoachStructuredResponse(
            title: "Prioritize recovery today",
            summary: "Your recent training load is elevated. A lighter day will help you absorb the work and return fresher for your next quality session.",
            recommendations: [
                .init(id: "easy", title: "Keep today easy", description: "Run conversationally or take a short walk.", priority: 1),
                .init(id: "sleep", title: "Protect your sleep", description: "Aim for an earlier bedtime tonight.", priority: 2),
                .init(id: "fuel", title: "Refuel well", description: "Include carbohydrates and protein after training.", priority: 3)
            ],
            details: nil,
            followUps: [],
            status: .recoveryRecommended,
            metrics: [
                .init(id: "load", label: "ACWR", value: "1.2", interpretation: "Stable", status: .neutral),
                .init(id: "sleep", label: "Sleep", value: "7h", interpretation: "Needs attention", status: .attention)
            ],
            primaryAction: nil,
            secondaryAction: nil,
            sources: [
                .init(id: "health", type: .healthData, label: "Health data", updatedAt: nil),
                .init(id: "plan", type: .trainingPlan, label: "Current plan", updatedAt: nil)
            ]
        ),
        language: .en
    )
    .padding()
    .background(Theme.bg)
}

#Preview("Minimal") {
    CoachResponseCard(
        response: CoachStructuredResponse(
            title: "Stay consistent",
            summary: "Your current routine is supporting your goal.",
            recommendations: [],
            details: nil,
            followUps: [],
            status: nil,
            metrics: [],
            primaryAction: nil,
            secondaryAction: nil,
            sources: []
        ),
        language: .en
    )
    .padding()
    .background(Theme.bg)
}
