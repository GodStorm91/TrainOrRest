import Foundation

extension CompletedActivity {
    /// Decoded view over `splitsData`. Returns `nil` while reconstruction has
    /// not run, and an empty array once it ran and found nothing usable.
    var splits: [ActivitySplit]? {
        get { splitsData.flatMap { try? JSONDecoder().decode([ActivitySplit].self, from: $0) } }
        set { splitsData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }
}
