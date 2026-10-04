import Foundation
import OSLog

/// Latency instrumentation for one Coach turn.
///
/// A turn spans local context assembly plus one to `CoachChatConfig.maxToolRounds`
/// provider round trips, and until this existed nothing on the path recorded where
/// the time went. Intervals show up in Instruments under the `coach` subsystem;
/// the matching `Logger` lines make the same numbers readable in Console without
/// attaching a profiler.
enum CoachSignpost {
    static let subsystem = "com.trainorrest.coach"

    static let signposter = OSSignposter(subsystem: subsystem, category: "turn")
    static let logger = Logger(subsystem: subsystem, category: "turn")

    enum Name {
        static let turn: StaticString = "coach turn"
        static let contextBuild: StaticString = "context build"
        static let historyFetch: StaticString = "history fetch"
        static let round: StaticString = "model round"
    }

    /// Measures an async step, emits the signpost interval, and logs the duration.
    static func measure<T>(
        _ name: StaticString,
        _ detail: String = "",
        operation: () async throws -> T
    ) async rethrows -> T {
        let state = signposter.beginInterval(name, id: signposter.makeSignpostID())
        let started = DispatchTime.now().uptimeNanoseconds
        defer {
            signposter.endInterval(name, state)
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000
            logger.info("\(String(describing: name), privacy: .public) \(elapsed, format: .fixed(precision: 3))s \(detail, privacy: .public)")
        }
        return try await operation()
    }

    /// Measures a synchronous step on the same channels.
    static func measureSync<T>(
        _ name: StaticString,
        _ detail: String = "",
        operation: () throws -> T
    ) rethrows -> T {
        let id = signposter.makeSignpostID()
        let state = signposter.beginInterval(name, id: id)
        let started = DispatchTime.now().uptimeNanoseconds
        defer {
            signposter.endInterval(name, state)
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000
            logger.info("\(String(describing: name), privacy: .public) \(elapsed, format: .fixed(precision: 3))s \(detail, privacy: .public)")
        }
        return try operation()
    }

    /// One line per provider round, the number that distinguishes a one round turn
    /// from a five round turn after the fact.
    static func roundFinished(
        index: Int,
        actionType: CoachRequestActionType,
        tools: [String],
        maxTokens: Int,
        stopReason: String?,
        seconds: Double
    ) {
        logger.info(
            """
            round \(index, privacy: .public)/\(CoachChatConfig.maxToolRounds, privacy: .public) \
            intent=\(actionType.rawValue, privacy: .public) \
            tools=\(tools.joined(separator: ","), privacy: .public) \
            max_tokens=\(maxTokens, privacy: .public) \
            stop=\(stopReason ?? "none", privacy: .public) \
            \(seconds, format: .fixed(precision: 3))s
            """
        )
    }
}
