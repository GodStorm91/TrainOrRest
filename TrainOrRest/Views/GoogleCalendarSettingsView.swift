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
    @AppStorage(CoachLanguage.storageKey) private var languageRaw = CoachLanguage.en.rawValue

    private var language: CoachLanguage { CoachLanguage(rawValue: languageRaw) ?? .en }


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
        .environment(\.locale, language.uiLocale)
        .navigationTitle(language.integrations.googleCalendarTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingPermission) {
            GoogleCalendarPermissionView(language: language) {
                isShowingPermission = false
                connect()
            } onCancel: {
                isShowingPermission = false
            }
        }
        .confirmationDialog(language.integrations.disconnectGoogleCalendarQuestion, isPresented: $isShowingDisconnect, titleVisibility: .visible) {
            Button(language.integrations.keepCalendarAndEvents) {
                disconnect(deleteCalendar: false)
            }
            Button(language.integrations.deleteTrainingCalendar, role: .destructive) {
                deleteRemoteCalendar = true
            }
            Button(language.cancelLabel, role: .cancel) {}
        } message: {
            Text(language.integrations.disconnectMessage)
        }
        .alert(language.integrations.deleteTrainingCalendarQuestion, isPresented: $deleteRemoteCalendar) {
            Button(language.integrations.deleteCalendar, role: .destructive) {
                disconnect(deleteCalendar: true)
            }
            Button(language.cancelLabel, role: .cancel) {}
        } message: {
            Text(language.integrations.deleteTrainingCalendarMessage)
        }
        .alert(language.integrations.schedulingFromGoogleQuestion, isPresented: $isShowingSchedulingPrompt) {
            Button(language.cancelLabel, role: .cancel) {}
            Button(language.integrations.enable) {
                googleCalendar.updateSchedulingFromGoogle(enabled: true)
            }
        } message: {
            Text(language.integrations.schedulingFromGoogleMessage)
        }
        .alert(language.integrations.smartSchedulingQuestion, isPresented: $isShowingSmartSchedulingPrompt) {
            Button(language.cancelLabel, role: .cancel) {}
            Button(language.integrations.continueWithGoogle) {
                Task { await googleCalendar.enableSmartScheduling() }
            }
        } message: {
            Text(language.integrations.smartSchedulingMessage)
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
                        DatePicker(language.integrations.workoutDate, selection: $dateChoiceDraft, displayedComponents: [.date, .hourAndMinute])
                    } footer: {
                        Text(language.integrations.dateValidationFooter)
                    }
                }
                .navigationTitle(language.integrations.chooseAnotherDay)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(language.cancelLabel) { dateChoiceChangeID = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(language.integrations.apply) {
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
                SmartSchedulingPreferencesView(language: language, connection: connection)
                    .environmentObject(googleCalendar)
            }
        }
    }

    private var disconnectedSections: some View {
        Group {
            Section {
                connectionHeader(
                    title: language.integrations.connectGoogleCalendar,
                    subtitle: language.integrations.connectCalendarSubtitle,
                    symbol: "calendar.badge.plus",
                    tint: Theme.accent
                )
                Button {
                    isShowingPermission = true
                } label: {
                    Label(language.integrations.connectGoogleCalendar, systemImage: "link")
                }
                .accessibilityLabel(language.integrations.connectGoogleCalendar)
            } footer: {
                Text(language.integrations.separateCalendarFooter)
            }
        }
    }

    private var connectedSections: some View {
        Group {
            Section {
                connectionHeader(
                    title: statusTitle,
                    subtitle: connection.maskedEmail ?? language.integrations.trainingCalendarName,
                    symbol: statusSymbol,
                    tint: statusTint
                )
                if let summary = connection.lastSyncSummary, !summary.isEmpty {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(connection.connectionStatus == .partialFailure ? Theme.warn : .secondary)
                }
                if let last = connection.lastSuccessfulSyncAt {
                    LabeledContent(language.integrations.lastSuccessfulSync, value: last.formatted(.relative(presentation: .named).locale(language.uiLocale)))
                } else {
                    LabeledContent(language.integrations.lastSuccessfulSync, value: language.integrations.notYet)
                }
                LabeledContent(language.integrations.calendar, value: connection.calendarName)
                Button {
                    syncNow()
                } label: {
                    if googleCalendar.isSyncing || isWorking {
                        ProgressView()
                    } else {
                        Label(language.integrations.syncNow, systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(googleCalendar.isSyncing || isWorking)
                .accessibilityLabel(language.integrations.syncGoogleCalendarNow)
            }

            Section {
                Toggle(language.integrations.upcomingPlanWorkouts, isOn: .constant(connection.upcomingWorkoutsEnabled))
                    .disabled(true)
                Picker(language.integrations.completedActivities, selection: completedModeBinding) {
                    ForEach(GoogleCalendarCompletedActivityMode.allCases) { mode in
                        Text(language.integrations.completedActivityMode(mode)).tag(mode)
                    }
                }
                LabeledContent(language.integrations.workoutsWithoutStartTime, value: language.integrations.allDayEvent)
                LabeledContent(language.integrations.googleCalendarReminders, value: language.integrations.off)
            } header: {
                Text(language.integrations.whatSyncs)
            } footer: {
                Text(connection.allowsSchedulingFromGoogle ? language.integrations.schedulingEnabledSyncFooter : language.integrations.schedulingDisabledSyncFooter)
            }

            Section {
                Toggle(language.integrations.allowSchedulingFromGoogle, isOn: schedulingFromGoogleBinding)
                if let last = connection.lastCalendarChangeCheckAt {
                    LabeledContent(language.integrations.lastChecked, value: last.formatted(.relative(presentation: .named).locale(language.uiLocale)))
                }
            } header: {
                Text(language.integrations.schedulingFromGoogle)
            } footer: {
                Text(language.integrations.schedulingFromGoogleFooter)
            }

            smartSchedulingSection

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
                                Text(change.createdAt.formatted(.dateTime.month(.abbreviated).day().hour().minute().locale(language.uiLocale)))
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
                    Text(language.integrations.calendarChangeReview)
                }
            }

            Section {
                Button(role: .destructive) {
                    isShowingDisconnect = true
                } label: {
                    Label(language.integrations.disconnectGoogleCalendar, systemImage: "link.badge.minus")
                }
                .accessibilityLabel(language.integrations.disconnectGoogleCalendar)
            }
        }
    }

    private var reconnectSections: some View {
        Group {
            Section {
                connectionHeader(
                    title: language.integrations.googleCalendarNeedsAttention,
                    subtitle: language.integrations.reconnectSubtitle,
                    symbol: "exclamationmark.triangle",
                    tint: Theme.warn
                )
                Button {
                    isShowingPermission = true
                } label: {
                    Label(language.integrations.reconnect, systemImage: "arrow.clockwise")
                }
                Button(role: .destructive) {
                    isShowingDisconnect = true
                } label: {
                    Label(language.integrations.disconnect, systemImage: "link.badge.minus")
                }
            }
        }
    }

    private var calendarMissingSections: some View {
        Group {
            Section {
                connectionHeader(
                    title: language.integrations.trainingCalendarRemoved,
                    subtitle: language.integrations.trainingCalendarRemovedSubtitle,
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
                    Label(language.integrations.createAgain, systemImage: "calendar.badge.plus")
                }
                .disabled(isWorking)
                Button(role: .destructive) {
                    isShowingDisconnect = true
                } label: {
                    Label(language.integrations.disconnect, systemImage: "link.badge.minus")
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
            Toggle(language.integrations.useCalendarAvailability, isOn: smartSchedulingBinding)
                .accessibilityLabel(language.integrations.useGoogleCalendarAvailability)
            Text(language.integrations.availabilityCoachExplanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if connection.smartSchedulingStatus == .needsPermission {
                LabeledContent(language.integrations.smartScheduling, value: language.integrations.needsPermission)
                Button {
                    isShowingSmartSchedulingPrompt = true
                } label: {
                    Label(language.integrations.reconnectSmartScheduling, systemImage: "lock.rotation")
                }
            }

            if connection.smartSchedulingEnabled {
                if !availabilityCalendarsForConnection.isEmpty {
                    DisclosureGroup(language.integrations.availabilityCalendars) {
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
                    Label(language.integrations.schedulingPreferences, systemImage: "slider.horizontal.3")
                }
                if let last = connection.smartSchedulingLastAvailabilityRefreshAt {
                    LabeledContent(language.integrations.lastAvailabilityRefresh, value: last.formatted(.relative(presentation: .named).locale(language.uiLocale)))
                }
                if let summary = connection.smartSchedulingLastAvailabilitySummary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button {
                    Task { await googleCalendar.refreshAvailability(reason: "manual") }
                } label: {
                    Label(language.integrations.refreshAvailability, systemImage: "arrow.clockwise")
                }
                .accessibilityLabel(language.integrations.refreshCalendarAvailability)
            }
        } header: {
            Text(language.integrations.smartScheduling)
        } footer: {
            Text(language.integrations.smartSchedulingFooter)
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
        language.integrations.connectionStatusTitle(connection.connectionStatus)
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

    private enum ReviewActionKind { case addBack, swap, coach }

    @ViewBuilder
    private func reviewActions(for change: GoogleCalendarInboundChange) -> some View {
        let recommendation = recommendation(for: change)
        VStack(alignment: .leading, spacing: 8) {
            Text(recommendation.rationale)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            recommendedControl(for: change, kind: recommendation.kind)
            if change.reason != .eventDeleted {
                DisclosureGroup(language.integrations.otherOptions) {
                    VStack(alignment: .leading, spacing: 8) {
                        otherActions(for: change, recommended: recommendation.kind)
                    }
                    .padding(.top, 4)
                }
                .font(.subheadline)
            }
        }
        .controlSize(.small)
    }

    private func recommendation(for change: GoogleCalendarInboundChange) -> (kind: ReviewActionKind, rationale: String) {
        switch change.reason {
        case .eventDeleted:
            return (.addBack, language.integrations.recommendationRationale(for: .eventDeleted))
        case .targetDayConflict:
            return (.swap, language.integrations.recommendationRationale(for: .targetDayConflict))
        case .outsidePlannedWeek:
            return (.coach, language.integrations.recommendationRationale(for: .outsidePlannedWeek))
        case .planValidationFailed:
            return (.coach, language.integrations.recommendationRationale(for: .planValidationFailed))
        default:
            return (.coach, language.integrations.recommendationRationale(for: change.reason))
        }
    }

    @ViewBuilder
    private func recommendedControl(for change: GoogleCalendarInboundChange, kind: ReviewActionKind) -> some View {
        switch kind {
        case .addBack:
            Button {
                googleCalendar.addBackToGoogleCalendar(workoutID: change.localEntityID)
            } label: {
                Label(language.integrations.addBackToGoogleCalendar, systemImage: "arrow.uturn.left")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel(language.integrations.addWorkoutBackToGoogleCalendar)
        case .swap:
            Button {
                googleCalendar.swapWorkouts(for: change.uuid)
            } label: {
                Label(language.integrations.swapWorkouts, systemImage: "arrow.left.arrow.right")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel(language.integrations.swapWorkouts)
        case .coach:
            NavigationLink {
                ChatView(reviewRequest: CalendarReviewChatRequest(prompt: coachPrompt(for: change)))
            } label: {
                Label(language.integrations.reviewWithCoach, systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel(language.integrations.reviewGoogleCalendarChangeWithCoach)
        }
    }

    @ViewBuilder
    private func otherActions(for change: GoogleCalendarInboundChange, recommended: ReviewActionKind) -> some View {
        if change.reason == .targetDayConflict, recommended != .swap {
            Button(language.integrations.swapWorkouts) {
                googleCalendar.swapWorkouts(for: change.uuid)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(language.integrations.swapWorkouts)
        }
        if let workout = workouts.first(where: { $0.uuid == change.localEntityID }),
           connection.smartSchedulingEnabled,
           change.reason != .eventDeleted {
            let candidates = googleCalendar.smartSchedulingCandidates(for: workout, limit: 3)
            if !candidates.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(language.integrations.smartSchedulingFound)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(candidates) { candidate in
                        Button {
                            googleCalendar.acceptSmartSchedulingCandidate(candidate, resolvingReview: change.uuid)
                        } label: {
                            Label(
                                language.integrations.timeRange(
                                    candidate.startTime.formatted(.dateTime.month(.abbreviated).day().hour().minute().locale(language.uiLocale)),
                                    candidate.endTime.formatted(.dateTime.hour().minute().locale(language.uiLocale))
                                ),
                                systemImage: "sparkles"
                            )
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel(language.integrations.acceptSmartSchedulingAlternative)
                    }
                }
            }
        }
        if recommended != .coach,
           change.reason == .outsidePlannedWeek || change.reason == .planValidationFailed {
            NavigationLink {
                ChatView(reviewRequest: CalendarReviewChatRequest(prompt: coachPrompt(for: change)))
            } label: {
                Text(language.integrations.reviewWithCoach)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(language.integrations.reviewGoogleCalendarChangeWithCoach)
        }
        if change.reason != .eventDeleted {
            Button(language.integrations.chooseAnotherDay) {
                dateChoiceDraft = change.proposedDate ?? change.originalDate
                dateChoiceChangeID = change.uuid
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(language.integrations.chooseAnotherDay)
            Button(change.reason == .outsidePlannedWeek ? language.integrations.restoreOriginalDate : language.integrations.keepOriginalSchedule) {
                googleCalendar.restoreOriginalSchedule(for: change.uuid)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(language.integrations.restoreOriginalWorkoutDate)
        }
    }

    private func changeStatusTitle(_ status: GoogleCalendarInboundChangeStatus) -> String {
        language.integrations.changeStatusTitle(status)
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
        let proposed = change.proposedDate?.formatted(.dateTime.month(.abbreviated).day().hour().minute().locale(language.uiLocale)) ?? language.integrations.googleCalendarDate
        return language.integrations.coachPrompt(
            original: change.originalDate.formatted(.dateTime.month(.abbreviated).day().hour().minute().locale(language.uiLocale)),
            proposed: proposed
        )
    }
}

private struct GoogleCalendarPermissionView: View {
    let language: CoachLanguage
    var onContinue: () -> Void
    var onCancel: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(language.integrations.connectCalendarSubtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        permissionRow(language.integrations.createSeparateTrainingCalendar, positive: true)
                        permissionRow(language.integrations.addAndUpdateWorkouts, positive: true)
                        permissionRow(language.integrations.keepWorkoutsSynchronized, positive: true)
                        permissionRow(language.integrations.doNotReadPersonalEvents, positive: false)
                        permissionRow(language.integrations.doNotChangeOtherCalendars, positive: false)
                        permissionRow(language.integrations.doNotReschedulePlan, positive: false)
                    }
                    .padding(.vertical, 6)
                }
                Section {
                    Button {
                        dismiss()
                        onContinue()
                    } label: {
                        Label(language.integrations.continueWithGoogle, systemImage: "link")
                    }
                    Button(language.integrations.notNow, role: .cancel) {
                        dismiss()
                        onCancel()
                    }
                }
            }
            .navigationTitle(language.integrations.connectGoogleCalendar)
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
    @AppStorage(CoachLanguage.storageKey) private var languageRaw = CoachLanguage.en.rawValue

    private var language: CoachLanguage { CoachLanguage(rawValue: languageRaw) ?? .en }

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
                        Text(language.integrations.googleCalendarTitle)
                            .font(.headline)
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                if connection.connectionStatus == .disconnected {
                    Text(language.integrations.connectCalendarSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button(language.integrations.connectGoogleCalendar) { isShowingPermission = true }
                        .buttonStyle(.borderedProminent)
                } else {
                    if let summary = connection.lastSyncSummary {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent(language.integrations.status, value: pendingReviewCount > 0 ? language.integrations.changesNeedReview(pendingReviewCount) : statusValue)
                    if pendingReviewCount > 0 {
                        Button(language.integrations.reviewChanges) { isShowingSettings = true }
                            .buttonStyle(.bordered)
                            .accessibilityLabel(language.integrations.reviewGoogleCalendarChanges)
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            Button(language.integrations.syncNow) {
                                Task { await googleCalendar.reconcile(reason: "manual") }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(googleCalendar.isSyncing)
                            .accessibilityLabel(language.integrations.syncGoogleCalendarNow)
                            Button(language.integrations.manageSync) { isShowingSettings = true }
                                .buttonStyle(.bordered)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Button(language.integrations.syncNow) {
                                Task { await googleCalendar.reconcile(reason: "manual") }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(googleCalendar.isSyncing)
                            .accessibilityLabel(language.integrations.syncGoogleCalendarNow)
                            Button(language.integrations.manageSync) { isShowingSettings = true }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .padding(20)
            .torReadableColumn()
            .navigationDestination(isPresented: $isShowingSettings) {
                GoogleCalendarSettingsView()
            }
            .sheet(isPresented: $isShowingPermission) {
                GoogleCalendarPermissionView(language: language) {
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
        let lastSynced = connection.lastSuccessfulSyncAt?.formatted(.relative(presentation: .named).locale(language.uiLocale))
        return language.integrations.statusSheetSubtitle(connection.connectionStatus, lastSynced: lastSynced)
    }

    private var statusValue: String {
        language.integrations.statusValue(connection.connectionStatus)
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
    let language: CoachLanguage
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var googleCalendar: GoogleCalendarSyncService
    @Bindable var connection: GoogleCalendarConnection

    var body: some View {
        Form {
            Section {
                Picker(language.integrations.preferredTrainingTime, selection: preferredTimeBinding) {
                    ForEach(PreferredTrainingTime.allCases) { option in
                        Text(language.integrations.preferredTrainingTimeOption(option)).tag(option)
                    }
                }
                Stepper(language.integrations.earliestStart(timeText(connection.smartSchedulingEarliestStartOrDefault)), value: earliestBinding, in: 0...(22 * 60), step: 15)
                Stepper(language.integrations.latestFinish(timeText(connection.smartSchedulingLatestFinishOrDefault)), value: latestBinding, in: (4 * 60)...(24 * 60), step: 15)
                Stepper(language.integrations.bufferBefore(connection.smartSchedulingBufferBeforeOrDefault), value: bufferBeforeBinding, in: 0...60, step: 5)
                Stepper(language.integrations.bufferAfter(connection.smartSchedulingBufferAfterOrDefault), value: bufferAfterBinding, in: 0...60, step: 5)
            } footer: {
                Text(language.integrations.schedulingPreferencesFooter)
            }
        }
        .navigationTitle(language.integrations.schedulingPreferences)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(language.doneLabel) { dismiss() }
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
