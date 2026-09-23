import Foundation
import SwiftUI

struct PlanPhaseRibbonModel: Equatable {
    struct Segment: Identifiable, Equatable {
        let id: Int
        let phase: TrainingPhase
        let startWeekIndex: Int
        let endWeekIndex: Int
        let ticks: [Tick]

        var weekCount: Int { ticks.count }

        var currentWeekInSegment: Int? {
            ticks.firstIndex(where: \.isCurrent).map { $0 + 1 }
        }
    }

    struct Tick: Identifiable, Equatable {
        let weekIndex: Int
        let startDate: Date
        let isCurrent: Bool
        let isDown: Bool
        let targetVolumeKm: Double?

        var id: Int { weekIndex }
    }

    let segments: [Segment]
    let currentWeekIndex: Int
    let activeSegmentID: Segment.ID?
    private let weekStarts: [Int: Date]

    init?(plan: TrainingPlan, summary: ActivePlanSummary, calendar: Calendar) {
        guard !plan.weekPhasesRaw.isEmpty else { return nil }

        let planWeekZero = PlanGenerator.mondayOfWeek(containing: plan.anchorDate, calendar: calendar)
        let currentWeekIndex = min(max(summary.currentWeek - 1, 0), plan.weekPhasesRaw.count - 1)
        var weekStarts: [Int: Date] = [:]
        var segments: [Segment] = []

        for phase in summary.phases {
            let start = max(phase.startWeekIndex, 0)
            let end = min(phase.endWeekIndex, plan.weekPhasesRaw.count - 1)
            guard start <= end else { continue }

            let ticks = (start...end).compactMap { weekIndex -> Tick? in
                guard let startDate = calendar.date(byAdding: .day, value: weekIndex * 7, to: planWeekZero) else {
                    return nil
                }
                weekStarts[weekIndex] = startDate
                return Tick(
                    weekIndex: weekIndex,
                    startDate: startDate,
                    isCurrent: weekIndex == currentWeekIndex,
                    isDown: plan.weekIsDown.indices.contains(weekIndex) ? plan.weekIsDown[weekIndex] : false,
                    targetVolumeKm: plan.weekTargetVolumesKm.indices.contains(weekIndex)
                        ? plan.weekTargetVolumesKm[weekIndex]
                        : nil
                )
            }
            guard !ticks.isEmpty else { continue }

            segments.append(Segment(
                id: phase.id,
                phase: phase.phase,
                startWeekIndex: start,
                endWeekIndex: end,
                ticks: ticks
            ))
        }

        guard !segments.isEmpty else { return nil }
        self.segments = segments
        self.currentWeekIndex = currentWeekIndex
        self.activeSegmentID = segments.first(where: {
            $0.startWeekIndex...$0.endWeekIndex ~= currentWeekIndex
        })?.id
        self.weekStarts = weekStarts
    }

    func weekStart(for weekIndex: Int) -> Date? {
        weekStarts[weekIndex]
    }
}

struct PlanPhaseRibbonView: View {
    let model: PlanPhaseRibbonModel
    let language: CoachLanguage
    let onSelectWeek: (Int) -> Void

    private let weekWidth: CGFloat = 62

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(model.segments) { segment in
                        segmentView(segment)
                            .id(segment.id)
                    }
                }
                .padding(1)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                scrollToActiveSegment(proxy, animated: false)
            }
            .onChange(of: model.activeSegmentID) {
                scrollToActiveSegment(proxy, animated: true)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func segmentView(_ segment: PlanPhaseRibbonModel.Segment) -> some View {
        let isActive = segment.id == model.activeSegmentID
        let tint = segment.phase.styleColor
        let segmentWidth = weekWidth * CGFloat(segment.weekCount)
        let contentWeekWidth = max(32, (segmentWidth - 20) / CGFloat(max(segment.weekCount, 1)))

        return VStack(alignment: .leading, spacing: 8) {
            Button {
                onSelectWeek(segment.ticks.first(where: \.isCurrent)?.weekIndex ?? segment.startWeekIndex)
            } label: {
                Text(segmentLabel(segment, isActive: isActive))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isActive ? Theme.text : Theme.dim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(segmentAccessibilityLabel(segment, isActive: isActive))

            HStack(spacing: 0) {
                ForEach(segment.ticks) { tick in
                    tickButton(tick, phase: segment.phase)
                        .frame(width: contentWeekWidth)
                }
            }
        }
        .padding(10)
        .frame(width: segmentWidth, alignment: .leading)
        .background(Theme.soft(tint, isActive ? 0.16 : 0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isActive ? tint.opacity(0.55) : Theme.border, lineWidth: 1)
        )
    }
    private func tickButton(_ tick: PlanPhaseRibbonModel.Tick, phase: TrainingPhase) -> some View {
        let tint = phase.styleColor

        return Button {
            onSelectWeek(tick.weekIndex)
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        if tick.isDown {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Theme.soft(Theme.good, 0.10))
                            DownWeekHatch()
                                .stroke(Theme.good.opacity(0.36), lineWidth: 1)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        Circle()
                            .fill(tick.isCurrent ? tint : Theme.card)
                            .overlay(Circle().strokeBorder(tick.isCurrent ? tint : Theme.border, lineWidth: 1))
                            .frame(width: 20, height: 20)
                    }
                    .frame(width: 24, height: 24)

                    if tick.isDown {
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Theme.good)
                            .padding(2)
                            .background(Theme.card, in: Circle())
                            .offset(x: 5, y: -5)
                    }
                }
                if let target = tick.targetVolumeKm {
                    Text("\(Int(target.rounded()))")
                        .font(.caption2.weight(.medium).monospacedDigit())
                        .foregroundStyle(Theme.faint)
                        .lineLimit(1)
                }
            }
            .frame(minHeight: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tickAccessibilityLabel(tick, phase: phase))
        .accessibilityAddTraits(tick.isCurrent ? .isSelected : [])
    }

    private func segmentLabel(_ segment: PlanPhaseRibbonModel.Segment, isActive: Bool) -> String {
        let name = language.name(segment.phase)
        guard isActive, let currentWeek = segment.currentWeekInSegment else { return name }
        return "\(name) · \(currentWeek)/\(segment.weekCount)"
    }

    private func segmentAccessibilityLabel(_ segment: PlanPhaseRibbonModel.Segment, isActive: Bool) -> String {
        let name = language.name(segment.phase)
        guard isActive, let currentWeek = segment.currentWeekInSegment else { return name }
        return "\(name), \(language.plan.phaseProgress(week: currentWeek, total: segment.weekCount))"
    }

    private func tickAccessibilityLabel(_ tick: PlanPhaseRibbonModel.Tick, phase: TrainingPhase) -> String {
        var parts = [language.name(phase), language.plan.weekOfTotal(tick.weekIndex + 1, total: totalWeeks)]
        if let target = tick.targetVolumeKm {
            parts.append("\(Int(target.rounded())) km")
        }
        if tick.isCurrent {
            parts.append(language.plan.thisWeek)
        }
        if tick.isDown {
            parts.append(language.recoveryLabel)
        }
        return parts.joined(separator: ", ")
    }

    private var totalWeeks: Int {
        model.segments.reduce(0) { $0 + $1.weekCount }
    }

    private func scrollToActiveSegment(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let segmentID = model.activeSegmentID else { return }
        DispatchQueue.main.async {
            let action = { proxy.scrollTo(segmentID, anchor: .center) }
            if animated {
                withAnimation(.easeOut(duration: 0.2)) { action() }
            } else {
                action()
            }
        }
    }
}

private struct DownWeekHatch: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let spacing: CGFloat = 5
        var x = rect.minX - rect.height
        while x < rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += spacing
        }
        return path
    }
}
