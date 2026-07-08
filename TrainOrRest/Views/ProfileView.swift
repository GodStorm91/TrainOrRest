import SwiftData
import SwiftUI

/// Profile tab: active goal summary plus entries to edit the goal and open
/// settings (API key, etc.). Wraps the existing GoalEntryView / SettingsView.
struct ProfileView: View {
    @Query private var goals: [Goal]
    @State private var showGoalEntry = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Profile").font(.torHeading(28, .bold)).foregroundStyle(Theme.text)

                if let goal = goals.first?.spec {
                    TorCard {
                        VStack(alignment: .leading, spacing: 10) {
                            TorEyebrow("Race goal").tracking(1.5)
                            Text(goal.distance.displayName).font(.torHeading(22, .bold)).foregroundStyle(Theme.text)
                            row("Target", Formatters.duration(goal.targetTimeSeconds))
                            row("Race day", goal.raceDate.formatted(date: .abbreviated, time: .omitted))
                            row("Running days", "\(goal.availableDays.count)/week")
                            Button("Edit goal") { showGoalEntry = true }
                                .font(.torHeading(14, .bold)).foregroundStyle(Theme.accent)
                                .padding(.top, 2)
                        }
                    }
                } else {
                    Button { showGoalEntry = true } label: {
                        Label("Set a race goal", systemImage: "target")
                            .font(.torHeading(16, .bold)).foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }

                navRow("Run history", systemImage: "figure.run") { ActivityListView() }
                navRow("Settings", systemImage: "gearshape") { SettingsView() }
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 24)
        }
        .background(Theme.bg)
        .scrollIndicators(.hidden)
        .sheet(isPresented: $showGoalEntry) { GoalEntryView() }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.dim)
            Spacer()
            Text(value).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
        }
    }

    private func navRow<Destination: View>(
        _ label: String, systemImage: String, @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink(destination: destination) {
            HStack {
                Label(label, systemImage: systemImage)
                    .font(.torHeading(16, .semibold)).foregroundStyle(Theme.text)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.faint)
            }
            .padding(16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
