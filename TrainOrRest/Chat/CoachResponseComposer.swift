import Foundation

enum CoachResponseComposer {
    static func status(for verdict: ReadinessVerdict) -> CoachResponseStatus {
        switch verdict {
        case .train:
            .ready
        case .goEasy, .rest:
            .recoveryRecommended
        case .insufficientData:
            .insufficientData
        }
    }

    static func metrics(from readiness: DailyReadiness, language: CoachLanguage) -> [CoachMetric] {
        let flagged = flaggedSignalIDs(from: readiness.ruleIDs)
        return ReadinessRationale(from: readiness).signals.compactMap { signal in
            guard
                let value = metricValue(for: signal.id, readiness: readiness, language: language),
                let label = metricLabel(for: signal.id, language: language)
            else {
                return nil
            }

            let status: CoachMetric.Status = flagged.contains(signal.id) ? .attention : .neutral
            return CoachMetric(
                id: signal.id,
                label: label,
                value: value,
                interpretation: interpretation(for: status, language: language),
                status: status
            )
        }
    }

    static func sources(from contextItems: [CoachContextItem], language: CoachLanguage) -> [CoachDataSource] {
        var seen = Set<String>()
        return contextItems.compactMap { item in
            let kind = sourceKind(for: item.type)
            guard seen.insert(kind.rawValue).inserted else { return nil }
            return CoachDataSource(
                id: kind.rawValue,
                type: kind,
                label: sourceLabel(for: kind, language: language),
                updatedAt: nil
            )
        }
    }

    static func compose(
        model: CoachStructuredResponse,
        readiness: DailyReadiness?,
        contextItems: [CoachContextItem],
        language: CoachLanguage
    ) -> CoachStructuredResponse {
        var response = model
        response.status = readiness.map { status(for: $0.verdict) }
        response.metrics = readiness.map { metrics(from: $0, language: language) } ?? []
        response.sources = sources(from: contextItems, language: language)
        return response
    }

    static func formatDistance(kilometers: Double, language: CoachLanguage) -> String {
        let rounded = (kilometers * 10).rounded() / 10
        let value = rounded.rounded() == rounded ? String(Int(rounded)) : String(format: "%.1f", rounded)
        return "\(value) km"
    }

    private static func flaggedSignalIDs(from rules: [ReadinessRuleID]) -> Set<String> {
        var ids = Set<String>()
        for rule in rules {
            switch rule {
            case .hrvLow, .overreaching, .sourceDispute:
                ids.insert("hrv")
            case .rhrElevated:
                ids.insert("rhr")
            case .shortSleep:
                ids.insert("sleep")
            case .loadRamp:
                ids.insert("load")
            default:
                break
            }
        }
        return ids
    }

    private static func metricValue(
        for id: String,
        readiness: DailyReadiness,
        language: CoachLanguage
    ) -> String? {
        switch id {
        case "hrv":
            readiness.hrvMean7.map { "\(Int($0.rounded())) ms" }
        case "rhr":
            readiness.rhrMean7.map { "\(Int($0.rounded())) bpm" }
        case "sleep":
            readiness.sleepLastNight.map { language.sleepHours($0) }
        case "load":
            readiness.acuteChronicRatio.map { String(format: "%.1f", $0) }
        case "score":
            readiness.score.map { "\($0)/100" }
        default:
            nil
        }
    }

    private static func metricLabel(for id: String, language: CoachLanguage) -> String? {
        switch id {
        case "hrv":
            language.metricHRVLabel
        case "rhr":
            language.metricRestingHRLabel
        case "sleep":
            language.metricSleepLabel
        case "load":
            language.metricLoadLabel
        case "score":
            language.metricReadinessLabel
        default:
            nil
        }
    }

    private static func interpretation(for status: CoachMetric.Status, language: CoachLanguage) -> String? {
        switch status {
        case .attention:
            language.metricAttentionNote
        case .neutral:
            language.metricStableNote
        case .positive:
            language.metricGoodNote
        case .unknown:
            nil
        }
    }

    private static func sourceKind(for kind: CoachContextItem.Kind) -> CoachDataSource.Kind {
        switch kind {
        case .healthData:
            .healthData
        case .completedRun:
            .completedWorkout
        case .trainingPlan, .planAssessment:
            .trainingPlan
        case .remainingPlan, .workout:
            .upcomingWorkouts
        case .raceGoal:
            .raceGoal
        }
    }

    private static func sourceLabel(for kind: CoachDataSource.Kind, language: CoachLanguage) -> String {
        switch kind {
        case .healthData:
            language.sourceHealthDataLabel
        case .completedWorkout:
            language.sourceCompletedWorkoutLabel
        case .trainingPlan:
            language.sourceTrainingPlanLabel
        case .upcomingWorkouts:
            language.sourceUpcomingWorkoutsLabel
        case .raceGoal:
            language.sourceRaceGoalLabel
        }
    }
}

enum CoachPlanLookup {
    static func matches(_ text: String) -> Bool {
        let folded = fold(text)
        if chipPhrases.contains(where: { folded.contains($0) }) {
            return true
        }
        guard lookupPhrases.contains(where: { folded.contains($0) }) else {
            return false
        }
        return !advicePhrases.contains(where: { folded.contains($0) })
    }

    static func response(
        summary: ActivePlanSummary?,
        today: Date,
        calendar: Calendar,
        language: CoachLanguage
    ) -> CoachStructuredResponse {
        let workouts = summary?.upcomingWorkouts ?? []
        let next = summary?.nextWorkout ?? workouts.first
        let metrics = workouts.map { workout in
            CoachMetric(
                id: workout.id.uuidString,
                label: dayLabel(workout.date, language: language, calendar: calendar),
                value: "\(workout.displayName) · \(CoachResponseComposer.formatDistance(kilometers: workout.distanceKm, language: language))",
                interpretation: workout.details.isEmpty ? nil : workout.details,
                status: .neutral
            )
        }

        let title: String
        let summaryText: String
        if let next {
            let distance = CoachResponseComposer.formatDistance(kilometers: next.distanceKm, language: language)
            let weekday = dayLabel(next.date, language: language, calendar: calendar)
            title = language.nextWorkoutHeadline(weekday: weekday, kind: next.displayName, distance: distance)
            summaryText = language.nextWorkoutSummary(
                weekday: weekday,
                kind: next.displayName,
                distance: distance,
                isToday: calendar.isDate(next.date, inSameDayAs: today)
            )
        } else if summary == nil {
            title = language.plan.noUpcomingWorkout
            summaryText = language.noPlanLookupSummary
        } else {
            title = language.plan.noUpcomingWorkout
            summaryText = language.plan.noUpcomingWorkout
        }

        return CoachStructuredResponse(
            title: title,
            summary: summaryText,
            safetyNote: nil,
            recommendations: [],
            details: nil,
            followUps: [],
            status: nil,
            metrics: metrics,
            primaryAction: nil,
            secondaryAction: nil,
            sources: [
                CoachDataSource(
                    id: CoachDataSource.Kind.upcomingWorkouts.rawValue,
                    type: .upcomingWorkouts,
                    label: language.sourceUpcomingWorkoutsLabel,
                    updatedAt: nil
                )
            ]
        )
    }

    private static let chipPhrases = [
        "view today's plan",
        "view todays plan",
        "today's plan",
        "todays plan",
        "xem ke hoach hom nay",
        "ke hoach hom nay",
        "今日のプラン",
    ].map(fold)

    private static let lookupPhrases = [
        "next scheduled",
        "next workout",
        "upcoming workout",
        "upcoming session",
        "upcoming plan",
        "scheduled workout",
        "buoi sap toi",
        "cac buoi sap",
        "buoi tap tiep theo",
        "xem chi tiet cac buoi",
        "chi tiet cac buoi",
        "次のワークアウト",
        "今後のワークアウト",
        "今後のプラン",
    ].map(fold)

    private static let advicePhrases = [
        "should i",
        "should we",
        "co nen",
        "skip",
        "dieu chinh",
        "adjust",
        "change my",
        "create workout",
        "tao bai",
    ].map(fold)

    private static func fold(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "vi_VN"))
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "Đ", with: "d")
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
    }

    private static func dayLabel(_ date: Date, language: CoachLanguage, calendar: Calendar) -> String {
        let locale: Locale
        switch language {
        case .en: locale = Locale(identifier: "en_US")
        case .ja: locale = Locale(identifier: "ja_JP")
        case .vi: locale = Locale(identifier: "vi_VN")
        }
        var calendar = calendar
        calendar.locale = locale
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("EEEMd")
        return formatter.string(from: date)
    }
}
