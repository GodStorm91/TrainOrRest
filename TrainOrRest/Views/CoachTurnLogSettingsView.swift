import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Hands the recent Coach turn record to the person using the app so they can
/// attach it to a bug report. The screen builds the JSON once, shows a preview,
/// and offers a copy and a file share.
struct CoachTurnLogSettingsView: View {
    @AppStorage(CoachLanguage.storageKey) private var languageRaw = CoachLanguage.en.rawValue
    @Environment(\.modelContext) private var modelContext

    @State private var report = ""
    @State private var turnCount = 0
    @State private var file: CoachTurnLogFile?

    private var language: CoachLanguage { CoachLanguage(rawValue: languageRaw) ?? .en }
    private var copy: SettingsCopy { language.settings }

    var body: some View {
        Form {
            Section {
                Button {
                    UIPasteboard.general.string = report
                } label: {
                    Label(copy.copyCoachTurnLog, systemImage: "doc.on.doc")
                }
                if let file {
                    ShareLink(item: file, preview: SharePreview(file.name)) {
                        Label(copy.shareCoachTurnLog, systemImage: "square.and.arrow.up")
                    }
                }
            } header: {
                Text(copy.coachTurnLogCount(turnCount))
            } footer: {
                Text(copy.coachTurnLogFooter)
            }

            if !report.isEmpty {
                Section {
                    DebugReportView(text: String(report.prefix(6_000)))
                }
            }
        }
        .navigationTitle(copy.coachTurnLogTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            build()
        }
    }

    private func build() {
        report = CoachTurnReport.bundle(in: modelContext)
        turnCount = CoachTurnReport.recordedTurnCount(in: modelContext)
        file = CoachTurnLogFile(contents: report)
    }
}

/// Writes the report to a temporary `.json` file so `ShareLink` can hand over a
/// real document instead of a wall of text.
struct CoachTurnLogFile: Transferable {
    let name: String
    let url: URL

    init?(contents: String) {
        let stamp = CoachTurnLogFile.stampFormatter.string(from: .now)
        let name = "trainorrest-coach-turns-\(stamp).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        guard (try? contents.write(to: url, atomically: true, encoding: .utf8)) != nil else { return nil }
        self.name = name
        self.url = url
    }

    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return formatter
    }()

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) {
            SentTransferredFile($0.url)
        }
    }
}
