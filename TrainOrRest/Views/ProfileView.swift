import SwiftData
import SwiftUI

/// Profile tab: active goal summary plus entries to edit the goal and open
/// settings (API key, etc.). Wraps the existing GoalEntryView / SettingsView.
struct ProfileView: View {
    @Query private var goals: [Goal]
    @EnvironmentObject private var pushService: WorkoutPushService
    @AppStorage(WorkoutPushSettings.enabledKey) private var watchPushEnabled = false
    @AppStorage(WorkoutPushSettings.athleteIDKey) private var athleteID = ""
    @State private var showGoalEntry = false
    @State private var intervalsAPIKey = ""
    @State private var pushSettingsStatus: String?

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

                watchPushSection
                appearanceSection
                navRow("Run history", systemImage: "figure.run") { ActivityListView() }
                navRow("Settings", systemImage: "gearshape") { SettingsView() }
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 24)
        }
        .background(Theme.bg)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 82)
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $showGoalEntry) { GoalEntryView() }
        .task { intervalsAPIKey = (try? KeychainStore.load(account: KeychainStore.intervalsICUAccount)) ?? "" }
    }

    private var appearanceSection: some View {
        TorCard {
            AppAppearanceSelector()
        }
    }

    private var watchPushSection: some View {
        TorCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "applewatch.radiowaves.left.and.right")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        TorEyebrow("Watch push")
                        Text("intervals.icu")
                            .font(.torHeading(18, .bold))
                            .foregroundStyle(Theme.text)
                    }
                    Spacer()
                    Toggle("", isOn: $watchPushEnabled)
                        .labelsHidden()
                }

                VStack(spacing: 10) {
                    TextField("Athlete ID", text: $athleteID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(Theme.card2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.border))

                    SecureField("intervals.icu API key", text: $intervalsAPIKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(Theme.card2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.border))
                }
                .font(.system(size: 14))

                HStack(alignment: .center, spacing: 10) {
                    Button {
                        savePushSettings()
                    } label: {
                        Label("Save", systemImage: "checkmark")
                            .font(.torHeading(14, .bold))
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSavePushSettings)

                    if pushService.isPushing {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Spacer()
                }

                Text(pushStatusText)
                    .font(.caption)
                    .foregroundStyle(pushStatusColor)

                Text("Enable Garmin upload in intervals.icu before expecting watch delivery.")
                    .font(.caption2)
                    .foregroundStyle(Theme.faint)
            }
        }
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

    private var pushStatusText: String {
        if let pushSettingsStatus {
            return pushSettingsStatus
        }
        if let error = pushService.lastPushError {
            return "Last push failed: \(error)"
        }
        if watchPushEnabled, athleteID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Add your intervals.icu athlete ID."
        }
        if watchPushEnabled, intervalsAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Add your intervals.icu API key."
        }
        if let lastPushAt = pushService.lastPushAt {
            return "Last push \(lastPushAt.formatted(date: .abbreviated, time: .shortened))"
        }
        return watchPushEnabled ? "Ready to push next planned workout window." : "Disabled."
    }

    private var pushStatusColor: Color {
        if pushSettingsStatus?.hasPrefix("Could not") == true {
            return Theme.bad
        }
        if pushService.lastPushError != nil {
            return Theme.bad
        }
        if watchPushEnabled {
            return Theme.dim
        }
        return Theme.faint
    }

    private var canSavePushSettings: Bool {
        !athleteID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !intervalsAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func savePushSettings() {
        let trimmed = intervalsAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try KeychainStore.save(trimmed, account: KeychainStore.intervalsICUAccount)
            pushSettingsStatus = "Saved."
            Task {
                await pushService.reconcile()
                await MainActor.run { pushSettingsStatus = nil }
            }
        } catch {
            pushSettingsStatus = "Could not save intervals.icu key."
        }
    }
}
