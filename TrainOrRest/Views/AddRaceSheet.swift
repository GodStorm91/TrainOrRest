import Foundation
import SwiftData
import SwiftUI

struct AddRaceSheet: View {
    var editing: RaceSpec? = nil
    let language: CoachLanguage
    var onCancel: () -> Void
    var onConfirm: (RaceSpec) -> Void
    var onRecordResult: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var raceID: UUID
    @State private var raceName: String
    @State private var raceDate: Date
    @State private var standardDistance: RaceDistance?
    @State private var customKilometers: String
    @State private var targetHours: Int
    @State private var targetMinutes: Int
    @State private var targetSeconds: Int
    @State private var priority: RacePriority
    @State private var didInitialize = false
    @State private var existingAName: String?
    @State private var isConfirmingDemotion = false

    private let calendar = Calendar.current

    init(
        editing: RaceSpec? = nil,
        language: CoachLanguage,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping (RaceSpec) -> Void,
        onRecordResult: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil
    ) {
        self.editing = editing
        self.language = language
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        self.onRecordResult = onRecordResult
        self.onDelete = onDelete

        let targetTime = Int((editing?.targetTimeSeconds ?? 0).rounded())
        _raceID = State(initialValue: editing?.id ?? UUID())
        _raceName = State(initialValue: editing?.name ?? "")
        _raceDate = State(initialValue: editing?.date ?? Calendar.current.date(byAdding: .weekOfYear, value: 12, to: .now) ?? .now)
        _standardDistance = State(initialValue: editing.flatMap { RaceDistance.matching(meters: $0.distanceMeters) } ?? (editing == nil ? .halfMarathon : nil))
        _customKilometers = State(initialValue: editing.map { String($0.kilometers) } ?? "")
        _targetHours = State(initialValue: targetTime / 3_600)
        _targetMinutes = State(initialValue: (targetTime % 3_600) / 60)
        _targetSeconds = State(initialValue: targetTime % 60)
        _priority = State(initialValue: editing?.priority ?? .a)
    }

    var body: some View {
        NavigationStack {
            Form {
                detailsSection
                distanceSection
                targetSection
                prioritySection
                previewSection
                additionalActions
                actionsSection
            }
            .navigationTitle(editing == nil ? language.season.addRaceTitle : language.season.raceDetailTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            guard !didInitialize else { return }
            didInitialize = true
            if editing == nil {
                priority = suggestion.priority
            }
        }
        .alert(language.season.demoteExistingATitle, isPresented: $isConfirmingDemotion) {
            Button(language.season.cancel, role: .cancel) {
                existingAName = nil
            }
            Button(primaryTitle) {
                submit()
            }
        } message: {
            if let existingAName {
                Text(language.season.demoteExistingA(existingAName))
            }
        }
    }

    private var detailsSection: some View {
        Section {
            TextField(language.season.raceName, text: $raceName)
                .textInputAutocapitalization(.words)
            DatePicker(
                language.season.raceDate,
                selection: $raceDate,
                in: dateRange,
                displayedComponents: .date
            )
            .environment(\.locale, language.uiLocale)
        }
    }

    private var distanceSection: some View {
        Section(language.season.raceDistance) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(RaceDistance.allCases) { distance in
                        distanceChip(
                            title: distance.displayName,
                            isSelected: standardDistance == distance
                        ) {
                            standardDistance = distance
                        }
                    }
                    distanceChip(
                        title: language.season.custom,
                        isSelected: standardDistance == nil
                    ) {
                        standardDistance = nil
                        if customKilometers.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            customKilometers = String(RaceDistance.fiveK.kilometers)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            if standardDistance == nil {
                TextField(language.season.raceDistance, text: $customKilometers)
                    .keyboardType(.decimalPad)
            }
        }
    }

    private var targetSection: some View {
        Section(language.season.raceTargetOptional) {
            HStack {
                Picker(language.settings.hours, selection: $targetHours) {
                    ForEach(0..<24, id: \.self) { value in
                        Text(language.settings.hourPickerValue(value)).tag(value)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)

                Picker(language.settings.minutes, selection: $targetMinutes) {
                    ForEach(0..<60, id: \.self) { value in
                        Text(language.settings.minutePickerValue(value)).tag(value)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)

                Picker(language.settings.secondsAbbreviation, selection: $targetSeconds) {
                    ForEach(0..<60, id: \.self) { value in
                        Text(String(format: "%02d", locale: language.uiLocale, value)).tag(value)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            .tint(Theme.accent)
        }
    }

    private var prioritySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(RacePriority.allCases, id: \.rawValue) { candidate in
                    Button {
                        priority = candidate
                    } label: {
                        HStack(spacing: 10) {
                            RacePriorityBadge(priority: candidate)
                                .accessibilityHidden(true)
                            Text(priorityTitle(candidate))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.text)
                            Spacer()
                            if priority == candidate {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Theme.accent)
                                    .accessibilityHidden(true)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(priority == candidate ? Theme.accentSoft : Theme.card2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(priority == candidate ? Theme.accent : Theme.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(priorityTitle(candidate))
                    .accessibilityAddTraits(priority == candidate ? .isSelected : [])
                }
                Text(language.season.prioritySuggestion(
                    suggestion.priority,
                    reason: suggestion.reason,
                    weeks: suggestion.weeksToARace
                ))
                .font(.footnote)
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text(language.season.raceTypeSection)
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.dim)
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        if !racePreview.dayChanges.isEmpty {
            Section {
                Text(language.season.schedulePreview(
                    miniTaperDays: RaceTaperTable.miniTaperDays,
                    miniTaperRange: miniTaperRange,
                    recoveryDays: RaceTaperTable.recoveryDays(
                        meters: distanceMeters,
                        priority: priority
                    )
                ))
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.warn)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.soft(Theme.warn, 0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private var additionalActions: some View {
        if let onRecordResult {
            Section {
                Button(language.season.recordResult, action: onRecordResult)
                    .foregroundStyle(Theme.accent)
                    .accessibilityLabel(language.season.recordResult)
            }
        }
        if let onDelete {
            Section {
                Button(language.season.deleteRace, role: .destructive, action: onDelete)
                    .foregroundStyle(Theme.bad)
                    .accessibilityLabel(language.season.deleteRace)
            }
        }
    }

    private var actionsSection: some View {
        Section {
            VStack(spacing: 8) {
                Button(action: requestConfirmation) {
                    Text(primaryTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(canConfirm ? .white : Theme.faint)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(canConfirm ? Theme.accent : Theme.faint.opacity(0.55), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canConfirm)
                .accessibilityLabel(primaryTitle)

                Button(language.season.cancel, action: cancel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .buttonStyle(.plain)
                    .accessibilityLabel(language.season.cancel)
            }
            .frame(maxWidth: .infinity)
        }
        .listRowBackground(Color.clear)
    }

    private var dateRange: ClosedRange<Date> {
        let lowerBound = editing == nil ? calendar.startOfDay(for: .now) : .distantPast
        return lowerBound...Date.distantFuture
    }

    private var distanceMeters: Double {
        standardDistance?.meters ?? (Double(customKilometers.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0) * 1_000
    }

    private var targetTimeSeconds: Double {
        Double(targetHours * 3_600 + targetMinutes * 60 + targetSeconds)
    }

    private var currentSpec: RaceSpec {
        RaceSpec(
            id: raceID,
            name: raceName.trimmingCharacters(in: .whitespacesAndNewlines),
            date: calendar.startOfDay(for: raceDate),
            distanceMeters: distanceMeters,
            targetTimeSeconds: targetTimeSeconds > 0 ? targetTimeSeconds : nil,
            priority: priority,
            status: editing?.status ?? .upcoming,
            result: editing?.result
        )
    }

    private var storedRaceSpecs: [RaceSpec] {
        ((try? RaceSeasonStore.season(in: modelContext))?.races ?? [])
            .filter { $0.id != raceID }
    }

    private var suggestion: RacePrioritySuggestion {
        RaceScheduler.suggestPriority(
            for: raceDate,
            races: storedRaceSpecs,
            today: .now,
            calendar: calendar
        )
    }

    private var racePreview: RaceScheduleChange {
        guard distanceMeters > 0,
              let change = try? RacePlanApplier.preview(
                in: modelContext,
                races: storedRaceSpecs + [currentSpec],
                today: .now,
                calendar: calendar
              )
        else {
            return .empty
        }
        return RaceScheduleChange(
            dayChanges: change.dayChanges.filter { $0.raceID == raceID },
            warnings: change.warnings
        )
    }

    private var miniTaperRange: String {
        let start = calendar.date(
            byAdding: .day,
            value: -RaceTaperTable.miniTaperDays,
            to: calendar.startOfDay(for: raceDate)
        ) ?? raceDate
        let end = calendar.date(byAdding: .day, value: -1, to: raceDate) ?? raceDate
        return "\(language.shortDate(start)) - \(language.shortDate(end))"
    }

    private var canConfirm: Bool {
        !currentSpec.name.isEmpty && distanceMeters > 0
    }

    private var primaryTitle: String {
        editing == nil ? language.season.addToSeason : language.season.save
    }

    private func distanceChip(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? Theme.accent : Theme.dim)
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .background(isSelected ? Theme.accentSoft : Theme.chip, in: Capsule())
                .overlay(Capsule().strokeBorder(isSelected ? Theme.accent : Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func priorityTitle(_ priority: RacePriority) -> String {
        switch priority {
        case .a: language.season.priorityATitle
        case .b: language.season.priorityBTitle
        case .c: language.season.priorityCTitle
        }
    }

    private func requestConfirmation() {
        guard currentSpec.priority == .a,
              let existing = try? RaceSeasonStore.existingARace(in: modelContext),
              existing.id != raceID
        else {
            submit()
            return
        }
        existingAName = existing.name
        isConfirmingDemotion = true
    }

    private func submit() {
        onConfirm(currentSpec)
        dismiss()
    }

    private func cancel() {
        onCancel()
        dismiss()
    }
}
