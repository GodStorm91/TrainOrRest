import Foundation
import SwiftUI

@MainActor
final class CoachChatSessionState: ObservableObject {
    @Published var activeThreadID: UUID?
}
