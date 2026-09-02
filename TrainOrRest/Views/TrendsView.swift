import Charts
import SwiftData
import SwiftUI

/// Trends tab: 28-day readiness + wellness history, all from persisted
/// DailyReadiness / DailyWellness. Compact real charts; richer line/stage
/// charts land in the next round.
struct TrendsView: View {
    @Query(sort: \DailyReadiness.date, order: .reverse) private var readiness: [DailyReadiness]
    @Query(sort: \DailyWellness.date, order: .reverse) private var wellness: [DailyWellness]
    @Query(sort: \CompletedActivity.date, order: .reverse) private var activities: [CompletedActivity]
    private let calendar = Calendar.current
    @AppStorage(CoachLanguage.storageKey) private var languageRaw = CoachLanguage.en.rawValue

    private var language: CoachLanguage { CoachLanguage(rawValue: languageRaw) ?? .en }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                statChips
                readinessBars
                trendLine(title: language.history.heartRateVariability, unit: "ms", color: Theme.data, series: hrvSeries)
                trendLine(title: language.history.restingHeartRate, unit: "bpm", color: Theme.data, series: rhrSeries)
                sleepStagesCard
                if readiness.isEmpty {
                    Text(language.history.trendsEmpty)
                        .font(.system(size: 13)).foregroundStyle(Theme.dim)
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 24)
        }
        .background(Theme.bg)
        .scrollIndicators(.hidden)
    }

    private var last28: [DailyReadiness] {
        let cutoff = calendar.date(byAdding: .day, value: -28, to: .now)!
        return readiness.filter { $0.date >= cutoff }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            TorEyebrow(language.history.lastTwentyEightDays).tracking(2)
            Text(language.history.trends).font(.torHeading(28, .bold)).foregroundStyle(Theme.text)
        }
    }

    private var statChips: some View {
        let scored = last28.compactMap(\.score)
        let avg = scored.isEmpty ? 0 : scored.reduce(0, +) / scored.count
        let trained = last28.filter { $0.verdict == .train }.count
        let rested = last28.filter { $0.verdict == .rest }.count
        return HStack(spacing: 8) {
            statChip("\(avg)", language.history.averageReadiness, Theme.text)
            statChip("\(trained)", language.history.trained, Theme.verdictTrain)
            statChip("\(rested)", language.history.rested, Theme.verdictRest)
            statChip("\(currentStreak)", language.history.streakDays(currentStreak), Theme.data)
        }
    }

    private var currentStreak: Int {
        TrainingStreak.current(activityDates: activities.map(\.date), today: .now, calendar: calendar)
    }

    private func statChip(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.torNumber(22)).foregroundStyle(color)
            Text(label).font(.system(size: 9.5, weight: .semibold)).tracking(0.6).foregroundStyle(Theme.faint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }

    private var readinessBars: some View {
        let week = lastSevenScores
        return TorCard {
            VStack(alignment: .leading, spacing: 14) {
                TorEyebrow(language.history.readinessThisWeek).tracking(1.5)
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(week, id: \.date) { day in
                        VStack(spacing: 6) {
                            Text(day.score.map(String.init) ?? "–")
                                .font(.torHeading(11, .semibold)).foregroundStyle(Theme.dim)
                            RoundedRectangle(cornerRadius: 5)
                                .fill(barColor(day.score))
                                .frame(height: barHeight(day.score))
                            Text(day.label).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.faint)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 130)
            }
        }
    }

    private struct DayScore { var date: Date; var label: String; var score: Int? }

    private var lastSevenScores: [DayScore] {
        (0..<7).reversed().map { back in
            let day = calendar.date(byAdding: .day, value: -back, to: calendar.startOfDay(for: .now))!
            let row = readiness.first { calendar.isDate($0.date, inSameDayAs: day) }
            return DayScore(date: day, label: weekdayInitial(day), score: row?.score)
        }
    }

    private func weekdayInitial(_ date: Date) -> String {
        let weekday = Weekday(rawValue: calendar.component(.weekday, from: date)) ?? .monday
        return language.shortName(weekday)
    }

    private func barColor(_ score: Int?) -> Color {
        guard score != nil else { return Theme.chip }
        return Theme.data
    }

    private func barHeight(_ score: Int?) -> CGFloat {
        guard let score else { return 8 }
        return max(10, CGFloat(score) / 100 * 100)
    }

    // MARK: - Trend lines (HRV / RHR)

    private struct Point: Identifiable { let id = UUID(); var date: Date; var value: Double }

    private func series(_ metric: (DailyWellness) -> Double?, days: Int = 21) -> [Point] {
        let cutoff = calendar.date(byAdding: .day, value: -days, to: .now)!
        return wellness
            .filter { $0.date >= cutoff }
            .compactMap { row in metric(row).map { Point(date: row.date, value: $0) } }
            .sorted { $0.date < $1.date }
    }

    private var hrvSeries: [Point] { series(\.hrvSDNN) }
    private var rhrSeries: [Point] { series(\.restingHeartRate) }

    @ViewBuilder
    private func trendLine(title: String, unit: String, color: Color, series: [Point]) -> some View {
        if series.count >= 2 {
            TorCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        TorEyebrow(title).tracking(1.5)
                        Spacer()
                        if let last = series.last {
                            Text("\(Int(last.value)) \(unit)")
                                .font(.torHeading(15, .bold)).foregroundStyle(Theme.text)
                        }
                    }
                    Chart(series) { point in
                        AreaMark(x: .value(language.history.dayAxis, point.date), y: .value(unit, point.value))
                            .foregroundStyle(LinearGradient(colors: [color.opacity(0.28), .clear], startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value(language.history.dayAxis, point.date), y: .value(unit, point.value))
                            .foregroundStyle(color)
                            .interpolationMethod(.catmullRom)
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis { AxisMarks(position: .leading) }
                    .frame(height: 90)
                }
            }
        }
    }

    // MARK: - Sleep stages (last 7 nights)

    private struct StageBar: Identifiable { let id = UUID(); var label: String; var stage: String; var hours: Double }

    private var sleepStageData: [StageBar] {
        (0..<7).reversed().flatMap { back -> [StageBar] in
            let day = calendar.date(byAdding: .day, value: -back, to: calendar.startOfDay(for: .now))!
            guard let row = wellness.first(where: { calendar.isDate($0.date, inSameDayAs: day) }) else { return [] }
            let label = weekdayInitial(day)
            return [
                StageBar(label: label, stage: language.history.deepSleep, hours: row.deepSleepHours ?? 0),
                StageBar(label: label, stage: language.history.remSleep, hours: row.remSleepHours ?? 0),
                StageBar(label: label, stage: language.history.lightSleep, hours: row.lightSleepHours ?? 0),
            ]
        }
    }

    @ViewBuilder
    private var sleepStagesCard: some View {
        if sleepStageData.contains(where: { $0.hours > 0 }) {
            TorCard {
                VStack(alignment: .leading, spacing: 12) {
                    TorEyebrow(language.history.sleepSevenNights).tracking(1.5)
                    Chart(sleepStageData) { bar in
                        BarMark(
                            x: .value(language.history.nightAxis, bar.label),
                            y: .value(language.history.hoursAxis, bar.hours)
                        )
                        .foregroundStyle(by: .value(language.history.sleepStage, bar.stage))
                    }
                    .chartForegroundStyleScale([
                        language.history.deepSleep: Theme.data,
                        language.history.remSleep: Theme.data.opacity(0.72),
                        language.history.lightSleep: Theme.data.opacity(0.44)
                    ])
                    .chartYAxis { AxisMarks(position: .leading) }
                    .frame(height: 120)
                }
            }
        }
    }
}
