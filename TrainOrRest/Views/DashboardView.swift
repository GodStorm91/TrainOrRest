import SwiftData
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var engine: SyncEngine
    @Query(sort: \DailyWellness.date, order: .reverse) private var wellness: [DailyWellness]
    @Query(sort: \CompletedActivity.date, order: .reverse) private var activities: [CompletedActivity]
    @Query private var syncStates: [SyncState]

    var body: some View {
        NavigationStack {
            List {
                if wellness.isEmpty && activities.isEmpty {
                    waitingSection
                } else {
                    wellnessSection
                    recentActivitiesSection
                }
                freshnessFooter
            }
            .navigationTitle("TrainOrRest")
            .refreshable { await engine.syncAll() }
            .overlay(alignment: .top) {
                if let error = engine.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.red, in: Capsule())
                        .padding(.top, 4)
                }
            }
        }
    }

    private var waitingSection: some View {
        Section {
            ContentUnavailableView(
                "Waiting for Garmin Data",
                systemImage: "arrow.triangle.2.circlepath",
                description: Text("No health data found yet. Make sure Garmin Connect is syncing to Apple Health, then pull to refresh. If you denied Health access, re-enable it in Settings → Health → Data Access & Devices.")
            )
        }
    }

    private var wellnessSection: some View {
        Section("Today's Signals") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                MetricCard(
                    title: "HRV",
                    value: Formatters.decimal(latest(\.hrvSDNN)?.value, unit: "ms"),
                    date: latest(\.hrvSDNN)?.date,
                    symbol: "waveform.path.ecg"
                )
                MetricCard(
                    title: "Resting HR",
                    value: Formatters.heartRate(latest(\.restingHeartRate)?.value),
                    date: latest(\.restingHeartRate)?.date,
                    symbol: "heart.fill"
                )
                MetricCard(
                    title: "Sleep",
                    value: Formatters.sleep(latest(\.sleepHours)?.value),
                    date: latest(\.sleepHours)?.date,
                    symbol: "bed.double.fill"
                )
                MetricCard(
                    title: "VO₂max",
                    value: Formatters.decimal(latest(\.vo2Max)?.value, unit: "ml/kg/min"),
                    date: latest(\.vo2Max)?.date,
                    symbol: "lungs.fill"
                )
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            .listRowBackground(Color.clear)
        }
    }

    private var recentActivitiesSection: some View {
        Section {
            if activities.isEmpty {
                Text("No runs synced yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(activities.prefix(5)) { activity in
                    NavigationLink {
                        ActivityDetailView(activity: activity)
                    } label: {
                        ActivityRow(activity: activity)
                    }
                }
                NavigationLink("All Activities") {
                    ActivityListView()
                }
            }
        } header: {
            Text("Recent Runs")
        }
    }

    private var freshnessFooter: some View {
        Section {
        } footer: {
            if let syncedAt = syncStates.compactMap(\.lastSyncAt).max() {
                Text("Garmin data as of \(syncedAt.formatted(date: .abbreviated, time: .shortened))")
            } else {
                Text("Not synced yet")
            }
        }
    }

    /// Most recent day that actually has a value for the given metric —
    /// Garmin metrics land on different days depending on sync latency.
    private func latest(_ metric: (DailyWellness) -> Double?) -> (value: Double, date: Date)? {
        for day in wellness {
            if let value = metric(day) {
                return (value, day.date)
            }
        }
        return nil
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let date: Date?
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
            if let date {
                Text(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct ActivityRow: View {
    let activity: CompletedActivity

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(activity.date.formatted(date: .abbreviated, time: .shortened))
                .font(.subheadline.weight(.medium))
            HStack(spacing: 12) {
                Text(Formatters.kilometers(activity.distanceMeters))
                Text(Formatters.pace(activity.avgPaceSecondsPerKm))
                Text(Formatters.duration(activity.durationSeconds))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
