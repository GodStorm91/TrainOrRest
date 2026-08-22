import SwiftData
import SwiftUI

struct WorkoutDetailView: View {
    @Bindable var workout: PlannedWorkout
    @Query private var activities: [CompletedActivity]
    @Query private var googleLinks: [GoogleCalendarEventLink]
    @Query private var googleConnections: [GoogleCalendarConnection]
    @EnvironmentObject private var googleCalendar: GoogleCalendarSyncService
    @State private var smartCandidates: [SchedulingCandidate] = []
    @State private var smartSchedulingMessage: String?
    @State private var isFindingSmartTime = false

    var body: some View {
        List {
            Section {
                LabeledContent("Date", value: workout.date.formatted(date: .complete, time: .omitted))
                LabeledContent("Workout", value: workout.kind?.displayName ?? workout.kindRaw)
                LabeledContent("Distance", value: Formatters.kilometers(workout.distanceKm * 1000))
                if let band = workout.paceBand {
                    LabeledContent("Pace", value: Formatters.paceBand(band))
                }
                Text(workout.details)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let scheduleUpdatedAt = workout.scheduleUpdatedAt, workout.scheduleUpdatedFrom == "googleCalendar" {
                Section("Schedule history") {
                    LabeledContent("Scheduled from", value: "Google Calendar")
                    LabeledContent("Updated", value: scheduleUpdatedAt.formatted(date: .abbreviated, time: .shortened))
                }
            }

            if isNotVisibleInGoogleCalendar {
                Section {
                    Label("Not shown in Google Calendar", systemImage: "calendar.badge.exclamationmark")
                        .foregroundStyle(Theme.warn)
                    Text("This workout still exists in your RestOrTrain plan.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        googleCalendar.addBackToGoogleCalendar(workoutID: workout.uuid)
                    } label: {
                        Label("Add back to Google Calendar", systemImage: "calendar.badge.plus")
                    }
                }
            }

            if smartSchedulingEnabled {
                Section("Smart Scheduling") {
                    Toggle("Keep this workout fixed", isOn: Binding(
                        get: { workout.isScheduleLocked },
                        set: { workout.scheduleLock = $0 }
                    ))
                    .accessibilityLabel("Keep workout fixed")
                    if smartCandidates.isEmpty {
                        Button {
                            Task { await refreshSmartCandidates() }
                        } label: {
                            Label(isFindingSmartTime ? "Finding a time" : "Find a time", systemImage: "sparkles")
                        }
                        .accessibilityLabel("Find a time")
                        .disabled(isFindingSmartTime)
                    } else {
                        ForEach(smartCandidates) { candidate in
                            VStack(alignment: .leading, spacing: 6) {
                                Label(candidate.id == smartCandidates.first?.id ? "Best scheduling option" : "Scheduling option", systemImage: "clock")
                                    .font(.subheadline.weight(.semibold))
                                Text("\(candidate.startTime.formatted(date: .abbreviated, time: .shortened))-\(candidate.endTime.formatted(date: .omitted, time: .shortened))")
                                    .font(.headline)
                                ForEach(candidate.reasons.prefix(3), id: \.self) { reason in
                                    Text("• \(reason)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Button {
                                    googleCalendar.acceptSmartSchedulingCandidate(candidate)
                                    smartSchedulingMessage = "\(workout.kind?.displayName ?? "Workout") scheduled for \(candidate.startTime.formatted(date: .omitted, time: .shortened))"
                                    smartCandidates = []
                                } label: {
                                    Label("Use \(candidate.startTime.formatted(date: .omitted, time: .shortened))", systemImage: "checkmark.circle")
                                }
                                .accessibilityLabel("Schedule \(workout.kind?.displayName ?? "workout") at \(candidate.startTime.formatted(date: .omitted, time: .shortened))")
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    if let smartSchedulingMessage {
                        Text(smartSchedulingMessage)
                            .font(.caption)
                            .foregroundStyle(Theme.good)
                    }
                }
            }

            if let matched = matchedActivity {
                Section("Completed Run") {
                    NavigationLink {
                        ActivityDetailView(activity: matched)
                    } label: {
                        ActivityRow(activity: matched)
                    }
                }
            }

            Section("Status") {
                statusButtons
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle(workout.date.formatted(.dateTime.month(.abbreviated).day()))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if smartSchedulingEnabled && !isTimed(workout.date) {
                await refreshSmartCandidates()
            }
        }
    }

    private var matchedActivity: CompletedActivity? {
        guard let uuid = workout.matchedActivityUUID else { return nil }
        return activities.first { $0.hkUUID == uuid }
    }

    private var isNotVisibleInGoogleCalendar: Bool {
        googleLinks.contains {
            $0.localEntityID == workout.uuid && $0.syncState == .notVisibleInGoogleCalendar
        }
    }

    private var smartSchedulingEnabled: Bool {
        googleConnections.first?.smartSchedulingEnabled == true
    }

    private func refreshSmartCandidates() async {
        guard !isFindingSmartTime else { return }
        isFindingSmartTime = true
        defer { isFindingSmartTime = false }
        smartCandidates = await googleCalendar.refreshedSmartSchedulingCandidates(for: workout)
        if smartCandidates.isEmpty {
            smartSchedulingMessage = "No safe available slot found."
        } else {
            smartSchedulingMessage = nil
        }
    }

    private func isTimed(_ date: Date) -> Bool {
        !Calendar.current.isDate(date, equalTo: Calendar.current.startOfDay(for: date), toGranularity: .minute)
    }

    private var statusButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                statusButton("Done", status: .done, tint: Theme.good)
                statusButton("Skipped", status: .skipped, tint: Theme.warn)
                statusButton("Planned", status: .planned, tint: Theme.accent)
            }
            .buttonStyle(.bordered)

            Text(statusHelpText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func statusButton(_ label: String, status: WorkoutStatus, tint: Color) -> some View {
        Button(label) {
            workout.status = status
            // Resetting to planned withdraws the manual decision, so auto-
            // matching may apply again; done/skip stays user-owned.
            workout.manuallyOverridden = status != .planned
            if status != .done {
                workout.matchedActivityUUID = nil
            }
            NotificationCenter.default.post(name: .planDidChange, object: nil)
        }
        .tint(tint)
        .disabled(workout.status == status)
        .frame(maxWidth: .infinity)
    }

    private var statusHelpText: String {
        switch workout.status {
        case .done:
            "Done is a manual completion and stays linked to this workout."
        case .skipped:
            "Skipped is a manual decision; the planner will not auto-match this workout."
        case .planned:
            "Planned clears the manual decision so future sync matching can apply again."
        }
    }
}
