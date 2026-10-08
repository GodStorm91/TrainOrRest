import SwiftUI

/// One kilometer of a run, ready to draw. Both the HealthKit reconstruction
/// and the intervals.icu import collapse into this so the chart has a single
/// source of truth and no branch inside the drawing code.
struct SplitDatum: Identifiable, Equatable {
    let kilometer: Int
    let paceSecondsPerKm: Double
    let averageHeartRate: Double?
    let distanceMeters: Double
    let isPartial: Bool

    var id: Int { kilometer }
}

extension SplitDatum {
    init?(_ split: ActivitySplit) {
        guard let pace = split.paceSecondsPerKm else { return nil }
        self.init(
            kilometer: split.kilometer,
            paceSecondsPerKm: pace,
            averageHeartRate: split.averageHeartRate,
            distanceMeters: split.distanceMeters,
            isPartial: split.isPartial
        )
    }
}

/// Maps pace onto a 0...1 position with the axis inverted, so a faster
/// kilometer draws taller. Pace falls as speed rises, which is why every
/// running app flips this axis rather than obeying the chart textbook.
///
/// The domain never collapses onto the run's own spread. A session where
/// every kilometer lands within a few seconds must look level, not dramatic,
/// so the domain is widened to `minimumSpanSeconds` around the median.
struct SplitPaceScale: Equatable {
    /// Narrowest pace range the chart will ever draw across. A 5 s/km spread
    /// inside a 40 s/km window reads as the flat run it was.
    static let minimumSpanSeconds: Double = 40

    /// Breathing room so the fastest column stops short of the ceiling and
    /// the slowest still shows above the floor.
    private static let paddingSeconds: Double = 6

    let fastestSeconds: Double
    let slowestSeconds: Double

    /// Share of the track the slowest column keeps.
    private static let floorFraction: Double = 0.16

    init?(splits: [SplitDatum], band: PaceBand?) {
        let paces = splits.map(\.paceSecondsPerKm)
        guard let minimum = paces.min(), let maximum = paces.max() else { return nil }

        var fastest = minimum - Self.paddingSeconds
        var slowest = maximum + Self.paddingSeconds

        if let band {
            fastest = min(fastest, band.fastSecondsPerKm - Self.paddingSeconds)
            slowest = max(slowest, band.slowSecondsPerKm + Self.paddingSeconds)
        }

        let span = slowest - fastest
        if span < Self.minimumSpanSeconds {
            let centre = (fastest + slowest) / 2
            fastest = centre - Self.minimumSpanSeconds / 2
            slowest = centre + Self.minimumSpanSeconds / 2
        }

        self.fastestSeconds = fastest
        self.slowestSeconds = slowest
    }

    /// 1 is the fastest edge of the domain. The slowest kilometer keeps
    /// `floorFraction` of the track so it still reads as a measurement
    /// rather than as missing data.
    func position(of paceSecondsPerKm: Double) -> Double {
        let span = slowestSeconds - fastestSeconds
        guard span > 0 else { return 0.5 }
        let clamped = min(max(paceSecondsPerKm, fastestSeconds), slowestSeconds)
        let normalized = 1 - (clamped - fastestSeconds) / span
        return Self.floorFraction + (1 - Self.floorFraction) * normalized
    }

    func bandRange(_ band: PaceBand) -> ClosedRange<Double> {
        let low = position(of: band.slowSecondsPerKm)
        let high = position(of: band.fastSecondsPerKm)
        return min(low, high)...max(low, high)
    }
}

// MARK: - Card

/// Compact column chart. One column per kilometer, height keyed to speed,
/// drawn inside a track because the domain does not start at zero and a
/// floating bar would imply it did.
struct SplitPaceColumns: View {
    let splits: [SplitDatum]
    let band: PaceBand?
    var height: CGFloat = 54

    /// Wide columns read as magnitudes rather than as a pace profile, so a
    /// short run spreads its spacing instead of fattening its columns.
    private static let maximumColumnWidth: CGFloat = 20
    private static let minimumSpacing: CGFloat = 2

    private var scale: SplitPaceScale? {
        SplitPaceScale(splits: splits, band: band)
    }

    var body: some View {
        if let scale {
            GeometryReader { proxy in
                let layout = layout(width: proxy.size.width)
                HStack(alignment: .bottom, spacing: layout.spacing) {
                    ForEach(splits) { split in
                        column(split, scale: scale, width: layout.columnWidth, height: proxy.size.height)
                    }
                }
            }
            .frame(height: height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
        }
    }

    private func layout(width: CGFloat) -> (columnWidth: CGFloat, spacing: CGFloat) {
        let count = CGFloat(splits.count)
        guard count > 1 else { return (min(Self.maximumColumnWidth, width), 0) }
        let natural = (width - Self.minimumSpacing * (count - 1)) / count
        let columnWidth = max(2, min(Self.maximumColumnWidth, natural))
        let spacing = max(Self.minimumSpacing, (width - columnWidth * count) / (count - 1))
        return (columnWidth, spacing)
    }

    private func column(_ split: SplitDatum, scale: SplitPaceScale, width: CGFloat, height: CGFloat) -> some View {
        let radius = min(5, width / 4)

        return ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Theme.line)

            if let band {
                let range = scale.bandRange(band)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Theme.text.opacity(0.07))
                    .frame(height: max(2, height * CGFloat(range.upperBound - range.lowerBound)))
                    .offset(y: -height * CGFloat(range.lowerBound))
            }

            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Theme.data)
                .opacity(split.isPartial ? 0.45 : 1)
                .frame(height: height * CGFloat(scale.position(of: split.paceSecondsPerKm)))
        }
        .frame(width: width, height: height)
    }

    private var accessibilityLabel: String {
        let paces = splits.map { split in
            "\(split.kilometer): \(Formatters.pace(split.paceSecondsPerKm))"
        }
        return paces.joined(separator: ", ")
    }
}

// MARK: - Detail

/// Full-width row per kilometer. Same inverted axis and same single data
/// hue as the card, so the two surfaces read as one chart at two sizes.
struct SplitPaceRow: View {
    let split: SplitDatum
    let scale: SplitPaceScale
    let band: PaceBand?
    let language: CoachLanguage

    private var isInsideBand: Bool {
        guard let band else { return false }
        return split.paceSecondsPerKm <= band.slowSecondsPerKm
            && split.paceSecondsPerKm >= band.fastSecondsPerKm
    }

    var body: some View {
        HStack(spacing: 10) {
            Text("\(split.kilometer)")
                .font(.torMono(12, .semibold))
                .foregroundStyle(Theme.faint)
                .frame(width: 20, alignment: .trailing)

            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.line)
                        .frame(height: 10)

                    if let band {
                        let range = scale.bandRange(band)
                        Rectangle()
                            .fill(Theme.text.opacity(0.07))
                            .frame(width: max(2, width * CGFloat(range.upperBound - range.lowerBound)), height: 10)
                            .offset(x: width * CGFloat(range.lowerBound))
                    }

                    Capsule()
                        .fill(Theme.data)
                        .opacity(split.isPartial ? 0.45 : 1)
                        .frame(width: max(6, width * CGFloat(scale.position(of: split.paceSecondsPerKm))), height: 10)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 16)

            Text(Formatters.pace(split.paceSecondsPerKm).replacingOccurrences(of: " /km", with: ""))
                .font(.torMono(12, .semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 44, alignment: .trailing)

            Text(split.averageHeartRate.map { "\(Int($0.rounded()))" } ?? "–")
                .font(.torMono(12, .regular))
                .foregroundStyle(Theme.faint)
                .frame(width: 28, alignment: .trailing)
        }
        .frame(height: 30)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            language.history.splitRowAccessibility(
                kilometer: split.kilometer,
                pace: Formatters.pace(split.paceSecondsPerKm),
                isPartial: split.isPartial,
                insideBand: band == nil ? nil : isInsideBand
            )
        )
    }
}
