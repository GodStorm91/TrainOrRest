import SwiftUI

/// The app's tab shell with the design's raised center-FAB bar. A native
/// TabView drives per-tab navigation state (its bar hidden); a custom bar is
/// added via safeAreaInset so screen content insets above it correctly.
struct RootTabView: View {
    enum Tab: Hashable { case today, trends, plan, profile }

    @State private var selection: Tab = .today
    @State private var showGoalEntry = false

    var body: some View {
        TabView(selection: $selection) {
            TodayView().tag(Tab.today)
            NavigationStack { TrendsView() }.tag(Tab.trends)
            NavigationStack { PlanCalendarView() }.tag(Tab.plan)
            NavigationStack { ProfileView() }.tag(Tab.profile)
        }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            TorTabBar(selection: $selection, onCenterTap: { showGoalEntry = true })
        }
        .sheet(isPresented: $showGoalEntry) { GoalEntryView() }
        .tint(Theme.accent)
    }
}

private struct TorTabBar: View {
    @Binding var selection: RootTabView.Tab
    let onCenterTap: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            item(.today, "Today", "house.fill")
            item(.trends, "Trends", "chart.line.uptrend.xyaxis")
            centerButton
            item(.plan, "Plan", "calendar")
            item(.profile, "Profile", "person.fill")
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

    private var centerButton: some View {
        Button(action: onCenterTap) {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Theme.accent, in: Circle())
                .overlay(Circle().strokeBorder(Theme.bg, lineWidth: 4))
                .shadow(color: Theme.accent.opacity(0.5), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .offset(y: -18)
        .accessibilityLabel("New race goal")
    }
}
