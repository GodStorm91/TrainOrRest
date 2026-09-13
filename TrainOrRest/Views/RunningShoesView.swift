import SwiftData
import SwiftUI

struct RunningShoesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \RunningShoe.createdAt, order: .reverse) private var shoes: [RunningShoe]
    @Query private var mileageEntries: [ShoeMileageEntry]
    @Query(sort: \PlannedWorkout.date) private var workouts: [PlannedWorkout]
    @Query private var storedPreferences: [RunningShoePreferences]

    @State private var showingAddShoe = false
    @State private var showingSettings = false

    @AppStorage(CoachLanguage.storageKey) private var languageRaw = CoachLanguage.en.rawValue

    private var language: CoachLanguage { CoachLanguage(rawValue: languageRaw) ?? .en }

    private var activeShoes: [RunningShoe] {
        shoes
            .filter { $0.status == .active }
            .sorted {
                let left = wearPriority(for: $0)
                let right = wearPriority(for: $1)
                if left != right { return left > right }
                return $0.createdAt > $1.createdAt
            }
    }
    private var retiredShoes: [RunningShoe] { shoes.filter { $0.status == .retired } }
    private var preferences: RunningShoePreferences? { storedPreferences.first }
    private var totalActiveMileageKm: Double { activeShoes.map(mileage).reduce(0, +) }
    private var upcomingWorkout: PlannedWorkout? {
        let today = Calendar.current.startOfDay(for: .now)
        return workouts.first { $0.status == .planned && $0.date >= today }
    }
    private var attentionShoe: RunningShoe? {
        activeShoes.first {
            let status = ShoeWearStatusService.wearStatus(
                currentMileageKm: mileage(for: $0),
                expectedLifespanKm: $0.expectedLifespanKm
            )
            return status == .inspect || status == .pastRange
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if shoes.isEmpty {
                    emptyState
                } else {
                    rotationOverview
                    if let attentionShoe {
                        attentionBanner(for: attentionShoe)
                    }
                    shoeSection(language.integrations.active, shoes: activeShoes)
                    if !retiredShoes.isEmpty {
                        DisclosureGroup(language.integrations.retiredShoes(retiredShoes.count)) {
                            VStack(spacing: 10) {
                                ForEach(retiredShoes, id: \.id) { shoe in
                                    NavigationLink { ShoeDetailView(shoe: shoe) } label: {
                                        RunningShoeRow(shoe: shoe, mileageKm: mileage(for: shoe), isRetired: true)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.top, 10)
                        }
                        .font(.torHeading(16, .bold))
                        .foregroundStyle(Theme.text)
                    }
                }

                Button {
                    showingAddShoe = true
                } label: {
                    Label(shoes.isEmpty ? language.integrations.addYourFirstShoe : language.integrations.addShoe, systemImage: "plus")
                        .font(.torHeading(15, .bold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            }
            .padding(.horizontal, TorLayout.screenGutter(horizontalSizeClass))
            .padding(.vertical, 16)
            .padding(.bottom, 86)
            .torReadableColumn()
        }
        .background(Theme.bg)
        .navigationTitle(language.integrations.runningShoes)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel(language.integrations.shoeAssignmentSettings)
            }
        }
        .sheet(isPresented: $showingAddShoe) {
            NavigationStack {
                ShoeFormView(mode: .add) { shoe in
                    modelContext.insert(shoe)
                    try? ShoeAssignmentService.reassignFutureAutomaticWorkouts(in: modelContext)
                    try? modelContext.save()
                    Task { await ShoeWearNotifier.notifyIfNeeded(in: modelContext) }
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                ShoeAssignmentSettingsView()
            }
        }
    }

    private var emptyState: some View {
        TorCard {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "shoeprints.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text(language.integrations.shoeMileageEmptyState)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var rotationOverview: some View {
        TorCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Label(language.integrations.automaticRotation, systemImage: "arrow.triangle.2.circlepath")
                        .font(.headline)
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Text((preferences?.shoeAutoAssignmentEnabled ?? true)
                        ? language.integrations.automaticRotationOn
                        : language.integrations.automaticRotationOff)
                        .font(.caption.weight(.bold))
                        .foregroundStyle((preferences?.shoeAutoAssignmentEnabled ?? true) ? Theme.good : Theme.faint)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Theme.chip, in: Capsule())
                }

                Text(language.integrations.automaticMileageExplanation)
                    .font(.subheadline)
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Label(language.integrations.activeShoeCount(activeShoes.count), systemImage: "shoeprints.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.text)
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Formatters.kilometers(totalActiveMileageKm * 1000))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.text)
                            .monospacedDigit()
                        Text(language.integrations.totalLogged)
                            .font(.caption)
                            .foregroundStyle(Theme.dim)
                    }
                }

                if let workout = upcomingWorkout,
                   let kind = workout.kind,
                   let shoeID = workout.shoeID,
                   let shoe = shoes.first(where: { $0.id == shoeID }) {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text(language.integrations.nextShoeAssignment)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.dim)
                        Text(language.integrations.shoeAssignedForWorkout(
                            shoe.displayName,
                            workoutName: language.name(kind)
                        ))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.text)
                        Text(workout.date.formatted(
                            .dateTime.weekday(.abbreviated).month(.abbreviated).day().locale(language.uiLocale)
                        ))
                            .font(.caption)
                            .foregroundStyle(Theme.faint)
                    }
                }
            }
        }
    }

    private func attentionBanner(for shoe: RunningShoe) -> some View {
        let mileageKm = mileage(for: shoe)
        let status = ShoeWearStatusService.wearStatus(
            currentMileageKm: mileageKm,
            expectedLifespanKm: shoe.expectedLifespanKm
        )
        return NavigationLink {
            ShoeDetailView(shoe: shoe)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: status == .pastRange ? "exclamationmark.triangle.fill" : "wrench.and.screwdriver.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.warn)
                    .frame(width: 32, height: 32)
                    .background(Theme.soft(Theme.warn), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(status == .pastRange
                        ? language.integrations.shoeReplacementReminderTitle(shoe.displayName)
                        : language.integrations.shoeInspectionReminderTitle(shoe.displayName))
                        .font(.headline)
                        .foregroundStyle(Theme.text)
                    Text(status == .pastRange
                        ? language.integrations.pastRangeMessage
                        : language.integrations.inspectShoeMessage)
                        .font(.caption)
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.faint)
                    .padding(.top, 4)
            }
            .padding(14)
            .background(Theme.soft(Theme.warn), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.warn.opacity(0.28), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func shoeSection(_ title: String, shoes: [RunningShoe]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TorEyebrow(title).tracking(2)
            if shoes.isEmpty {
                Text(language.integrations.noActiveShoes)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 10) {
                    ForEach(shoes, id: \.id) { shoe in
                        NavigationLink { ShoeDetailView(shoe: shoe) } label: {
                            RunningShoeRow(shoe: shoe, mileageKm: mileage(for: shoe), isRetired: false)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func mileage(for shoe: RunningShoe) -> Double {
        ShoeMileageService.currentMileageKm(for: shoe, ledger: mileageEntries)
    }

    private func wearPriority(for shoe: RunningShoe) -> Int {
        switch ShoeWearStatusService.wearStatus(
            currentMileageKm: mileage(for: shoe),
            expectedLifespanKm: shoe.expectedLifespanKm
        ) {
        case .normal: 0
        case .approaching: 1
        case .inspect: 2
        case .pastRange: 3
        }
    }
}

struct RunningShoeRow: View {
    let shoe: RunningShoe
    let mileageKm: Double
    let isRetired: Bool
    @AppStorage(CoachLanguage.storageKey) private var languageRaw = CoachLanguage.en.rawValue

    private var language: CoachLanguage { CoachLanguage(rawValue: languageRaw) ?? .en }


    private var wearStatus: ShoeWearStatus {
        ShoeWearStatusService.wearStatus(currentMileageKm: mileageKm, expectedLifespanKm: shoe.expectedLifespanKm)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "shoeprints.fill")
                    .font(.headline)
                    .foregroundStyle(wearColor)
                    .frame(width: 38, height: 38)
                    .background(Theme.soft(wearColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(shoe.displayName)
                        .font(.headline)
                        .foregroundStyle(isRetired ? Theme.faint : Theme.text)
                    Text(language.integrations.shoeTypes(shoe.preferredWorkoutTypes))
                        .font(.subheadline)
                        .foregroundStyle(Theme.dim)
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.faint)
            }

            ProgressView(value: mileageProgress)
                .tint(wearColor)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(language.integrations.mileageProgress(
                    current: Formatters.kilometers(mileageKm * 1000),
                    expected: Formatters.kilometers(shoe.expectedLifespanKm * 1000)
                ))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.dim)
                Spacer(minLength: 4)
                if let warningText {
                    Text(warningText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(wearColor)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        .opacity(isRetired ? 0.62 : 1)
    }

    private var mileageProgress: Double {
        guard shoe.expectedLifespanKm > 0 else { return 0 }
        return min(mileageKm / shoe.expectedLifespanKm, 1)
    }

    private var warningText: String? {
        switch wearStatus {
        case .normal: nil
        case .approaching: language.integrations.approachingShort
        case .inspect: language.integrations.checkSoon
        case .pastRange: language.integrations.pastTypicalRange
        }
    }

    private var wearColor: Color {
        switch wearStatus {
        case .normal: Theme.dim
        case .approaching, .inspect, .pastRange: Theme.warn
        }
    }
}

struct ShoeMileageIndicator: View {
    let mileageKm: Double
    let expectedKm: Double

    @AppStorage(CoachLanguage.storageKey) private var languageRaw = CoachLanguage.en.rawValue

    private var language: CoachLanguage { CoachLanguage(rawValue: languageRaw) ?? .en }

    private var progress: Double {
        guard expectedKm > 0 else { return 0 }
        return min(mileageKm / expectedKm, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: progress)
                .tint(ShoeWearStatusService.wearStatus(currentMileageKm: mileageKm, expectedLifespanKm: expectedKm) == .normal ? Theme.accent : Theme.warn)
            Text(language.integrations.kilometersLogged(Formatters.kilometers(mileageKm * 1000)))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
            if mileageKm < expectedKm {
                Text(language.integrations.kilometersUntilRecommendedRange(Formatters.kilometers((expectedKm - mileageKm) * 1000)))
                    .font(.caption)
                    .foregroundStyle(Theme.dim)
            }
        }
    }
}

struct ShoeDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var shoe: RunningShoe
    @Query private var mileageEntries: [ShoeMileageEntry]
    @Query(sort: \CompletedActivity.date, order: .reverse) private var activities: [CompletedActivity]

    @State private var showingEdit = false
    @State private var isConfirmingRetire = false
    @AppStorage(CoachLanguage.storageKey) private var languageRaw = CoachLanguage.en.rawValue

    private var language: CoachLanguage { CoachLanguage(rawValue: languageRaw) ?? .en }


    private var entries: [ShoeMileageEntry] { mileageEntries.filter { $0.shoeID == shoe.id } }
    private var mileageKm: Double { ShoeMileageService.currentMileageKm(for: shoe, ledger: mileageEntries) }
    private var shoeActivities: [CompletedActivity] {
        let ids = Set(entries.map(\.activityID))
        return activities.filter { ids.contains($0.hkUUID) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TorCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(shoe.brand.isEmpty ? language.integrations.runningShoe : shoe.brand)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.dim)
                        Text(shoe.model.isEmpty ? shoe.displayName : shoe.model)
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(Theme.text)
                        Text(Formatters.kilometers(mileageKm * 1000))
                            .font(.largeTitle.weight(.bold).monospacedDigit())
                            .foregroundStyle(Theme.text)
                        Text(language.integrations.shoeStatus(shoe.status))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(shoe.status == .active ? Theme.good : Theme.faint)
                    }
                }

                detailSection(language.integrations.mileage) {
                    ShoeMileageIndicator(mileageKm: mileageKm, expectedKm: shoe.expectedLifespanKm)
                    MileageWarning(shoe: shoe, mileageKm: mileageKm)
                }

                detailSection(language.integrations.usage) {
                    ShoeMetricRow(label: language.integrations.runs, value: "\(shoeActivities.count)")
                    ShoeMetricRow(label: language.integrations.distance, value: Formatters.kilometers(mileageKm * 1000))
                    if let last = shoeActivities.first {
                        ShoeMetricRow(
                            label: language.integrations.lastRun,
                            value: "\(last.date.formatted(.dateTime.month(.abbreviated).day().locale(language.uiLocale))) · \(Formatters.kilometers(last.distanceMeters))"
                        )
                    }
                }

                detailSection(language.integrations.preferences) {
                    ShoeMetricRow(label: language.integrations.preferredFor, value: language.integrations.shoeTypes(shoe.preferredWorkoutTypes))
                    ShoeMetricRow(label: language.integrations.primary, value: shoe.primaryWorkoutType.map(language.integrations.shoeWorkoutType) ?? language.integrations.anyRun)
                }

                detailSection(language.integrations.purchase) {
                    ShoeMetricRow(label: language.integrations.purchased, value: shoe.purchaseDate?.formatted(.dateTime.month(.abbreviated).day().locale(language.uiLocale)) ?? language.integrations.notSet)
                    ShoeMetricRow(label: language.integrations.startingMileage, value: Formatters.kilometers(shoe.initialMileageKm * 1000))
                }

                VStack(spacing: 10) {
                    Button { showingEdit = true } label: {
                        Label(language.editLabel, systemImage: "pencil")
                            .frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .buttonStyle(.bordered)

                    Button(role: shoe.status == .active ? .destructive : nil) {
                        if shoe.status == .active {
                            isConfirmingRetire = true
                        } else {
                            toggleStatus()
                        }
                    } label: {
                        Label(shoe.status == .active ? language.integrations.retireShoe : language.integrations.reactivateShoe, systemImage: shoe.status == .active ? "archivebox" : "arrow.uturn.backward")
                            .frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(16)
            .padding(.bottom, 86)
        }
        .background(Theme.bg)
        .navigationTitle(shoe.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingEdit) {
            NavigationStack {
                ShoeFormView(mode: .edit(shoe)) { _ in
                    try? ShoeAssignmentService.reassignFutureAutomaticWorkouts(in: modelContext)
                    try? modelContext.save()
                    Task { await ShoeWearNotifier.notifyIfNeeded(in: modelContext) }
                }
            }
        }
        .confirmationDialog(
            language.integrations.retireShoeQuestion,
            isPresented: $isConfirmingRetire,
            titleVisibility: .visible
        ) {
            Button(language.integrations.retireShoe, role: .destructive) {
                toggleStatus()
            }
            Button(language.cancelLabel, role: .cancel) {}
        } message: {
            Text(language.integrations.retireShoeMessage(shoe.displayName))
        }
    }

    private func detailSection<Content: View>(_ title: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        TorCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                content()
            }
        }
    }

    private func toggleStatus() {
        shoe.status = shoe.status == .active ? .retired : .active
        try? ShoeAssignmentService.reassignFutureAutomaticWorkouts(in: modelContext)
        try? modelContext.save()
    }
}

private struct ShoeMetricRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.dim)
            Spacer(minLength: 16)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct MileageWarning: View {
    let shoe: RunningShoe
    let mileageKm: Double
    @AppStorage(CoachLanguage.storageKey) private var languageRaw = CoachLanguage.en.rawValue

    private var language: CoachLanguage { CoachLanguage(rawValue: languageRaw) ?? .en }


    private var status: ShoeWearStatus {
        ShoeWearStatusService.wearStatus(currentMileageKm: mileageKm, expectedLifespanKm: shoe.expectedLifespanKm)
    }

    var body: some View {
        switch status {
        case .normal:
            EmptyView()
        case .approaching:
            warning(language.integrations.approachingRecommendedMileage, language.integrations.noActionNeededYet)
        case .inspect:
            warning(language.integrations.checkShoe(shoe.displayName), language.integrations.inspectShoeMessage)
        case .pastRange:
            warning(language.integrations.pastTypicalRange, language.integrations.pastRangeMessage)
        }
    }

    private func warning(_ title: String, _ copy: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.warn)
            Text(copy)
                .font(.caption)
                .foregroundStyle(Theme.dim)
        }
        .padding(12)
        .background(Theme.soft(Theme.warn), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

enum ShoeFormMode {
    case add
    case edit(RunningShoe)
}

struct ShoeFormView: View {
    @Environment(\.dismiss) private var dismiss
    let mode: ShoeFormMode
    let onSave: (RunningShoe) -> Void

    @State private var step = 0
    @State private var brand = ""
    @State private var model = ""
    @State private var nickname = ""
    @State private var purchaseDate = Date()
    @State private var hasPurchaseDate = true
    @State private var startingMileage = 0.0
    @State private var selectedTypes: Set<ShoeWorkoutType> = [.easy]
    @State private var primaryType: ShoeWorkoutType = .easy
    @State private var expectedLifespan = 600.0
    @AppStorage(CoachLanguage.storageKey) private var languageRaw = CoachLanguage.en.rawValue

    private var language: CoachLanguage { CoachLanguage(rawValue: languageRaw) ?? .en }


    private var editingShoe: RunningShoe? {
        if case let .edit(shoe) = mode { return shoe }
        return nil
    }

    var body: some View {
        Form {
            if step == 0 {
                Section(language.integrations.basicInformation) {
                    TextField(language.integrations.brand, text: $brand)
                    TextField(language.integrations.model, text: $model)
                    TextField(language.integrations.nickname, text: $nickname)
                    Toggle(language.integrations.setPurchaseDate, isOn: $hasPurchaseDate)
                    if hasPurchaseDate {
                        DatePicker(language.integrations.purchaseDate, selection: $purchaseDate, displayedComponents: .date)
                    }
                    Stepper(language.integrations.startingMileageValue(Formatters.kilometers(startingMileage * 1000)), value: $startingMileage, in: 0...5000, step: 5)
                }
            } else if step == 1 {
                Section(language.integrations.shoeUsageQuestion) {
                    ShoeUsageTypeSelector(selectedTypes: $selectedTypes)
                }
                Section(language.integrations.primaryUse) {
                    Picker(language.integrations.primaryUse, selection: $primaryType) {
                        ForEach(Array(selectedTypes).sorted(by: { language.integrations.shoeWorkoutType($0) < language.integrations.shoeWorkoutType($1) }), id: \.self) { type in
                            Text(language.integrations.shoeWorkoutType(type)).tag(type)
                        }
                    }
                }
            } else {
                Section(language.integrations.mileage) {
                    Stepper(language.integrations.expectedLifespanValue(Formatters.kilometers(expectedLifespan * 1000)), value: $expectedLifespan, in: 100...1200, step: 50)
                    Text(language.integrations.adjustAnytime)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(language.integrations.mileageUpdatesAfterSync)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .environment(\.locale, language.uiLocale)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if step == 0 {
                    Button(language.cancelLabel) { dismiss() }
                } else {
                    Button(language.backLabel) { step -= 1 }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(step == 2 ? language.saveLabel : language.integrations.next) {
                    if step < 2 {
                        advance()
                    } else {
                        save()
                    }
                }
                .disabled(!canContinue)
            }
        }
        .onAppear(perform: hydrate)
        .onChange(of: selectedTypes) { _, newValue in
            if newValue.isEmpty {
                selectedTypes = [.easy]
                primaryType = .easy
            } else if !newValue.contains(primaryType) {
                primaryType = newValue.sorted(by: { language.integrations.shoeWorkoutType($0) < language.integrations.shoeWorkoutType($1) }).first ?? .easy
            } else if newValue.count == 1, let only = newValue.first {
                primaryType = only
            }
        }
    }

    private var title: String {
        let base: String
        switch mode {
        case .add: base = language.integrations.addShoe
        case .edit: base = language.editLabel
        }
        return language.integrations.shoeFormTitle(base, step: step + 1, of: 3)
    }

    private var canContinue: Bool {
        step > 0 || (!brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func advance() {
        if selectedTypes.count == 1, let only = selectedTypes.first {
            primaryType = only
        }
        step += 1
    }

    private func hydrate() {
        guard let shoe = editingShoe else { return }
        brand = shoe.brand
        model = shoe.model
        nickname = shoe.nickname ?? ""
        hasPurchaseDate = shoe.purchaseDate != nil
        purchaseDate = shoe.purchaseDate ?? .now
        startingMileage = shoe.initialMileageKm
        selectedTypes = Set(shoe.preferredWorkoutTypes.isEmpty ? [.easy] : shoe.preferredWorkoutTypes)
        primaryType = shoe.primaryWorkoutType ?? selectedTypes.first ?? .easy
        expectedLifespan = shoe.expectedLifespanKm
    }

    private func save() {
        let cleanNickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = editingShoe ?? RunningShoe(brand: brand, model: model)
        target.brand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        target.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        target.nickname = cleanNickname.isEmpty ? nil : cleanNickname
        target.purchaseDate = hasPurchaseDate ? purchaseDate : nil
        target.initialMileageKm = startingMileage
        target.preferredWorkoutTypes = Array(selectedTypes).sorted { $0.rawValue < $1.rawValue }
        target.primaryWorkoutType = primaryType
        target.expectedLifespanKm = expectedLifespan
        target.updatedAt = .now
        onSave(target)
        dismiss()
    }
}

struct ShoeUsageTypeSelector: View {
    @Binding var selectedTypes: Set<ShoeWorkoutType>
    @AppStorage(CoachLanguage.storageKey) private var languageRaw = CoachLanguage.en.rawValue

    private var language: CoachLanguage { CoachLanguage(rawValue: languageRaw) ?? .en }


    var body: some View {
        ForEach(ShoeWorkoutType.allCases.filter { $0 != .other }) { type in
            Button {
                if selectedTypes.contains(type) {
                    selectedTypes.remove(type)
                } else {
                    selectedTypes.insert(type)
                }
            } label: {
                HStack {
                    Text(language.integrations.shoeWorkoutType(type))
                    Spacer()
                    if selectedTypes.contains(type) {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
}

struct ShoeAssignmentSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var storedPreferences: [RunningShoePreferences]
    @State private var createdPreferences: RunningShoePreferences?
    @AppStorage(CoachLanguage.storageKey) private var languageRaw = CoachLanguage.en.rawValue

    private var language: CoachLanguage { CoachLanguage(rawValue: languageRaw) ?? .en }


    private var preferences: RunningShoePreferences? {
        storedPreferences.first ?? createdPreferences
    }

    var body: some View {
        Group {
            if let preferences {
                settingsForm(preferences)
            } else {
                ProgressView()
                    .task { ensurePreferences() }
            }
        }
        .navigationTitle(language.integrations.shoeAssignment)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func settingsForm(_ preferences: RunningShoePreferences) -> some View {
        Form {
            Section(language.integrations.automaticShoeAssignment) {
                Toggle(language.integrations.autoPickShoe, isOn: Binding(
                    get: { preferences.shoeAutoAssignmentEnabled },
                    set: {
                        preferences.shoeAutoAssignmentEnabled = $0
                        preferences.updatedAt = .now
                        reassign()
                    }
                ))
                Text(language.integrations.autoPickShoeExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(language.integrations.selectionStrategy) {
                Picker(language.integrations.strategy, selection: Binding(
                    get: { preferences.shoeAutoAssignmentStrategy },
                    set: {
                        preferences.shoeAutoAssignmentStrategy = $0
                        reassign()
                    }
                )) {
                    ForEach(ShoeAutoAssignmentStrategy.allCases) { strategy in
                        Text(language.integrations.shoeAssignmentStrategy(strategy)).tag(strategy)
                    }
                }
                Text(language.integrations.shoeAssignmentStrategyDescription(preferences.shoeAutoAssignmentStrategy))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(language.integrations.mileageRange) {
                Toggle(language.integrations.avoidShoesNearMileageLimit, isOn: Binding(
                    get: { preferences.avoidNearRetirementShoes },
                    set: {
                        preferences.avoidNearRetirementShoes = $0
                        preferences.updatedAt = .now
                        reassign()
                    }
                ))
                Stepper(language.integrations.avoidAfter(Int(preferences.nearRetirementThresholdPercent.rounded())), value: Binding(
                    get: { preferences.nearRetirementThresholdPercent },
                    set: {
                        preferences.nearRetirementThresholdPercent = $0
                        preferences.updatedAt = .now
                        reassign()
                    }
                ), in: 70...100, step: 5)
            }
        }
    }

    private func ensurePreferences() {
        guard storedPreferences.isEmpty, createdPreferences == nil else { return }
        let preferences = RunningShoePreferences()
        modelContext.insert(preferences)
        createdPreferences = preferences
        try? modelContext.save()
    }

    private func reassign() {
        try? ShoeAssignmentService.reassignFutureAutomaticWorkouts(in: modelContext)
        try? modelContext.save()
    }
}

struct WorkoutShoeRow: View {
    let shoe: RunningShoe?
    let source: ShoeAssignmentSource
    let isNearMileageRange: Bool
    @AppStorage(CoachLanguage.storageKey) private var languageRaw = CoachLanguage.en.rawValue

    private var language: CoachLanguage { CoachLanguage(rawValue: languageRaw) ?? .en }


    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "shoeprints.fill")
                .foregroundStyle(isNearMileageRange ? Theme.warn : Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(shoe?.displayName ?? language.integrations.chooseShoe)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(isNearMileageRange ? Theme.warn : Theme.dim)
            }
            Spacer()
            if source == .auto {
                Text(language.integrations.automatic)
                    .font(.torLabel(10, .bold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.faint)
        }
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        if isNearMileageRange { return language.integrations.nearRecommendedMileageRange }
        if source == .auto { return language.integrations.automaticallySelected }
        if shoe == nil { return language.integrations.chooseShoe }
        return language.integrations.runningShoe
    }
}

struct ShoePickerSheet: View {
    let workoutType: ShoeWorkoutType
    let shoes: [RunningShoe]
    let mileageEntries: [ShoeMileageEntry]
    let recommendedShoeID: UUID?
    let allowsAutomaticSelection: Bool
    let onSelect: (RunningShoe?) -> Void
    let onAutomatic: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @AppStorage(CoachLanguage.storageKey) private var languageRaw = CoachLanguage.en.rawValue

    private var language: CoachLanguage { CoachLanguage(rawValue: languageRaw) ?? .en }


    private var recommended: RunningShoe? {
        recommendedShoeID.flatMap { id in shoes.first { $0.id == id } }
    }

    private var matches: [RunningShoe] {
        shoes.filter { $0.status == .active && $0.preferredWorkoutTypes.contains(workoutType) && $0.id != recommendedShoeID }
    }

    private var others: [RunningShoe] {
        shoes.filter { $0.status == .active && !$0.preferredWorkoutTypes.contains(workoutType) && $0.id != recommendedShoeID }
    }

    var body: some View {
        NavigationStack {
            List {
                if let recommended {
                    Section(language.integrations.recommended) {
                        shoeButton(recommended, trailing: language.integrations.recommended)
                    }
                }
                if !matches.isEmpty {
                    Section(language.integrations.otherMatches) {
                        ForEach(matches, id: \.id) { shoeButton($0) }
                    }
                }
                if !others.isEmpty {
                    Section(language.integrations.otherShoes) {
                        ForEach(others, id: \.id) { shoeButton($0) }
                    }
                }
                Section {
                    if allowsAutomaticSelection, let onAutomatic {
                        Button(language.integrations.useAutomaticSelection) {
                            onAutomatic()
                            dismiss()
                        }
                    }
                    Button(language.integrations.noShoe) {
                        onSelect(nil)
                        dismiss()
                    }
                }
            }
            .navigationTitle(language.integrations.chooseAShoe)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func shoeButton(_ shoe: RunningShoe, trailing: String? = nil) -> some View {
        Button {
            onSelect(shoe)
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(shoe.displayName)
                        .font(.headline)
                    Text("\(language.integrations.shoeTypes(shoe.preferredWorkoutTypes)) · \(Formatters.kilometers(ShoeMileageService.currentMileageKm(for: shoe, ledger: mileageEntries) * 1000))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }
}


#if DEBUG
@MainActor
private enum RunningShoesPreviewData {
    static let emptyContainer: ModelContainer = {
        previewContainer(seed: false)
    }()

    static let populatedContainer: ModelContainer = {
        previewContainer(seed: true)
    }()

    private static func previewContainer(seed: Bool) -> ModelContainer {
        let schema = Schema([
            RunningShoe.self,
            ShoeMileageEntry.self,
            RunningShoePreferences.self,
            PlannedWorkout.self,
            CompletedActivity.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [configuration])
        guard seed else { return container }
        let shoes = [
            RunningShoe(
                brand: "ASICS",
                model: "Superblast 3",
                nickname: "Superblast 3",
                initialMileageKm: 327,
                preferredWorkoutTypes: [.easy, .longRun],
                primaryWorkoutType: .longRun,
                expectedLifespanKm: 600
            ),
            RunningShoe(
                brand: "Nike",
                model: "Vaporfly 4",
                initialMileageKm: 84,
                preferredWorkoutTypes: [.tempo, .threshold, .race],
                primaryWorkoutType: .race,
                expectedLifespanKm: 350
            ),
            RunningShoe(
                brand: "ASICS",
                model: "Novablast 6",
                initialMileageKm: 548,
                preferredWorkoutTypes: [.recovery, .easy],
                primaryWorkoutType: .easy,
                expectedLifespanKm: 600
            )
        ]
        shoes.forEach(container.mainContext.insert)
        return container
    }
}

#Preview("Running Shoes Empty") {
    NavigationStack {
        RunningShoesView()
    }
    .modelContainer(RunningShoesPreviewData.emptyContainer)
}

#Preview("Running Shoes List") {
    NavigationStack {
        RunningShoesView()
    }
    .modelContainer(RunningShoesPreviewData.populatedContainer)
}

#Preview("Shoe Picker") {
    ShoePickerSheet(
        workoutType: .easy,
        shoes: [
            RunningShoe(brand: "ASICS", model: "Novablast 6", initialMileageKm: 43, preferredWorkoutTypes: [.recovery, .easy], primaryWorkoutType: .easy),
            RunningShoe(brand: "ASICS", model: "Superblast 3", initialMileageKm: 327, preferredWorkoutTypes: [.easy, .longRun], primaryWorkoutType: .longRun),
            RunningShoe(brand: "Nike", model: "Vaporfly 4", initialMileageKm: 84, preferredWorkoutTypes: [.tempo, .race], primaryWorkoutType: .race, expectedLifespanKm: 350)
        ],
        mileageEntries: [],
        recommendedShoeID: nil,
        allowsAutomaticSelection: true,
        onSelect: { _ in },
        onAutomatic: {}
    )
}

#Preview("Add Shoe") {
    NavigationStack {
        ShoeFormView(mode: .add) { _ in }
    }
}
#endif
