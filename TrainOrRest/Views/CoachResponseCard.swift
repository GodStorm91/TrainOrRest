import SwiftUI

struct CoachResponseCard: View {
    let response: CoachStructuredResponse
    let language: CoachLanguage
    var timestamp: Date? = nil
    var followUpsConsumed: Bool = false
    var onSelectFollowUp: (CoachChoiceOption) -> Void = { _ in }

    @State private var showsDetail = false
    @State private var showsSources = false

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
                        .accessibilityAddTraits(.isHeader)
                }

                if !response.summary.isEmpty {
                    CoachGlossaryText(
                        text: response.summary,
                        mode: .structured,
                        language: language,
                        font: .subheadline,
                        color: Theme.dim,
                        values: glossaryValues
                    )
                    .fixedSize(horizontal: false, vertical: true)
                }

                if let note = response.safetyNote, !note.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.warn)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(language.coachSafetyLabel)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Theme.warn)

                            Text(note)
                                .font(.subheadline)
                                .foregroundStyle(Theme.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.soft(Theme.warn), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityElement(children: .combine)
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

                if response.details != nil {
                    Button {
                        showsDetail = true
                    } label: {
                        HStack(spacing: 6) {
                            Text(language.coachViewDetailLabel)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(language.coachViewDetailLabel)
                    .accessibilityAddTraits(.isButton)
                }

                if !response.followUps.isEmpty && !followUpsConsumed {
                    FlowLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(response.followUps) { option in
                            Button {
                                onSelectFollowUp(option)
                            } label: {
                                Text(option.label)
                                    .font(.subheadline)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(Theme.chip, in: Capsule())
                                    .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
                                    .foregroundStyle(Theme.text)
                            }
                            .buttonStyle(.plain)
                            .frame(minHeight: 44)
                            .contentShape(Capsule())
                            .accessibilityLabel(option.visibleSelectionText)
                            .accessibilityAddTraits(.isButton)
                        }
                    }
                }

                if !response.sources.isEmpty {
                    Button {
                        showsSources = true
                    } label: {
                        Text(sourceAttributionText)
                            .font(.caption)
                            .foregroundStyle(Theme.faint)
                            .frame(minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(sourceAttributionText)
                    .accessibilityHint(language.coachViewSourcesHint)
                    .accessibilityAddTraits(.isButton)
                }
            }
            .sheet(isPresented: $showsDetail) {
                if let details = response.details {
                    CoachDetailSheet(details: details, language: language)
                }
            }
            .sheet(isPresented: $showsSources) {
                CoachSourcesSheet(sources: response.sources, language: language)
            }
        }
    }

    private var sourceAttributionText: String {
        var text = language.coachBasedOnSourcesLabel(count: response.sources.count)
        if let timestamp {
            text += " · \(Self.updatedTimeText(timestamp, language: language))"
        }
        return text
    }

    private var glossaryValues: [String: String] {
        response.metrics.reduce(into: [:]) { values, metric in
            guard let term = CoachGlossary.term(matchingAlias: metric.label) else { return }
            values[term.id] = metric.value
        }
    }


    static func updatedTimeText(_ date: Date, language: CoachLanguage) -> String {
        language.coachUpdatedAtLabel(date.formatted(.dateTime.hour().minute().locale(language.uiLocale)))
    }

    private func metricRow(_ metric: CoachMetric) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(metricLabel(metric))
                .font(.subheadline)
                .foregroundStyle(Theme.dim)

            Spacer(minLength: 8)

            Text(metric.value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.text)

            if let interpretation = metricInterpretation(metric) {
                Text("· \(interpretation)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(metricColor(metric.status))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(metricAccessibilityLabel(metric))
    }

    private func metricAccessibilityLabel(_ metric: CoachMetric) -> String {
        "\(metricLabel(metric)): \(metric.value)\(metricInterpretation(metric).map { " · \($0)" } ?? "")"
    }

    private func metricLabel(_ metric: CoachMetric) -> String {
        language.metricLabel(for: metric.id, fallback: metric.label)
    }

    private func metricInterpretation(_ metric: CoachMetric) -> String? {
        language.metricInterpretation(for: metric.status, fallback: metric.interpretation)
    }

    private func recommendationRow(_ number: Int, _ recommendation: CoachRecommendation) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.accent)

            VStack(alignment: .leading, spacing: 2) {
                CoachGlossaryText(
                    text: recommendation.title,
                    mode: .structured,
                    language: language,
                    font: .subheadline,
                    color: Theme.text,
                    values: glossaryValues
                )

                if let description = recommendation.description {
                    CoachGlossaryText(
                        text: description,
                        mode: .structured,
                        language: language,
                        font: .caption,
                        color: Theme.dim,
                        values: glossaryValues
                    )
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
            followUps: [
                .init(id: "increase-load", label: "Should I increase my training load next week?", description: nil, value: "Should I increase my training load next week?"),
                .init(id: "recovery-nutrition", label: "What should I eat to recover?", description: nil, value: "What should I eat to recover?")
            ],
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
