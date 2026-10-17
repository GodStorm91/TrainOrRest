import Foundation
import SwiftData
import SwiftUI

struct RaceDetailView: View {
    let race: RaceSpec
    let language: CoachLanguage

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var finishTime: String
    @State private var isRecordingResult = false
    @State private var isConfirmingDeletion = false

    private let calendar = Calendar.current

    init(race: RaceSpec, language: CoachLanguage) {
        self.race = race
        self.language = language
        _finishTime = State(initialValue: race.result.map { Self.timeText($0.finishTimeSeconds) } ?? "")
    }

    var body: some View {
        AddRaceSheet(
            editing: race,
            language: language,
            onCancel: { dismiss() },
            onConfirm: save,
            onRecordResult: { isRecordingResult = true },
            onDelete: { isConfirmingDeletion = true }
        )
        .alert(language.season.finishTime, isPresented: $isRecordingResult) {
            TextField(language.season.finishTime, text: $finishTime)
                .keyboardType(.numbersAndPunctuation)
            Button(language.season.cancel, role: .cancel) {}
            Button(language.season.save) {
                recordResult()
            }
            .disabled(finishTimeSeconds == nil)
        }
        .confirmationDialog(
            language.season.deleteRaceConfirm,
            isPresented: $isConfirmingDeletion,
            titleVisibility: .visible
        ) {
            Button(language.season.deleteRace, role: .destructive) {
                deleteRace()
            }
            Button(language.season.cancel, role: .cancel) {}
        }
    }

    private var finishTimeSeconds: Double? {
        let pieces = finishTime
            .split(separator: ":")
            .compactMap { Int($0) }
        guard pieces.count == finishTime.split(separator: ":").count,
              !pieces.isEmpty,
              pieces.allSatisfy({ $0 >= 0 })
        else {
            return nil
        }

        switch pieces.count {
        case 1:
            return Double(pieces[0])
        case 2:
            guard pieces[1] < 60 else { return nil }
            return Double(pieces[0] * 60 + pieces[1])
        case 3:
            guard pieces[1] < 60, pieces[2] < 60 else { return nil }
            return Double(pieces[0] * 3_600 + pieces[1] * 60 + pieces[2])
        default:
            return nil
        }
    }

    private func save(_ spec: RaceSpec) {
        do {
            try RaceSeasonStore.update(id: race.id, to: spec, in: modelContext, now: .now)
            try RaceSeasonStore.syncGoalToARace(in: modelContext, calendar: calendar)
            try applySeasonSchedule(summary: spec.name)
        } catch {
            return
        }
    }

    private func recordResult() {
        guard let finishTimeSeconds else { return }
        do {
            try RaceSeasonStore.recordResult(
                id: race.id,
                result: RaceResultSpec(finishTimeSeconds: finishTimeSeconds),
                in: modelContext,
                now: .now
            )
            dismiss()
        } catch {
            return
        }
    }

    private func deleteRace() {
        do {
            try RaceSeasonStore.remove(id: race.id, in: modelContext)
            dismiss()
        } catch {
            return
        }
    }

    private func applySeasonSchedule(summary: String) throws {
        let season = try RaceSeasonStore.season(in: modelContext)
        let change = try RacePlanApplier.preview(
            in: modelContext,
            races: season.races,
            today: .now,
            calendar: calendar
        )
        _ = try RacePlanApplier.apply(
            change,
            in: modelContext,
            today: .now,
            calendar: calendar,
            summary: summary
        )
    }

    private static func timeText(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%02d:%02d:%02d", total / 3_600, (total % 3_600) / 60, total % 60)
    }
}
