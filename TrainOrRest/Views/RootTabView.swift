import SwiftUI

/// The app's tab shell: Today · Trends · Plan · Profile. Accent-tinted to the
/// design's purple. (The design's raised center "+" FAB bar is a next-round
/// refinement; this uses the standard tab bar so navigation is solid first.)
struct RootTabView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "house.fill") }

            NavigationStack { TrendsView() }
                .tabItem { Label("Trends", systemImage: "chart.line.uptrend.xyaxis") }

            NavigationStack { PlanCalendarView() }
                .tabItem { Label("Plan", systemImage: "calendar") }

            NavigationStack { ProfileView() }
                .tabItem { Label("Profile", systemImage: "person.fill") }
        }
        .tint(Theme.accent)
    }
}
