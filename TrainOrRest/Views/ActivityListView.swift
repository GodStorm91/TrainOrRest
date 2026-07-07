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
                }
            }
        }
        .navigationTitle("Activities")
    }
}
