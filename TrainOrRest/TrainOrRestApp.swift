import SwiftData
import SwiftUI

@main
struct TrainOrRestApp: App {
    private let container: ModelContainer
    @StateObject private var engine: SyncEngine

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(
                for: CompletedActivity.self, DailyWellness.self, SyncState.self
            )
        } catch {
            fatalError("Failed to create SwiftData container: \(error)")
        }
        self.container = container
        let engine = SyncEngine(
            health: HealthKitService(),
            modelContext: container.mainContext
        )
        // Register observer queries at launch, not from view lifecycle:
        // HealthKit background launches never connect a scene, so view
        // .task would miss them and the delivery would be wasted.
        // Registering before authorization is safe (queries return nothing).
        engine.startObserving()
        _engine = StateObject(wrappedValue: engine)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(engine)
        }
        .modelContainer(container)
    }
}

/// Routes between onboarding (HealthKit permission not yet requested) and the
/// dashboard. HealthKit never reveals read-grant status, so once the request
/// was shown we always proceed; empty data renders the waiting state.
struct RootView: View {
    @EnvironmentObject private var engine: SyncEngine
    @Environment(\.scenePhase) private var scenePhase

    private enum AuthorizationStage {
        case checking
        case unavailable
        case needsRequest
        case ready
    }

    @State private var stage: AuthorizationStage = .checking
    private var health: HealthKitService { engine.health }

    var body: some View {
        Group {
            switch stage {
            case .checking:
                ProgressView()
            case .unavailable:
                ContentUnavailableView(
                    "Health Data Unavailable",
                    systemImage: "heart.slash",
                    description: Text("This device does not provide Apple Health data.")
                )
            case .needsRequest:
                OnboardingView(health: health, onAuthorized: activate)
            case .ready:
                DashboardView()
            }
        }
        .task { await determineStage() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, stage == .ready {
                Task { await engine.syncAll() }
            }
        }
    }

    private func determineStage() async {
        guard HealthKitService.isAvailable else {
            stage = .unavailable
            return
        }
        let needsRequest = (try? await health.needsAuthorizationRequest()) ?? true
        if needsRequest {
            stage = .needsRequest
        } else {
            activate()
        }
    }

    private func activate() {
        stage = .ready
        Task { await engine.syncAll() }
    }
}

struct OnboardingView: View {
    let health: HealthKitService
    let onAuthorized: () -> Void
    @State private var isRequesting = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "figure.run.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.tint)
            Text("TrainOrRest")
                .font(.largeTitle.bold())
            Text("Connect Apple Health to read your Garmin runs, sleep, HRV and resting heart rate. Everything stays on this device.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Button {
                requestAccess()
            } label: {
                if isRequesting {
                    ProgressView()
                } else {
                    Text("Connect Apple Health")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRequesting)
            .padding(.horizontal)
        }
        .padding()
    }

    private func requestAccess() {
        isRequesting = true
        Task {
            defer { isRequesting = false }
            // Proceed even if the sheet errors out: read-grant status is
            // opaque, and the dashboard's empty state handles no data.
            try? await health.requestAuthorization()
            onAuthorized()
        }
    }
}
