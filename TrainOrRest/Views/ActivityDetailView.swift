import SwiftUI

struct ActivityDetailView: View {
    let activity: CompletedActivity

    var body: some View {
        List {
            Section("Run") {
                LabeledContent("Date", value: activity.date.formatted(date: .long, time: .shortened))
                LabeledContent("Distance", value: Formatters.kilometers(activity.distanceMeters))
                LabeledContent("Duration", value: Formatters.duration(activity.durationSeconds))
                LabeledContent("Avg Pace", value: Formatters.pace(activity.avgPaceSecondsPerKm))
            }
            Section("Heart Rate") {
                LabeledContent("Average", value: Formatters.heartRate(activity.avgHeartRate))
                LabeledContent("Max", value: Formatters.heartRate(activity.maxHeartRate))
            }
            Section("Source") {
                LabeledContent("Recorded by", value: activity.sourceName)
            }
        }
        .navigationTitle(activity.date.formatted(.dateTime.month(.abbreviated).day()))
        .navigationBarTitleDisplayMode(.inline)
    }
}
