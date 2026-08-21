import SwiftData
import SwiftUI

struct GoogleCalendarSettingsView: View {
    @EnvironmentObject private var googleCalendar: GoogleCalendarSyncService
    @Query private var connections: [GoogleCalendarConnection]
    @Query(sort: \GoogleCalendarInboundChange.createdAt, order: .reverse) private var calendarChanges: [GoogleCalendarInboundChange]
    @Query(sort: \GoogleAvailabilityCalendar.displayName) private var availabilityCalendars: [GoogleAvailabilityCalendar]
    @Query(sort: \PlannedWorkout.date) private var workouts: [PlannedWorkout]
    @State private var isShowingPermission = false
    @State private var isShowingDisconnect = false
    @State private var deleteRemoteCalendar = false
    @State private var isShowingSchedulingPrompt = false
    @State private var isShowingSmartSchedulingPrompt = false
    @State private var isShowingSchedulingPreferences = false
    @State private var isWorking = false
    @State private var dateChoiceChangeID: UUID?
    @State private var dateChoiceDraft = Date()
    @State private var didSyncOnOpen = false

    private var connection: GoogleCalendarConnection {
        connections.first ?? googleCalendar.connection()
    }

    var body: some View {
        Form {
            switch connection.connectionStatus {
            case .disconnected:
                disconnectedSections
            case .connecting, .initialSync, .connected, .syncing, .partialFailure, .offlineQueued:
                connectedSections
            case .needsReconnect:
                reconnectSections
            case .calendarMissing:
                calendarMissingSections
            }
        }
        .navigationTitle("Google Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingPermission) {
            GoogleCalendarPermissionView {
                isShowingPermission = false
                connect()
            } onCancel: {
                isShowingPermission = false
            }
        }
        .confirmationDialog("Disconnect Google Calendar?", isPresented: $isShowingDisconnect, titleVisibility: .visible) {
            Button("Keep calendar and events") {
                disconnect(deleteCalendar: false)
            }
            Button("Delete RestOrTrain Training calendar", role: .destructive) {
                deleteRemoteCalendar = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("RestOrTrain will stop updating your Google Calendar.")
        }
        .alert("Delete RestOrTrain Training calendar?", isPresented: $deleteRemoteCalendar) {
            Button("Delete calendar", role: .destructive) {
                disconnect(deleteCalendar: true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only the RestOrTrain-created secondary calendar is removed. Your workouts and personal calendars stay untouched.")
        }
        .alert("Allow scheduling from Google Calendar?", isPresented: $isShowingSchedulingPrompt) {
            Button("Cancel", role: .cancel) {}
            Button("Enable") {
                googleCalendar.updateSchedulingFromGoogle(enabled: true)
            }
        } message: {
            Text("You’ll be able to change when a RestOrTrain workout happens directly from Google Calendar.\n\nGoogle Calendar can change:\n✓ Workout date\n✓ Start time\n\nGoogle Calendar cannot change:\n✕ Workout type\n✕ Distance\n✕ Pace or intensity\n✕ Workout structure\n✕ Your training goal\n\nMoves that could disrupt your training plan will require review in RestOrTrain.")
        }
        .alert("Use Google Calendar availability?", isPresented: $isShowingSmartSchedulingPrompt) {
            Button("Cancel", role: .cancel) {}
            Button("Continue with Google") {
                Task { await googleCalendar.enableSmartScheduling() }
            }
        } message: {
            Text("RestOrTrain can use your busy and available time to suggest better workout times.\n\nRestOrTrain will be able to see:\n✓ When you are busy\n✓ When you are available\n\nRestOrTrain will not read:\n✕ Event names\n✕ Event descriptions\n✕ Attendees\n✕ Meeting links\n✕ Event notes\n\nYour training plan and workout details remain managed by RestOrTrain.")
        }
        .task {
            guard !didSyncOnOpen,
                  connection.connectionStatus == .connected,
                  connection.allowsSchedulingFromGoogle else { return }
            didSyncOnOpen = true
            await googleCalendar.reconcile(reason: "openGoogleCalendarSettings")
        }
        .sheet(isPresented: Binding(
            get: { dateChoiceChangeID != nil },
            set: { if !$0 { dateChoiceChangeID = nil } }
        )) {
            NavigationStack {
                Form {
                    Section {
                        DatePicker("Workout date", selection: $dateChoiceDraft, displayedComponents: [.date, .hourAndMinute])
                    } footer: {
                        Text("RestOrTrain will validate the chosen date before applying it.")
                    }
                }
                .navigationTitle("Choose another day")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dateChoiceChangeID = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Apply") {
                            if let dateChoiceChangeID {
                                googleCalendar.moveReviewedWorkout(for: dateChoiceChangeID, to: dateChoiceDraft)
                            }
                            dateChoiceChangeID = nil
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $isShowingSchedulingPreferences) {
            NavigationStack {
                SmartSchedulingPreferencesView(connection: connection)
                    .environmentObject(googleCalendar)
            }
        }
    }

    private var disconnectedSections: some View {
        Group {
            Section {
                connectionHeader(
                    title: "Connect Google Calendar",
                    subtitle: "View RestOrTrain workouts alongside your work and personal schedule.",
                    symbol: "calendar.badge.plus",
                    tint: Theme.accent
                )
                Button {
                    isShowingPermission = true
                } label: {
                    Label("Connect Google Calendar", systemImage: "link")
                }
                .accessibilityLabel("Connect Google Calendar")
            } footer: {
                Text("RestOrTrain creates a separate training calendar and does not read personal events.")
            }
        }
    }

    private var connectedSections: some View {
        Group {
            Section {
                connectionHeader(
                    title: statusTitle,
                    subtitle: connection.maskedEmail ?? "RestOrTrain Training",
                    symbol: statusSymbol,
                    tint: statusTint
                )
                if let last = connection.lastSuccessfulSyncAt {
                    LabeledContent("Last successful sync", value: last.formatted(date: .abbreviated, time: .shortened))
                } else {
                    LabeledContent("Last successful sync", value: "Not yet")
                }
                LabeledContent("Calendar", value: connection.calendarName)
                Button {
                    syncNow()
                } label: {
                    if googleCalendar.isSyncing || isWorking {
                        ProgressView()
                    } else {
                        Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(googleCalendar.isSyncing || isWorking)
                .accessibilityLabel("Sync Google Calendar now")
            }

            Section {
                Toggle("Upcoming plan workouts", isOn: .constant(connection.upcomingWorkoutsEnabled))
                    .disabled(true)
                Picker("Completed activities", selection: completedModeBinding) {
                    ForEach(GoogleCalendarCompletedActivityMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                LabeledContent("Workouts without a start time", value: "All-day event")
                LabeledContent("Google Calendar reminders", value: "Off")
            } header: {
                Text("What syncs")
            } footer: {
                Text(connection.allowsSchedulingFromGoogle ? "Google Calendar can schedule the workout. RestOrTrain defines the workout." : "RestOrTrain is the source of truth. Changes made in Google Calendar do not update your training plan and may be overwritten during sync.")
            }

            Section {
                Toggle("Allow scheduling from Google Calendar", isOn: schedulingFromGoogleBinding)
                if let last = connection.lastCalendarChangeCheckAt {
                    LabeledContent("Last checked", value: last.formatted(date: .abbreviated, time: .shortened))
                }
            } header: {
                Text("Scheduling from Google")
            } footer: {
                Text("When enabled, changing the date or start time of a RestOrTrain workout in Google Calendar can update your training schedule.\n\nWorkout type, distance, pace, and structure remain managed by RestOrTrain.")
            }

            smartSchedulingSection

            if let summary = connection.lastSyncSummary {
                Section {
                    Text(summary)
                        .foregroundStyle(connection.connectionStatus == .partialFailure ? Theme.warn : Theme.dim)
                }
            }

            let recentChanges = calendarChanges.filter { $0.connectionID == connection.uuid }.prefix(5)
            if !recentChanges.isEmpty || connection.lastCalendarChangeSummary != nil {
                Section {
                    if let summary = connection.lastCalendarChangeSummary {
                        Text(summary)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(recentChanges), id: \.uuid) { change in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Label(changeStatusTitle(change.status), systemImage: changeStatusSymbol(change.status))
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(change.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(change.message)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if change.status == .pendingReview {
                                reviewActions(for: change)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Calendar change review")
                }
            }

            Section {
                Button(role: .destructive) {
                    isShowingDisconnect = true
                } label: {
                    Label("Disconnect Google Calendar", systemImage: "link.badge.minus")
                }
                .accessibilityLabel("Disconnect Google Calendar")
            }
        }
    }

    private var reconnectSections: some View {
        Group {
            Section {
                connectionHeader(
                    title: "Google Calendar needs attention",
                    subtitle: "RestOrTrain no longer has permission to update your training calendar.",
                    symbol: "exclamationmark.triangle",
                    tint: Theme.warn
                )
                Button {
                    isShowingPermission = true
                } label: {
                    Label("Reconnect", systemImage: "arrow.clockwise")
                }
                Button(role: .destructive) {
                    isShowingDisconnect = true
                } label: {
                    Label("Disconnect", systemImage: "link.badge.minus")
                }
            }
        }
    }

    private var calendarMissingSections: some View {
        Group {
            Section {
                connectionHeader(
                    title: "Training calendar was removed",
                    subtitle: "The RestOrTrain Training calendar can no longer be found in Google Calendar.",
                    symbol: "calendar.badge.exclamationmark",
                    tint: Theme.warn
                )
                Button {
                    isWorking = true
                    Task {
                        await googleCalendar.createCalendarAgain()
                        await MainActor.run { isWorking = false }
                    }
                } label: {
                    Label("Create again", systemImage: "calendar.badge.plus")
                }
                .disabled(isWorking)
                Button(role: .destructive) {
                    isShowingDisconnect = true
                } label: {
                    Label("Disconnect", systemImage: "link.badge.minus")
                }
            }
        }
    }

    private func connectionHeader(title: String, subtitle: String, symbol: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(minHeight: 56)
        .accessibilityElement(children: .combine)
    }

    private var completedModeBinding: Binding<GoogleCalendarCompletedActivityMode> {
        Binding(
            get: { connection.completedActivityMode },
            set: { googleCalendar.updatePreferences(completedMode: $0) }
        )
    }

    private var smartSchedulingSection: some View {
        Section {
            Toggle("Use calendar availability", isOn: smartSchedulingBinding)
                .accessibilityLabel("Use Google Calendar availability")
            Text("Let Coach use busy and available time blocks to suggest better workout times. RestOrTrain does not read event names or details.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if connection.smartSchedulingStatus == .needsPermission {
                LabeledContent("Smart Scheduling", value: "Needs permission")
                Button {
                    isShowingSmartSchedulingPrompt = true
                } label: {
                    Label("Reconnect Smart Scheduling", systemImage: "lock.rotation")
                }
            }

            if connection.smartSchedulingEnabled {
                if !availabilityCalendarsForConnection.isEmpty {
                    DisclosureGroup("Availability calendars") {
                        ForEach(availabilityCalendarsForConnection, id: \.uuid) { calendar in
                            Toggle(isOn: Binding(
                                get: { calendar.selectedForAvailability },
                                set: { googleCalendar.updateSmartSchedulingCalendar(calendar.googleCalendarID, selected: $0) }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(calendar.displayName)
                                    if let reason = calendar.excludedByDefaultReason {
                                        Text(reason)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                Button {
                    isShowingSchedulingPreferences = true
                } label: {
                    Label("Scheduling preferences", systemImage: "slider.horizontal.3")
                }
                if let last = connection.smartSchedulingLastAvailabilityRefreshAt {
                    LabeledContent("Last availability refresh", value: last.formatted(date: .abbreviated, time: .shortened))
                }
                if let summary = connection.smartSchedulingLastAvailabilitySummary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button {
                    Task { await googleCalendar.refreshAvailability(reason: "manual") }
                } label: {
                    Label("Refresh availability", systemImage: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh calendar availability")
            }
        } header: {
            Text("Smart Scheduling")
        } footer: {
            Text("RestOrTrain only uses busy/free time to help schedule workouts. Event names and details are not used.")
        }
    }

    private var availabilityCalendarsForConnection: [GoogleAvailabilityCalendar] {
        availabilityCalendars.filter { $0.connectionID == connection.uuid }
    }

    private var smartSchedulingBinding: Binding<Bool> {
        Binding(
            get: { connection.smartSchedulingEnabled },
            set: { enabled in
                if enabled {
                    isShowingSmartSchedulingPrompt = true
                } else {
                    googleCalendar.disableSmartScheduling()
                }
            }
        )
    }

    private var schedulingFromGoogleBinding: Binding<Bool> {
        Binding(
            get: { connection.allowsSchedulingFromGoogle },
            set: { enabled in
                if enabled {
                    isShowingSchedulingPrompt = true
                } else {
                    googleCalendar.updateSchedulingFromGoogle(enabled: false)
                }
            }
        )
    }

    private var statusTitle: String {
        switch connection.connectionStatus {
        case .initialSync: "Initial sync"
        case .syncing: "Syncing"
        case .partialFailure: "Calendar sync incomplete"
        case .offlineQueued: "Waiting for connection"
        default: "Google Calendar Connected"
        }
    }

    private var statusSymbol: String {
        switch connection.connectionStatus {
        case .partialFailure, .offlineQueued: "exclamationmark.triangle"
        case .syncing, .initialSync: "arrow.triangle.2.circlepath"
        default: "checkmark.circle.fill"
        }
    }

    private var statusTint: Color {
        switch connection.connectionStatus {
        case .partialFailure, .offlineQueued: Theme.warn
        case .syncing, .initialSync: Theme.accent
        default: Theme.good
        }
    }

    private func connect() {
        isWorking = true
        Task {
            await googleCalendar.connect()
            await MainActor.run { isWorking = false }
        }
    }

    private func syncNow() {
        isWorking = true
        Task {
            await googleCalendar.reconcile(reason: "manual")
            await MainActor.run { isWorking = false }
        }
    }

    private func checkCalendarChanges() {
        isWorking = true
        Task {
            await googleCalendar.reconcile(reason: "manual")
            await MainActor.run { isWorking = false }
        }
    }

    private func disconnect(deleteCalendar: Bool) {
        isWorking = true
        Task {
            await googleCalendar.disconnect(deleteCalendar: deleteCalendar)
            await MainActor.run { isWorking = false }
        }
    }

    @ViewBuilder
    private func reviewActions(for change: GoogleCalendarInboundChange) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if change.reason == .eventDeleted {
                Button("Add back to Google Calendar") {
                    googleCalendar.addBackToGoogleCalendar(workoutID: change.localEntityID)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Add workout back to Google Calendar")
            }
            if change.reason == .targetDayConflict {
                Button("Swap workouts") {
                    googleCalendar.swapWorkouts(for: change.uuid)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Swap workouts")
            }
            if let workout = workouts.first(where: { $0.uuid == change.localEntityID }),
               connection.smartSchedulingEnabled,
               change.reason != .eventDeleted {
                let candidates = googleCalendar.smartSchedulingCandidates(for: workout, limit: 3)
                if !candidates.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Smart Scheduling found")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(candidates) { candidate in
                            Button {
                                googleCalendar.acceptSmartSchedulingCandidate(candidate, resolvingReview: change.uuid)
                            } label: {
                                Label(
                                    "\(candidate.startTime.formatted(date: .abbreviated, time: .shortened))-\(candidate.endTime.formatted(date: .omitted, time: .shortened))",
                                    systemImage: "sparkles"
                                )
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Accept Smart Scheduling alternative")
                        }
                    }
                }
            }
            if change.reason != .eventDeleted {
                Button("Choose another day") {
                    dateChoiceDraft = change.proposedDate ?? change.originalDate
                    dateChoiceChangeID = change.uuid
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Choose another day")
            }
            if change.reason == .outsidePlannedWeek || change.reason == .planValidationFailed {
                NavigationLink {
                    ChatView(reviewRequest: CalendarReviewChatRequest(prompt: coachPrompt(for: change)))
                } label: {
                    Text("Review with Coach")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Review Google Calendar change with Coach")
            }
            if change.reason != .eventDeleted {
                Button(change.reason == .outsidePlannedWeek ? "Restore original date" : "Keep original schedule") {
                    googleCalendar.restoreOriginalSchedule(for: change.uuid)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Restore original workout date")
            }
        }
        .controlSize(.small)
    }

    private func changeStatusTitle(_ status: GoogleCalendarInboundChangeStatus) -> String {
        switch status {
        case .pendingReview: "Needs review"
        case .applied: "Applied"
        case .rejected: "Rejected"
        case .restored: "Restored"
        }
    }

    private func changeStatusSymbol(_ status: GoogleCalendarInboundChangeStatus) -> String {
        switch status {
        case .pendingReview: "exclamationmark.triangle"
        case .applied: "checkmark.circle"
        case .rejected: "xmark.circle"
        case .restored: "arrow.counterclockwise.circle"
        }
    }

    private func coachPrompt(for change: GoogleCalendarInboundChange) -> String {
        let proposed = change.proposedDate?.formatted(date: .abbreviated, time: .shortened) ?? "the Google Calendar date"
        return "Review this Google Calendar schedule change before changing the training plan. Original workout date: \(change.originalDate.formatted(date: .abbreviated, time: .shortened)). Requested Google Calendar date: \(proposed). Consider the current plan week, target week, nearby workouts, phase, load, recovery, and whether to accept, swap, adjust the week, or keep the original schedule."
    }
}

private struct GoogleCalendarPermissionView: View {
    var onContinue: () -> Void
    var onCancel: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("See your RestOrTrain workouts alongside your work and personal schedule.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        permissionRow("Create a separate calendar named “RestOrTrain Training”", positive: true)
                        permissionRow("Add and update workouts in that calendar", positive: true)
                        permissionRow("Keep those workouts synchronized when your plan changes", positive: true)
                        permissionRow("Read events from your personal calendars", positive: false)
                        permissionRow("Change your other calendars", positive: false)
                        permissionRow("Reschedule your RestOrTrain plan from Google Calendar", positive: false)
                    }
                    .padding(.vertical, 6)
                }
                Section {
                    Button {
                        dismiss()
                        onContinue()
                    } label: {
                        Label("Continue with Google", systemImage: "link")
                    }
                    Button("Not now", role: .cancel) {
                        dismiss()
                        onCancel()
                    }
                }
            }
            .navigationTitle("Connect Google Calendar")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func permissionRow(_ text: String, positive: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: positive ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(positive ? Theme.good : Theme.faint)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: 44, alignment: .leading)
    }
}

struct GoogleCalendarStatusSheet: View {
    @EnvironmentObject private var googleCalendar: GoogleCalendarSyncService
    @Query private var connections: [GoogleCalendarConnection]
    @Query(sort: \GoogleCalendarInboundChange.createdAt, order: .reverse) private var calendarChanges: [GoogleCalendarInboundChange]
    @State private var isShowingSettings = false
    @State private var isShowingPermission = false

    private var connection: GoogleCalendarConnection {
        connections.first ?? googleCalendar.connection()
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(tint)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Google Calendar")
                            .font(.headline)
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                if connection.connectionStatus == .disconnected {
                    Text("View your RestOrTrain workouts alongside your work and personal schedule.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Connect Google Calendar") { isShowingPermission = true }
                        .buttonStyle(.borderedProminent)
                } else {
                    if let summary = connection.lastSyncSummary {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Status", value: pendingReviewCount > 0 ? "\(pendingReviewCount) changes need review" : statusValue)
                    if pendingReviewCount > 0 {
                        Button("Review changes") { isShowingSettings = true }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Review Google Calendar changes")
                    }
                    HStack {
                        Button("Sync now") {
                            Task { await googleCalendar.reconcile(reason: "manual") }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(googleCalendar.isSyncing)
                        .accessibilityLabel("Sync Google Calendar now")
                        Button("Manage sync") { isShowingSettings = true }
                            .buttonStyle(.bordered)
                    }
                }
            }
            .padding(20)
            .navigationDestination(isPresented: $isShowingSettings) {
                GoogleCalendarSettingsView()
            }
            .sheet(isPresented: $isShowingPermission) {
                GoogleCalendarPermissionView {
                    isShowingPermission = false
                    Task { await googleCalendar.connect() }
                } onCancel: {
                    isShowingPermission = false
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var subtitle: String {
        switch connection.connectionStatus {
        case .disconnected: return "Not connected"
        case .syncing, .initialSync: return "Syncing"
        case .needsReconnect: return "Reconnect required"
        case .offlineQueued: return "Waiting for connection"
        case .partialFailure: return "Needs attention"
        default:
            if let last = connection.lastSuccessfulSyncAt {
                return "Last synced \(last.formatted(date: .omitted, time: .shortened))"
            }
            return "Connected"
        }
    }

    private var statusValue: String {
        switch connection.connectionStatus {
        case .connected: "Up to date"
        case .syncing, .initialSync: "Syncing"
        case .needsReconnect: "Reconnect required"
        case .offlineQueued: "Waiting for connection"
        case .partialFailure, .calendarMissing: "Sync incomplete"
        case .disconnected, .connecting: "Not connected"
        }
    }

    private var pendingReviewCount: Int {
        calendarChanges.filter {
            $0.connectionID == connection.uuid && $0.status == .pendingReview
        }.count
    }

    private var icon: String {
        switch connection.connectionStatus {
        case .disconnected: "calendar.badge.plus"
        case .needsReconnect, .partialFailure, .offlineQueued, .calendarMissing: "exclamationmark.triangle"
        case .syncing, .initialSync: "arrow.triangle.2.circlepath"
        default: "calendar.badge.checkmark"
        }
    }

    private var tint: Color {
        switch connection.connectionStatus {
        case .needsReconnect, .partialFailure, .offlineQueued, .calendarMissing: Theme.warn
        case .connected: Theme.good
        default: Theme.accent
        }
    }
}

private struct SmartSchedulingPreferencesView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var googleCalendar: GoogleCalendarSyncService
    @Bindable var connection: GoogleCalendarConnection

    var body: some View {
        Form {
            Section {
                Picker("Preferred training time", selection: preferredTimeBinding) {
                    ForEach(PreferredTrainingTime.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                Stepper("Earliest start \(timeText(connection.smartSchedulingEarliestStartOrDefault))", value: earliestBinding, in: 0...(22 * 60), step: 15)
                Stepper("Latest finish \(timeText(connection.smartSchedulingLatestFinishOrDefault))", value: latestBinding, in: (4 * 60)...(24 * 60), step: 15)
                Stepper("Buffer before \(connection.smartSchedulingBufferBeforeOrDefault) min", value: bufferBeforeBinding, in: 0...60, step: 5)
                Stepper("Buffer after \(connection.smartSchedulingBufferAfterOrDefault) min", value: bufferAfterBinding, in: 0...60, step: 5)
            } footer: {
                Text("These preferences rank valid slots. They never override recovery or plan-safety validation.")
            }
        }
        .navigationTitle("Scheduling preferences")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    private var preferredTimeBinding: Binding<PreferredTrainingTime> {
        Binding(
            get: { connection.preferredTrainingTime },
            set: { update(preferredTime: $0) }
        )
    }

    private var earliestBinding: Binding<Int> {
        Binding(
            get: { connection.smartSchedulingEarliestStartOrDefault },
            set: { update(earliest: min($0, connection.smartSchedulingLatestFinishOrDefault - 30)) }
        )
    }

    private var latestBinding: Binding<Int> {
        Binding(
            get: { connection.smartSchedulingLatestFinishOrDefault },
            set: { update(latest: max($0, connection.smartSchedulingEarliestStartOrDefault + 30)) }
        )
    }

    private var bufferBeforeBinding: Binding<Int> {
        Binding(
            get: { connection.smartSchedulingBufferBeforeOrDefault },
            set: { update(bufferBefore: $0) }
        )
    }

    private var bufferAfterBinding: Binding<Int> {
        Binding(
            get: { connection.smartSchedulingBufferAfterOrDefault },
            set: { update(bufferAfter: $0) }
        )
    }

    private func update(
        preferredTime: PreferredTrainingTime? = nil,
        earliest: Int? = nil,
        latest: Int? = nil,
        bufferBefore: Int? = nil,
        bufferAfter: Int? = nil
    ) {
        googleCalendar.updateSmartSchedulingPreferences(
            preferredTime: preferredTime ?? connection.preferredTrainingTime,
            earliestStartMinutes: earliest ?? connection.smartSchedulingEarliestStartOrDefault,
            latestFinishMinutes: latest ?? connection.smartSchedulingLatestFinishOrDefault,
            bufferBeforeMinutes: bufferBefore ?? connection.smartSchedulingBufferBeforeOrDefault,
            bufferAfterMinutes: bufferAfter ?? connection.smartSchedulingBufferAfterOrDefault
        )
    }

    private func timeText(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}
