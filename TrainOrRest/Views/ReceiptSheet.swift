import SwiftUI

/// Shared provenance receipt for AI edits, deterministic rule adjustments, and source conflicts.
struct ReceiptSheet: View {
    struct Row: Identifiable, Equatable {
        enum Kind: Equatable {
            case check
            case detail
        }

        let id = UUID()
        let kind: Kind
        let label: String
        let value: String
        let symbol: String?

        init(kind: Kind = .detail, label: String, value: String, symbol: String? = nil) {
            self.kind = kind
            self.label = label
            self.value = value
            self.symbol = symbol
        }

        static func check(_ label: String, value: String, symbol: String? = "checkmark.circle") -> Row {
            Row(kind: .check, label: label, value: value, symbol: symbol)
        }

        static func detail(_ label: String, value: String, symbol: String? = nil) -> Row {
            Row(kind: .detail, label: label, value: value, symbol: symbol)
        }
    }

    let title: String
    let subtitle: String?
    let rows: [Row]

    init(title: String, subtitle: String? = nil, rows: [Row]) {
        self.title = title
        self.subtitle = subtitle
        self.rows = rows
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(.system(.title2, design: .rounded).weight(.semibold))
                            .foregroundStyle(Theme.text)

                        if let subtitle {
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(Theme.dim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    TorCard(padding: 0, cornerRadius: 16) {
                        VStack(spacing: 0) {
                            ForEach(rows) { row in
                                ReceiptRowView(row: row)
                                if row.id != rows.last?.id {
                                    Rectangle()
                                        .fill(Theme.line)
                                        .frame(height: 1)
                                        .padding(.leading, 46)
                                }
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
}

private struct ReceiptRowView: View {
    let row: ReceiptSheet.Row

    private var tint: Color {
        row.kind == .check ? Theme.good : Theme.accent
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: row.symbol ?? fallbackSymbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(Theme.soft(tint), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
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

    private var fallbackSymbol: String {
        row.kind == .check ? "checkmark.circle" : "info.circle"
    }
}
