import BackgroundTasks
import SwiftData
import SwiftUI

@main
struct TrainOrRestApp: App {
    static let refreshTaskIdentifier = "com.khanhnguyen.TrainOrRest.refresh"
    /// Morning refresh aims to run after Garmin's overnight sync lands.
    static let refreshHour = 5

    private let container: ModelContainer
    @StateObject private var engine: SyncEngine
    @StateObject private var pushService: WorkoutPushService
    @StateObject private var googleCalendarService: GoogleCalendarSyncService
    @StateObject private var chatStore: CoachChatStore
    @StateObject private var chatSession: CoachChatSessionState
    @StateObject private var adaptiveReviewCoordinator: AdaptivePlanReviewCoordinator
    @StateObject private var runSchedule: RunScheduleController
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(
                for: CompletedActivity.self, DailyWellness.self, SyncState.self,
                Goal.self, TrainingPlan.self, PlannedWorkout.self,
                DailyReadiness.self, DailyCheckIn.self, RuleOverride.self,
                PlanSnapshot.self, ChatThread.self, ChatMessage.self, PlanEdit.self,
                AdaptivePlanReview.self,
                CoachRequestSnapshot.self, CoachMemoryItem.self, CoachPromptSuggestionRecord.self,
                GoogleCalendarConnection.self, GoogleCalendarEventLink.self,
                GoogleCalendarInboundChange.self, ScheduleChangeOperation.self,
                GoogleAvailabilityCalendar.self, DayAvailability.self,
                RunningShoe.self, ShoeMileageEntry.self, RunningShoePreferences.self
            )
        } catch {
            fatalError("Failed to create SwiftData container: \(error)")
        }
        self.container = container
        let pushService = WorkoutPushService(modelContext: container.mainContext)
        let googleCalendarService = GoogleCalendarSyncService(modelContext: container.mainContext)
        let chatStore = CoachChatStore()
        let chatSession = CoachChatSessionState()
#if DEBUG
        if let seededThreadID = DevSeed.seedIfRequested(container.mainContext) {
            chatSession.activeThreadID = seededThreadID
        }
#endif
        let engine = SyncEngine(
            health: HealthKitService(),
            modelContext: container.mainContext,
            pushService: pushService
        )
        // Register observer queries at launch, not from view lifecycle:
        // HealthKit background launches never connect a scene, so view
        // .task would miss them and the delivery would be wasted.
        // Registering before authorization is safe (queries return nothing).
        engine.startObserving()
        _engine = StateObject(wrappedValue: engine)
        _pushService = StateObject(wrappedValue: pushService)
        _googleCalendarService = StateObject(wrappedValue: googleCalendarService)
        _chatStore = StateObject(wrappedValue: chatStore)
        _chatSession = StateObject(wrappedValue: chatSession)
        _runSchedule = StateObject(wrappedValue: RunScheduleController())
        _adaptiveReviewCoordinator = StateObject(wrappedValue: AdaptivePlanReviewCoordinator(
            anthropicClient: ClaudeClient(),
            openAIClient: OpenAIClient()
        ))

        // Background tasks must be registered before launch finishes.
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.refreshTaskIdentifier, using: nil
        ) { task in
            Self.handleMorningRefresh(task, engine: engine)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(engine)
                .environmentObject(pushService)
                .environmentObject(googleCalendarService)
                .environmentObject(chatStore)
                .environmentObject(chatSession)
                .environmentObject(runSchedule)
                .environmentObject(adaptiveReviewCoordinator)
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            engine.isForeground = phase == .active
            if phase == .active, googleCalendarService.connection().smartSchedulingEnabled {
                Task { await googleCalendarService.refreshAvailability(reason: "foreground") }
            }
            if phase == .background {
                Self.scheduleMorningRefresh()
            }
        }
    }

    // MARK: - Morning background refresh (best-effort)

    private static func handleMorningRefresh(_ task: BGTask, engine: SyncEngine) {
        scheduleMorningRefresh() // always re-arm for tomorrow
        let work = Task { @MainActor in
            await engine.syncAll()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }

    private static func scheduleMorningRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskIdentifier)
        request.earliestBeginDate = Calendar.current.nextDate(
            after: .now,
            matching: DateComponents(hour: refreshHour),
            matchingPolicy: .nextTime
        )
        // Submission fails in unsupported environments (e.g. simulator
        // without background modes) — best-effort, foreground sync covers it.
        try? BGTaskScheduler.shared.submit(request)
    }
}

/// Routes between first-run setup and the dashboard. Existing installs that
/// already saw the Health sheet skip the new tour.
struct RootView: View {
    @EnvironmentObject private var engine: SyncEngine
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppAppearance.storageKey) private var appearanceRaw = AppAppearance.system.rawValue
    @AppStorage(CoachLanguage.storageKey) private var languageRaw = CoachLanguage.en.rawValue
    @AppStorage(OnboardingGate.completedKey) private var onboardingCompleted = false
    @EnvironmentObject private var adaptiveReviewCoordinator: AdaptivePlanReviewCoordinator

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceRaw) ?? .system
    }

    private var language: CoachLanguage { CoachLanguage(rawValue: languageRaw) ?? .en }

    private enum LaunchStage {
        case checking
        case unavailable
        case firstRun
        case ready
    }

    @State private var stage: LaunchStage = .checking
    private var health: HealthKitService { engine.health }

    var body: some View {
        Group {
            switch stage {
            case .checking:
                ProgressView()
            case .unavailable:
                VStack(spacing: 20) {
                    ContentUnavailableView(
                        language.onboarding.healthDataUnavailableTitle,
                        systemImage: "heart.slash",
                        description: Text(language.onboarding.healthDataUnavailableDescription)
                    )
                    Button(language.continueLabel, action: activate)
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                }
                .padding()
            case .firstRun:
                FirstRunFlowView(health: health, onFinished: activate)
            case .ready:
                readyRoot
            }
        }
        .preferredColorScheme(appearance.colorScheme)
        .task { await determineStage() }
        #if DEBUG
        .onAppear { DevSeed.applyRequestedGeometry() }
        #endif
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, stage == .ready {
                #if DEBUG
                if DevSeed.requestedScreen != nil { return }
                #endif
                Task { await engine.syncAll() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .planDidChange)) { _ in
            adaptiveReviewCoordinator.planDidChange(in: modelContext)
        }
    }

    @ViewBuilder
    private var readyRoot: some View {
        #if DEBUG
        if let screen = DevSeed.requestedScreen {
            NavigationStack { devScreen(screen) }
        } else {
            RootTabView()
        }
        #else
        RootTabView()
        #endif
    }

    #if DEBUG
    @ViewBuilder
    private func devScreen(_ screen: DevSeed.DevScreen) -> some View {
        switch screen {
        case .settings:
            SettingsView()
        case .provider:
            CoachProviderSettingsView()
        case .delivery:
            WatchDeliverySettingsView()
        case .profile:
            ProfileView()
        case .coach:
            DevCoachLiveView()
        case .shoes:
            RunningShoesView()
        case .workout:
            if let workout = todayWorkout {
                WorkoutDetailView(workout: workout)
            } else {
                ContentUnavailableView("No workout to preview", systemImage: "figure.run")
            }
    }
    }
    private var todayWorkout: PlannedWorkout? {
        let workouts = (try? modelContext.fetch(
            FetchDescriptor<PlannedWorkout>(sortBy: [SortDescriptor(\.date)])
        )) ?? []
        return workouts.first { Calendar.current.isDateInToday($0.date) }
    }
    #endif


    private func determineStage() async {
        guard HealthKitService.isAvailable else {
            stage = .unavailable
            return
        }
        let needsRequest = (try? await health.needsAuthorizationRequest()) ?? true
        OnboardingGate.adoptExistingInstallIfNeeded(healthAlreadyRequested: !needsRequest)
        onboardingCompleted = OnboardingGate.isCompleted()
        if OnboardingGate.shouldShowFirstRun(
            completed: onboardingCompleted,
            healthUnavailable: false
        ) {
            stage = .firstRun
        } else {
            activate()
        }
    }

    private func activate() {
        onboardingCompleted = true
        OnboardingGate.markCompleted()
        stage = .ready
        #if DEBUG
        // Seeded screenshot launches (coach chat and dev screens) skip the
        // notification prompt and sync so nothing overlays the captured screen.
        if DevSeed.isRequested { return }
        #endif
        Task {
            await VerdictNotifier.requestPermission()
            await engine.syncAll()
        }
    }
}

#if DEBUG
/// DEBUG-only coach verification host. Renders the live coach thread and, when
/// `TOR_DEV_LIVE=1`, fires exactly one read-only turn so the real provider
/// answer card can be screenshotted. Compiled out of release builds.
private struct DevCoachLiveView: View {
    @EnvironmentObject private var chatStore: CoachChatStore
    @EnvironmentObject private var chatSession: CoachChatSessionState
    @Environment(\.modelContext) private var modelContext
    @AppStorage("coachModel") private var model = CoachChatConfig.defaultModel
    @State private var fired = false

    var body: some View {
        let workoutID = DevSeed.liveEditWorkoutID(modelContext)
        ChatView(contextualWorkoutID: workoutID)
            .task {
                guard DevSeed.isLiveRequested, !fired else { return }
                fired = true
                guard let threadID = chatSession.activeThreadID else { return }
                var request = CoachTurnRequest(text: DevSeed.livePrompt, model: model, threadID: threadID)
                if let workoutID {
                    request.attachments = [.plannedWorkout(workoutID)]
                    request.evidence = EvidenceSelection(readinessSnapshot: true, weekPlan: true, workout: .planned(workoutID), hasPhoto: false)
                }
                _ = await chatStore.submit(request, in: modelContext)
            }
    }
}
#endif
