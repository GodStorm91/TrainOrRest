import AuthenticationServices
import SwiftUI
import UIKit

/// Runs ChatGPT sign-in from any coach surface and selects ChatGPT once it succeeds.
@MainActor
enum ChatGPTSignInAction {
    enum Outcome: Equatable {
        case connected
        case cancelled
        case failed(String)
    }

    static let planNoticeShownKey = "chatGPTPlanNoticeShown"

    static func run(requestConsent: Bool = false) async -> Outcome {
        let anchor = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        do {
            try await ChatGPTTokenStore.shared.signIn(presentationAnchor: anchor, requestConsent: requestConsent)
        } catch {
            if isCancellation(error) { return .cancelled }
            return .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
        UserDefaults.standard.set(CoachConnection.chatGPT.rawValue, forKey: CoachConnection.storageKey)
        await ChatGPTModelCatalog.shared.invalidate()
        _ = try? await ChatGPTModelCatalog.shared.resolveSelectedModel(tokenProvider: ChatGPTTokenStore.shared)
        return .connected
    }

    /// Whether the one-time plan-usage notice still needs to be shown after a successful connection.
    static func shouldShowPlanNotice(_ defaults: UserDefaults = .standard) -> Bool {
        !defaults.bool(forKey: planNoticeShownKey)
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin { return true }
        return (error as? ChatGPTOAuthError) == .cancelled
    }
}

/// The primary sign-in button. Black with white text per the ChatGPT sign-in button guidance.
struct ContinueWithChatGPTButton: View {
    let title: String
    var isWorking = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isWorking {
                    ProgressView().tint(.white)
                }
                Text(title)
                    .font(.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(.black)
        .foregroundStyle(.white)
        .disabled(isWorking)
    }
}

/// One-time confirmation after the first ChatGPT connection.
struct ChatGPTPlanNoticeSheet: View {
    let copy: SettingsCopy
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Theme.good)
            Text(copy.chatGPTPlanNoticeTitle)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            Text(copy.chatGPTPlanNoticeBody)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Link(copy.manageUsage, destination: CoachConnectionStatus.usageURL)
                .font(.body.weight(.semibold))
            Button(action: onDismiss) {
                Text(copy.gotIt)
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        }
        .padding(24)
        .presentationDetents([.medium])
        .interactiveDismissDisabled()
    }
}

/// Presents `ChatGPTPlanNoticeSheet` once, persisted in `chatGPTPlanNoticeShown`.
struct ChatGPTPlanNoticeModifier: ViewModifier {
    @Binding var isPresented: Bool
    let copy: SettingsCopy
    @AppStorage(ChatGPTSignInAction.planNoticeShownKey) private var noticeShown = false

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            ChatGPTPlanNoticeSheet(copy: copy) {
                noticeShown = true
                isPresented = false
            }
        }
    }
}

extension View {
    func chatGPTPlanNotice(isPresented: Binding<Bool>, copy: SettingsCopy) -> some View {
        modifier(ChatGPTPlanNoticeModifier(isPresented: isPresented, copy: copy))
    }
}

/// The status card's next action for ChatGPT states, shared by Settings and the chat banner.
struct ChatGPTStatusActions: View {
    let status: CoachConnectionStatus
    let copy: SettingsCopy
    let isWorking: Bool
    let signIn: (_ requestConsent: Bool) -> Void

    var body: some View {
        switch status.action {
        case .none:
            EmptyView()
        case .allowPlanUse:
            ContinueWithChatGPTButton(title: copy.allowPlanUse, isWorking: isWorking) { signIn(true) }
        case .reconnect:
            ContinueWithChatGPTButton(title: copy.reconnect, isWorking: isWorking) { signIn(false) }
        case .manageUsage:
            HStack {
                Link(copy.manageUsage, destination: CoachConnectionStatus.usageURL)
                    .font(.body.weight(.semibold))
                Spacer()
                Button(copy.tryAgain) {
                    Task { await ChatGPTTokenStore.shared.clearUsageLimit() }
                }
            }
        }
    }
}
