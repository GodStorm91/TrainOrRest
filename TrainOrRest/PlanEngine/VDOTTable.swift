import Foundation

/// Daniels VDOT computations using the published Daniels–Gilbert model
/// ("Oxygen Power", Daniels & Gilbert 1979; same model underlies the tables
/// in "Daniels' Running Formula"). Implemented as formulas rather than a
/// transcribed table — identical mapping, no transcription-error surface.
/// Unit tests spot-check outputs against published table rows.
enum VDOTTable {
    // MARK: - Daniels–Gilbert model

    /// Oxygen cost (ml/kg/min) of running at velocity v (meters/minute).
    static func oxygenCost(velocityMetersPerMinute v: Double) -> Double {
        -4.60 + 0.182258 * v + 0.000104 * v * v
    }

    /// Fraction of VO2max sustainable for a race of duration t (minutes).
    static func sustainableFraction(minutes t: Double) -> Double {
        0.8 + 0.1894393 * exp(-0.012778 * t) + 0.2989558 * exp(-0.1932605 * t)
    }

    /// VDOT implied by a race (or hard training) performance.
    static func vdot(distanceMeters: Double, timeSeconds: Double) -> Double {
        let minutes = timeSeconds / 60
        let velocity = distanceMeters / minutes
        return oxygenCost(velocityMetersPerMinute: velocity) / sustainableFraction(minutes: minutes)
    }

    /// Predicted race time (seconds) for a distance at a given VDOT.
    /// Monotonic in time, solved by bisection.
    static func predictedTimeSeconds(distanceMeters: Double, vdot: Double) -> Double {
        var low = 4.0, high = 600.0 // minutes
        for _ in 0..<60 {
            let mid = (low + high) / 2
            if VDOTTable.vdot(distanceMeters: distanceMeters, timeSeconds: mid * 60) > vdot {
                low = mid // performance implies higher fitness → true time is slower
            } else {
                high = mid
            }
        }
        return (low + high) / 2 * 60
    }

    /// Velocity (m/min) that costs the given fraction of VDOT.
    static func velocity(atVO2Fraction fraction: Double, vdot: Double) -> Double {
        let target = fraction * vdot
        let a = 0.000104, b = 0.182258, c = -(4.60 + target)
        return (-b + (b * b - 4 * a * c).squareRoot()) / (2 * a)
    }

    static func paceSecondsPerKm(atVO2Fraction fraction: Double, vdot: Double) -> Double {
        60_000 / velocity(atVO2Fraction: fraction, vdot: vdot)
    }

    // MARK: - Training zones

    /// %VO2max anchors for Daniels training zones (band endpoints).
    private enum Zone {
        static let easy = (fast: 0.73, slow: 0.62)
        static let marathon = (fast: 0.86, slow: 0.82)
        static let threshold = (fast: 0.90, slow: 0.86)
        static let interval = (fast: 1.00, slow: 0.95)
    }

    static func trainingPaces(vdot: Double) -> TrainingPaces {
        func band(_ zone: (fast: Double, slow: Double)) -> PaceBand {
            PaceBand(
                fastSecondsPerKm: paceSecondsPerKm(atVO2Fraction: zone.fast, vdot: vdot),
                slowSecondsPerKm: paceSecondsPerKm(atVO2Fraction: zone.slow, vdot: vdot)
            )
        }
        return TrainingPaces(
            easy: band(Zone.easy),
            marathon: band(Zone.marathon),
            threshold: band(Zone.threshold),
            interval: band(Zone.interval)
        )
    }
}
