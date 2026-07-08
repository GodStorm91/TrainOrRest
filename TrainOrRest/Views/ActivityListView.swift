import SwiftData
import SwiftUI

struct ActivityListView: View {
    @Query(sort: \CompletedActivity.date, order: .reverse) private var activities: [CompletedActivity]

    var body: some View {
        List {
            if activities.isEmpty {
                ContentUnavailableView(
                    "No Runs Yet",
                    systemImage: "figure.run",
                    description: Text("Runs recorded on your Garmin will appear here after Garmin Connect syncs to Apple Health.")
                )
            } else {
                ForEach(activities) { activity in
                    NavigationLink {
                        ActivityDetailView(activity: activity)
                    } label: {
                        ActivityRow(activity: activity)
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                }
            }
        }
        .navigationTitle("Activities")
        .animation(.easeOut(duration: 0.22), value: activities.count)
    }
}
