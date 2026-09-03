import Foundation
import SwiftUI
import WidgetKit

struct ReadinessEntry: TimelineEntry {
    let date: Date
    let snapshot: ReadinessWidgetSnapshot
}

struct ReadinessProvider: TimelineProvider {
    func placeholder(in context: Context) -> ReadinessEntry {
        ReadinessEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (ReadinessEntry) -> Void) {
        completion(ReadinessEntry(date: .now, snapshot: ReadinessWidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ReadinessEntry>) -> Void) {
        let entry = ReadinessEntry(date: .now, snapshot: ReadinessWidgetSnapshot.load())
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1_800)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct ReadinessWidgetView: View {
    let entry: ReadinessEntry
    @Environment(\.widgetFamily) private var family

    private var snapshot: ReadinessWidgetSnapshot {
        entry.snapshot
    }

    private var language: WidgetCoachLanguage {
        WidgetCoachLanguage(rawValue: snapshot.languageRaw ?? "en") ?? .en
    }

    private var verdictText: String {
        language.today.verdictWord(rawValue: snapshot.verdictRaw)
    }

    private var reasonText: String {
        snapshot.reason.isEmpty
            ? language.today.widgetReason(rawVerdict: snapshot.verdictRaw)
            : snapshot.reason
    }

    private var footerText: String {
        guard let computedAt = snapshot.computedAt else {
            return language.today.noFreshData
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = language.uiLocale
        formatter.unitsStyle = .abbreviated
        return language.today.updated(
            formatter.localizedString(for: computedAt, relativeTo: snapshot.updatedAt)
        )
    }

    var body: some View {
        ZStack {
            background
            VStack(alignment: .leading, spacing: family == .systemSmall ? 8 : 12) {
                HStack(alignment: .top) {
                    Text(language.today.readinessLabel)
                        .font(.system(size: 11, weight: .semibold, design: .rounded).width(.condensed))
                        .foregroundStyle(.white.opacity(0.64))
                    Spacer(minLength: 8)
                    ReadinessGaugeMark(progress: scoreProgress, color: verdictColor)
                        .frame(width: 30, height: 30)
                }

                Spacer(minLength: 2)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(snapshot.scoreText)
                        .font(.system(size: family == .systemSmall ? 54 : 64, weight: .bold).width(.condensed))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.72)
                    Text(verdictText)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(verdictColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }

                Text(reasonText)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.76))
                    .lineLimit(family == .systemSmall ? 2 : 3)
                    .minimumScaleFactor(0.82)

                Text(footerText)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.46))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(16)
        }
        .containerBackground(for: .widget) {
            background
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(red: 0.10, green: 0.09, blue: 0.15),
                Color(red: 0.04, green: 0.04, blue: 0.07)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var verdictColor: Color {
        switch snapshot.verdictRaw {
        case "train":
            return Color(red: 0.31, green: 0.86, blue: 0.77)
        case "goEasy":
            return Color(red: 0.89, green: 0.77, blue: 0.54)
        case "rest":
            return Color(red: 0.59, green: 0.68, blue: 0.86)
        default:
            return Color.white.opacity(0.62)
        }
    }

    private var scoreProgress: Double {
        guard let score = snapshot.score else { return 0.28 }
        return min(1, max(0, Double(score) / 100))
    }
}

private struct ReadinessGaugeMark: View {
    let progress: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.14), lineWidth: 4)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
        }
        .accessibilityHidden(true)
    }
}

struct ReadinessWidget: Widget {
    let kind = "ReadinessWidget"

    private var configurationLanguage: WidgetCoachLanguage {
        WidgetCoachLanguage(rawValue: ReadinessWidgetSnapshot.load().languageRaw ?? "en") ?? .en
    }

    var body: some WidgetConfiguration {

        StaticConfiguration(kind: kind, provider: ReadinessProvider()) { entry in
            ReadinessWidgetView(entry: entry)
        }
        .configurationDisplayName(configurationLanguage.today.configurationDisplayName)
        .description(configurationLanguage.today.configurationDescription)
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct TrainOrRestWidgetBundle: WidgetBundle {
    var body: some Widget {
        ReadinessWidget()
    }
}

#Preview(as: .systemSmall) {
    ReadinessWidget()
} timeline: {
    ReadinessEntry(date: .now, snapshot: .placeholder)
}
