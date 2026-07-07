import Foundation

/// Metric-unit display formatting (km, min/km) shared across views.
enum Formatters {
    static func kilometers(_ meters: Double?) -> String {
        guard let meters else { return "–" }
        return String(format: "%.2f km", meters / 1000)
    }

    static func pace(_ secondsPerKm: Double?) -> String {
        guard let secondsPerKm, secondsPerKm.isFinite, secondsPerKm > 0 else { return "–" }
        let total = Int(secondsPerKm.rounded())
        return String(format: "%d:%02d /km", total / 60, total % 60)
    }

    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    static func heartRate(_ bpm: Double?) -> String {
        guard let bpm else { return "–" }
        return "\(Int(bpm.rounded())) bpm"
    }

    static func sleep(_ hours: Double?) -> String {
        guard let hours else { return "–" }
        let totalMinutes = Int((hours * 60).rounded())
        return String(format: "%dh %02dm", totalMinutes / 60, totalMinutes % 60)
    }

    static func decimal(_ value: Double?, unit: String) -> String {
        guard let value else { return "–" }
        return String(format: "%.1f %@", value, unit)
    }
}
