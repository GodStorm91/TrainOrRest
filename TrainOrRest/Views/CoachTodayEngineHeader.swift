import SwiftUI

enum CoachTodayHeaderText {
    static func text(for readiness: DailyReadiness?, language: CoachLanguage = .en) -> String {
        guard let readiness else {
            return "\(language.today.engine) · \(language.today.noVerdictYet)"
        }
        return language.today.engineText(
            verdict: readiness.verdict,
            ruleCodes: readiness.ruleIDs.map(\.code)
        )
    }

    static func compactText(for readiness: DailyReadiness?, language: CoachLanguage = .en) -> String {
        guard let readiness else { return language.today.noVerdictYet }
        return language.today.engineCompactText(
            verdict: readiness.verdict,
            ruleCodes: readiness.ruleIDs.map(\.code)
        )
    }
}

struct CoachTodayEngineHeader: View {
    let readiness: DailyReadiness?
    @AppStorage(CoachLanguage.storageKey) private var languageRaw = CoachLanguage.en.rawValue
    @State private var showsRationale = false

    private var language: CoachLanguage {
        CoachLanguage(rawValue: languageRaw) ?? .en
    }

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
                    Text(CoachTodayHeaderText.text(for: readiness, language: language))
                        .fixedSize(horizontal: true, vertical: false)
                    Text(CoachTodayHeaderText.compactText(for: readiness, language: language))
                        .fixedSize(horizontal: true, vertical: false)
                    Text(readiness.map { language.verdictWord($0.verdict) } ?? language.today.noVerdictYet)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)

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
            CoachTodayRationaleSheet(readiness: readiness, language: language)
        }
    }

    private var accessibilityLabel: String {
        language.today.engineAccessibility(
            verdict: readiness?.verdict,
            ruleCodes: readiness?.ruleIDs.map(\.code) ?? []
        )
    }
}

private struct CoachTodayRationaleSheet: View {
    let readiness: DailyReadiness?
    let language: CoachLanguage

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
                        CoachRationaleCard(rationale: ReadinessRationale(from: readiness), language: language)

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
                                Text(language.today.noReadinessOutput)
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
        guard let readiness else { return language.today.noVerdictYet }
        return "\(language.today.engine) · \(language.verdictWord(readiness.verdict))"
    }

    private var subtitle: String {
        guard let readiness else {
            return language.today.noTimestampAvailable
        }
        return language.today.computedAt(readiness.computedAt)
    }

    private var ruleRows: [ReceiptSheet.Row] {
        guard let readiness else { return [] }
        var rows = readiness.ruleIDs.map { id in
            ReceiptSheet.Row.detail(
                language.today.ruleLabel(id),
                value: language.today.ruleDetail(id),
                symbol: "checkmark.seal"
            )
        }
        if rows.isEmpty {
            rows.append(.detail(language.today.rules, value: language.today.noRulesFired, symbol: "checkmark.seal"))
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
