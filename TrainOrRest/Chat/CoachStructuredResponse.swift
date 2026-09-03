import Foundation

enum CoachResponseStatus: String, Codable, Equatable {
    case ready
    case recoveryRecommended = "recovery_recommended"
    case adjustmentRecommended = "adjustment_recommended"
    case attention
    case insufficientData = "insufficient_data"
}

struct CoachMetric: Codable, Equatable, Identifiable {
    enum Status: String, Codable, Equatable {
        case positive
        case neutral
        case attention
        case unknown
    }

    var id: String
    var label: String
    var value: String
    var interpretation: String?
    var status: Status
}

struct CoachRecommendation: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var description: String?
    var priority: Int
}

struct CoachAction: Codable, Equatable, Identifiable {
    enum Kind: String, Codable, Equatable {
        case adjustPlan = "adjust_plan"
        case keepPlan = "keep_plan"
        case reviewWorkout = "review_workout"
        case openDetail = "open_detail"
        case sendPrompt = "send_prompt"
    }

    var id: String
    var type: Kind
    var label: String
    var payload: JSONValue?
}

struct CoachDetailSection: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var markdown: String
}

struct CoachResponseDetails: Codable, Equatable {
    var title: String
    var sections: [CoachDetailSection]
}

struct CoachDataSource: Codable, Equatable, Identifiable {
    enum Kind: String, Codable, Equatable {
        case healthData = "health_data"
        case completedWorkout = "completed_workout"
        case trainingPlan = "training_plan"
        case upcomingWorkouts = "upcoming_workouts"
        case raceGoal = "race_goal"
    }

    var id: String
    var type: Kind
    var label: String
    var updatedAt: Date?
}

struct CoachStructuredResponse: Codable, Equatable {
    var title: String
    var summary: String
    var safetyNote: String? = nil
    var recommendations: [CoachRecommendation]
    var details: CoachResponseDetails?
    var followUps: [CoachChoiceOption]
    var status: CoachResponseStatus?
    var metrics: [CoachMetric]
    var primaryAction: CoachAction?
    var secondaryAction: CoachAction?
    var sources: [CoachDataSource]
}

enum CoachResponseLimits {
    static let maxRecommendations = 3
    static let maxFollowUps = 3
}

extension CoachStructuredResponsePayload {
    // Builds a validated model-authored response, or nil when title/summary are
    // absent so the caller keeps the legacy text. Overflow recommendations move
    // into details; nothing is dropped.
    func validatedStructuredResponse(additionalRecommendationsTitle: String) -> CoachStructuredResponse? {
        let trimmedTitle = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSummary = (summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedSummary.isEmpty else { return nil }
        let trimmedSafetyNote = safetyNote?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanRecommendations = dedupedByCoachID((recommendations ?? []).filter { !$0.title.isCoachBlank })
        let sorted = cleanRecommendations.sorted { $0.priority < $1.priority }
        let visible = Array(sorted.prefix(CoachResponseLimits.maxRecommendations))
        let overflow = Array(sorted.dropFirst(CoachResponseLimits.maxRecommendations))
        var sections = dedupedByCoachID((details?.sections ?? []).filter { !$0.title.isCoachBlank || !$0.markdown.isCoachBlank })
        if !overflow.isEmpty {
            let markdown = overflow.enumerated().map { index, rec in rec.description.map { "\(index + 1). \(rec.title): \($0)" } ?? "\(index + 1). \(rec.title)" }.joined(separator: "\n")
            sections.removeAll { $0.id == "additional-recommendations" }
            sections.append(CoachDetailSection(id: "additional-recommendations", title: additionalRecommendationsTitle, markdown: markdown))
        }
        let resolvedDetails: CoachResponseDetails?
        if sections.isEmpty {
            resolvedDetails = nil
        } else {
            resolvedDetails = CoachResponseDetails(title: details?.title ?? additionalRecommendationsTitle, sections: sections)
        }
        let cleanFollowUps = dedupedByCoachID((followUps ?? []).filter { !$0.label.isCoachBlank || !$0.value.isCoachBlank })
        return CoachStructuredResponse(title: trimmedTitle, summary: trimmedSummary, safetyNote: trimmedSafetyNote?.isEmpty == true ? nil : trimmedSafetyNote, recommendations: visible, details: resolvedDetails, followUps: Array(cleanFollowUps.prefix(CoachResponseLimits.maxFollowUps)), status: nil, metrics: [], primaryAction: nil, secondaryAction: nil, sources: [])
    }
}

private extension String {
    var isCoachBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

private func dedupedByCoachID<T: Identifiable>(_ items: [T]) -> [T] {
    var seen = Set<T.ID>()
    return items.filter { seen.insert($0.id).inserted }
}
