import SwiftData
import SwiftUI

/// Run History: an overview card of real aggregates over the selected period,
/// then the run list. Reached from Profile → Run history.
struct ActivityListView: View {
    @Query(sort: \CompletedActivity.date, order: .reverse) private var activities: [CompletedActivity]
    @State private var period: Period = .month

    private let calendar = Calendar.current

    enum Period: String, CaseIterable, Identifiable {
        case month = "30d"
        case year = "Year"
        var id: Self { self }
        var days: Int { self == .month ? 30 : 365 }
        var eyebrow: String { self == .month ? "Last 30 days" : "Last year" }
    }

    private var filtered: [CompletedActivity] {
        let cutoff = calendar.date(byAdding: .day, value: -period.days, to: .now) ?? .distantPast
        return activities.filter { $0.date >= cutoff }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                periodToggle
                if filtered.isEmpty {
                    emptyState
                } else {
                    OverviewCard(summary: RunHistorySummary(activities: filtered), eyebrow: period.eyebrow)
                    TorEyebrow("Activities").tracking(2)
                    LazyVStack(spacing: 10) {
                        ForEach(filtered) { activity in
                            NavigationLink {
                                ActivityDetailView(activity: activity)
                            } label: {
                                ActivityRow(activity: activity)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Theme.bg)
        .scrollIndicators(.hidden)
        .navigationTitle("Run History")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.easeOut(duration: 0.22), value: filtered.count)
    }

    private var periodToggle: some View {
        HStack {
            Spacer()
            HStack(spacing: 4) {
                ForEach(Period.allCases) { option in
                    let selected = option == period
                    Text(option.rawValue)
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
                            withAnimation(.easeOut(duration: 0.15)) { period = option }
                        }
                }
            }
            .padding(3)
            .background(Theme.chip, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Runs Yet",
            systemImage: "figure.run",
            description: Text("Runs recorded on your Garmin will appear here after Garmin Connect syncs to Apple Health.")
        )
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}

/// Aggregates card — distance headline plus pace / time / longest chips.
private struct OverviewCard: View {
    let summary: RunHistorySummary
    let eyebrow: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TorEyebrow(eyebrow).tracking(1.6).foregroundStyle(Theme.dim)

            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(String(format: "%.1f", summary.totalDistanceMeters / 1000))
                    .font(.torNumber(44, .bold))
                    .foregroundStyle(Theme.text)
                Text("km")
                    .font(.torHeading(16, .semibold))
                    .foregroundStyle(Theme.dim)
            }
            Text("total distance · \(summary.runCount) \(summary.runCount == 1 ? "run" : "runs")")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.faint)

            HStack(spacing: 10) {
                stat(paceText, "AVG PACE", Theme.text)
                stat(Formatters.duration(summary.totalDurationSeconds), "TOTAL TIME", Theme.text)
                stat(longestText, "LONGEST km", Theme.good)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }

    private var paceText: String {
        guard let pace = summary.averagePaceSecondsPerKm else { return "–" }
        return Formatters.pace(pace).replacingOccurrences(of: " /km", with: "")
    }

    private var longestText: String {
        guard let meters = summary.longestDistanceMeters else { return "–" }
        return String(format: "%.1f", meters / 1000)
    }

    private func stat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.torHeading(17, .bold)).foregroundStyle(color)
            Text(label).font(.system(size: 9.5, weight: .semibold)).tracking(0.5).foregroundStyle(Theme.faint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 11)
        .background(Theme.chip, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}
