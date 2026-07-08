import SwiftData
import SwiftUI

/// Trends tab: 28-day readiness + wellness history, all from persisted
/// DailyReadiness / DailyWellness. Compact real charts; richer line/stage
/// charts land in the next round.
struct TrendsView: View {
    @Query(sort: \DailyReadiness.date, order: .reverse) private var readiness: [DailyReadiness]
    @Query(sort: \DailyWellness.date, order: .reverse) private var wellness: [DailyWellness]
    private let calendar = Calendar.current

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                statChips
                readinessBars
                if readiness.isEmpty {
                    Text("Trends appear once a few days of readiness are recorded.")
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
            TorEyebrow("Last 28 days").tracking(2)
            Text("Trends").font(.torHeading(28, .bold)).foregroundStyle(Theme.text)
        }
    }

    private var statChips: some View {
        let scored = last28.compactMap(\.score)
        let avg = scored.isEmpty ? 0 : scored.reduce(0, +) / scored.count
        let trained = last28.filter { $0.verdict == .train }.count
        let rested = last28.filter { $0.verdict == .rest }.count
        let best = scored.max() ?? 0
        return HStack(spacing: 8) {
            statChip("\(avg)", "AVG READY", Theme.text)
            statChip("\(trained)", "TRAINED", Theme.good)
            statChip("\(rested)", "RESTED", Theme.bad)
            statChip("\(best)", "BEST", Theme.accent)
        }
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
                TorEyebrow("Readiness · this week").tracking(1.5)
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
        String(date.formatted(.dateTime.weekday(.abbreviated)).prefix(1))
    }

    private func barColor(_ score: Int?) -> Color {
        guard let score else { return Theme.chip }
        return score >= 70 ? Theme.good : score >= 50 ? Theme.warn : Theme.bad
    }

    private func barHeight(_ score: Int?) -> CGFloat {
        guard let score else { return 8 }
        return max(10, CGFloat(score) / 100 * 100)
    }
}
