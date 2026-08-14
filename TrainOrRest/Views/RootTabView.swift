import SwiftUI
import UIKit

/// The app's four-tab shell. A native TabView drives per-tab navigation state
/// (its bar hidden); a custom bar is added via safeAreaInset so screen content
/// insets above it correctly.
struct RootTabView: View {
    enum Tab: Hashable { case today, plan, trends, coach }

    @State private var selection: Tab = .today
    @State private var isKeyboardVisible = false

    var body: some View {
        TabView(selection: $selection) {
            TodayView().tag(Tab.today)
            NavigationStack { PlanCalendarView() }.tag(Tab.plan)
            NavigationStack { TrendsView() }.tag(Tab.trends)
            NavigationStack { ChatView() }.tag(Tab.coach)
        }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !isKeyboardVisible {
                TorTabBar(selection: $selection)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.easeOut(duration: 0.18)) {
                isKeyboardVisible = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.18)) {
                isKeyboardVisible = false
            }
        }
        .tint(Theme.accent)
    }
}

private struct TorTabBar: View {
    @Binding var selection: RootTabView.Tab

    var body: some View {
        HStack(spacing: 0) {
            item(.today, "Today", "house")
            item(.plan, "Plan", "calendar")
            item(.trends, "Trends", "chart.line.uptrend.xyaxis")
            item(.coach, "Coach", "message")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .background(alignment: .top) {
            Rectangle().fill(Theme.border).frame(height: 1)
        }
        .background(.ultraThinMaterial)
    }

    private func item(_ tab: RootTabView.Tab, _ title: String, _ symbol: String) -> some View {
        let active = selection == tab
        return Button {
            selection = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 21, weight: .medium))
                Text(title).font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(active ? Theme.accent : Theme.faint)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }
}
