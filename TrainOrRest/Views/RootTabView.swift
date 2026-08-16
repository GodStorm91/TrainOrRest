import SwiftUI
import UIKit

/// Three-destination shell with a compact floating Liquid Glass dock.
struct RootTabView: View {
    enum Tab: Hashable { case calendar, chat, profile }

    @State private var selection: Tab = .chat
    @State private var isKeyboardVisible = false
    @Namespace private var dockNamespace

    var body: some View {
        ZStack(alignment: .bottom) {
            activeScreen
                .id(selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.992, anchor: .center)),
                    removal: .opacity
                ))

            if shouldShowDock {
                TorTabDock(selection: $selection, namespace: dockNamespace)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.easeOut(duration: 0.18)) { isKeyboardVisible = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.18)) { isKeyboardVisible = false }
        }
        .animation(.smooth(duration: 0.26), value: selection)
        .tint(Theme.accent)
    }

    @ViewBuilder
    private var activeScreen: some View {
        switch selection {
        case .calendar:
            NavigationStack { PlanCalendarView() }
        case .chat:
            NavigationStack {
                ChatView(
                    bottomNavigation: AnyView(
                        TorTabDock(selection: $selection, namespace: dockNamespace)
                    )
                )
            }
        case .profile:
            NavigationStack { ProfileView() }
        }
    }

    private var shouldShowDock: Bool {
        !isKeyboardVisible && selection != .chat
    }
}

private struct TorTabDock: View {
    @Binding var selection: RootTabView.Tab
    let namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 4) {
            item(.calendar, "Calendar", "calendar")
            item(.chat, "Chat", "message")
            item(.profile, "Profile", "person.crop.circle")
        }
        .padding(4)
        .frame(maxWidth: 292)
        .frame(height: 56)
        .torGlass(cornerRadius: 28, tint: .graphite)
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
        .clipShape(Capsule(style: .continuous))
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 42)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: selection)
    }

    private func item(_ tab: RootTabView.Tab, _ title: String, _ symbol: String) -> some View {
        let active = selection == tab
        return Button {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                selection = tab
            }
        } label: {
            ZStack {
                if active {
                    Capsule(style: .continuous)
                        .fill(Theme.accent.opacity(0.13))
                        .matchedGeometryEffect(id: "dock-active-pill", in: namespace)
                }

                HStack(spacing: active ? 6 : 0) {
                    Image(systemName: symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .scaleEffect(active ? 1.04 : 1.0)
                    if active {
                        Text(title)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .leading)),
                                removal: .opacity
                            ))
                    }
                }
                .foregroundStyle(active ? Theme.accent : Theme.faint)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }
}
