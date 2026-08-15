import SwiftUI

enum CoachTodayHeaderText {
    static func text(for readiness: DailyReadiness?) -> String {
        guard let readiness else { return "Engine · No verdict yet" }
        return ([readiness.verdict.bannerWord] + readiness.ruleIDs.map(\.code))
            .reduce("Engine") { partial, item in "\(partial) · \(item)" }
    }

    static func compactText(for readiness: DailyReadiness?) -> String {
        guard let readiness else { return "No verdict yet" }
        return ([readiness.verdict.bannerWord] + readiness.ruleIDs.map(\.code))
            .joined(separator: " · ")
    }
}

struct CoachTodayEngineHeader: View {
    let readiness: DailyReadiness?
    @State private var showsRationale = false

    private var tint: Color {
        readiness?.verdict.torColor ?? Theme.dim
    }

    var body: some View {
        Button {
            showsRationale = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: readiness?.verdict.bannerSymbol ?? "chart.line.uptrend.xyaxis")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)

                ViewThatFits(in: .horizontal) {
                    Text(CoachTodayHeaderText.text(for: readiness))
                    Text(CoachTodayHeaderText.compactText(for: readiness))
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

                Spacer(minLength: 6)

                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.faint)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Theme.bg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.border).frame(height: 1)
        }
        .accessibilityLabel(accessibilityLabel)
        .sheet(isPresented: $showsRationale) {
            CoachTodayRationaleSheet(readiness: readiness)
        }
    }

    private var accessibilityLabel: String {
        guard let readiness else { return "Engine readiness. No verdict yet." }
        let rules = readiness.ruleIDs.map(\.code).joined(separator: ", ")
        if rules.isEmpty {
            return "Engine readiness. \(readiness.verdict.bannerWord)."
        }
        return "Engine readiness. \(readiness.verdict.bannerWord). Fired rules \(rules)."
    }
}

private struct CoachTodayRationaleSheet: View {
    let readiness: DailyReadiness?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(.system(.title2, design: .rounded).weight(.semibold))
                            .foregroundStyle(Theme.text)
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(Theme.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let readiness {
                        CoachRationaleCard(rationale: ReadinessRationale(from: readiness))

                        TorCard(padding: 0, cornerRadius: 16) {
                            VStack(spacing: 0) {
                                ForEach(ruleRows) { row in
                                    ReceiptRow(row: row)
                                    if row.id != ruleRows.last?.id {
                                        Rectangle()
                                            .fill(Theme.line)
                                            .frame(height: 1)
                                            .padding(.leading, 46)
                                    }
                                }
                            }
                        }
                    } else {
                        TorCard(padding: 14, cornerRadius: 16) {
                            Label {
                                Text("The readiness engine has not produced a verdict for today.")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.dim)
                                    .fixedSize(horizontal: false, vertical: true)
                            } icon: {
                                Image(systemName: "chart.line.uptrend.xyaxis")
                                    .foregroundStyle(Theme.dim)
                            }
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.bg.ignoresSafeArea())
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.bg)
    }

    private var title: String {
        readiness.map { "Engine · \($0.verdict.bannerWord)" } ?? "No verdict yet"
    }

    private var subtitle: String {
        guard let readiness else {
            return "No timestamp is available until today's readiness is computed."
        }
        return "Computed \(readiness.computedAt.formatted(date: .abbreviated, time: .shortened))."
    }

    private var ruleRows: [ReceiptSheet.Row] {
        guard let readiness else { return [] }
        var rows = readiness.ruleIDs.map { id in
            ReceiptSheet.Row.detail("Rule \(id.code) · \(id.title)", value: id.detail, symbol: "checkmark.seal")
        }
        if rows.isEmpty {
            rows.append(.detail("Rules", value: "No deterministic readiness rules fired today.", symbol: "checkmark.seal"))
        }
        return rows
    }
}

private struct ReceiptRow: View {
    let row: ReceiptSheet.Row

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: row.symbol ?? "info.circle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(row.kind == .check ? Theme.good : Theme.accent)
                .frame(width: 22, height: 22)
                .background(Theme.soft(row.kind == .check ? Theme.good : Theme.accent), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(row.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(row.value)
                    .font(.footnote)
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
