import SwiftUI

enum CoachHeaderMetrics {
    static let headerTopPadding: CGFloat = 8
    static let headerBottomSpacing: CGFloat = 14 // brief: 12-16pt visual spacing
    static let fallbackHeaderHeight: CGFloat = 48 // yields ~70 before measurement, matching the old constant

    /// Top inset for the message list so the first line clears the sticky header.
    static func messageTopInset(headerHeight: CGFloat) -> CGFloat {
        max(headerHeight, fallbackHeaderHeight) + headerTopPadding + headerBottomSpacing
    }
}

struct CoachHeaderHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = CoachHeaderMetrics.fallbackHeaderHeight

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
