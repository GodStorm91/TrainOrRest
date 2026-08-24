import SwiftData
import SwiftUI

struct RunningShoesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RunningShoe.createdAt, order: .reverse) private var shoes: [RunningShoe]
    @Query private var mileageEntries: [ShoeMileageEntry]
    @Query(sort: \PlannedWorkout.date) private var workouts: [PlannedWorkout]

    @State private var showingAddShoe = false
    @State private var showingSettings = false

    private var activeShoes: [RunningShoe] { shoes.filter { $0.status == .active } }
    private var retiredShoes: [RunningShoe] { shoes.filter { $0.status == .retired } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if shoes.isEmpty {
                    emptyState
                } else {
                    shoeSection("Active", shoes: activeShoes)
                    if !retiredShoes.isEmpty {
                        DisclosureGroup("Retired · \(retiredShoes.count) shoes") {
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
                    Label(shoes.isEmpty ? "Add your first shoe" : "Add shoe", systemImage: "plus")
                        .font(.torHeading(15, .bold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            }
            .padding(16)
            .padding(.bottom, 86)
        }
        .background(Theme.bg)
        .navigationTitle("Running Shoes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("Shoe assignment settings")
            }
        }
        .sheet(isPresented: $showingAddShoe) {
            NavigationStack {
                ShoeFormView(mode: .add) { shoe in
                    modelContext.insert(shoe)
                    try? ShoeAssignmentService.reassignFutureAutomaticWorkouts(in: modelContext)
                    try? modelContext.save()
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
                Text("Track shoe mileage and let TrainOrRest pick the right pair for each workout.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func shoeSection(_ title: String, shoes: [RunningShoe]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TorEyebrow(title).tracking(2)
            if shoes.isEmpty {
                Text("No active shoes.")
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
}

struct RunningShoeRow: View {
    let shoe: RunningShoe
    let mileageKm: Double
    let isRetired: Bool

    private var wearStatus: ShoeWearStatus {
        ShoeWearStatusService.wearStatus(currentMileageKm: mileageKm, expectedLifespanKm: shoe.expectedLifespanKm)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "shoeprints.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(wearColor)
                .frame(width: 38, height: 38)
                .background(Theme.soft(wearColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(shoe.displayName)
                    .font(.torHeading(16, .bold))
                    .foregroundStyle(isRetired ? Theme.faint : Theme.text)
                Text(shoe.preferredTypesText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text("\(kmText(mileageKm)) / ~\(kmText(shoe.expectedLifespanKm)) km")
                        .font(.torMono(11))
                        .foregroundStyle(Theme.faint)
                    if warningText != nil {
                        Text(warningText ?? "")
                            .font(.torLabel(10, .bold))
                            .foregroundStyle(wearColor)
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.faint)
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        .opacity(isRetired ? 0.62 : 1)
    }

    private var warningText: String? {
        switch wearStatus {
        case .normal, .approaching: nil
        case .inspect: "Check soon"
        case .pastRange: "Past typical range"
        }
    }

    private var wearColor: Color {
        switch wearStatus {
        case .normal: Theme.accent
        case .approaching, .inspect, .pastRange: Theme.warn
        }
    }
}

struct ShoeMileageIndicator: View {
    let mileageKm: Double
    let expectedKm: Double

    private var progress: Double {
        guard expectedKm > 0 else { return 0 }
        return min(mileageKm / expectedKm, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: progress)
                .tint(ShoeWearStatusService.wearStatus(currentMileageKm: mileageKm, expectedLifespanKm: expectedKm) == .normal ? Theme.accent : Theme.warn)
            Text("\(kmText(mileageKm)) km logged")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
            if mileageKm < expectedKm {
                Text("~\(kmText(expectedKm - mileageKm)) km until recommended range")
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
                        TorEyebrow(shoe.brand.isEmpty ? "Running Shoe" : shoe.brand).tracking(2)
                        Text(shoe.model.isEmpty ? shoe.displayName : shoe.model.uppercased())
                            .font(.torHeading(28, .bold))
                            .foregroundStyle(Theme.text)
                        Text("\(kmText(mileageKm)) km")
                            .font(.torNumber(36, .bold))
                            .foregroundStyle(Theme.text)
                        Text(shoe.status == .active ? "Active" : "Retired")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(shoe.status == .active ? Theme.good : Theme.faint)
                    }
                }

                detailSection("Mileage") {
                    ShoeMileageIndicator(mileageKm: mileageKm, expectedKm: shoe.expectedLifespanKm)
                    MileageWarning(shoe: shoe, mileageKm: mileageKm)
                }

                detailSection("Usage") {
                    ShoeMetricRow(label: "Runs", value: "\(shoeActivities.count)")
                    ShoeMetricRow(label: "Distance", value: "\(kmText(entries.map(\.distanceKm).reduce(0, +))) km")
                    if let last = shoeActivities.first {
                        ShoeMetricRow(
                            label: "Last run",
                            value: "\(last.date.formatted(.dateTime.month(.abbreviated).day())) · \(Formatters.kilometers(last.distanceMeters))"
                        )
                    }
                }

                detailSection("Preferences") {
                    ShoeMetricRow(label: "Preferred for", value: shoe.preferredTypesText)
                    ShoeMetricRow(label: "Primary", value: shoe.primaryWorkoutType?.displayName ?? "Any run")
                }

                detailSection("Purchase") {
                    ShoeMetricRow(label: "Purchased", value: shoe.purchaseDate?.formatted(date: .abbreviated, time: .omitted) ?? "Not set")
                    ShoeMetricRow(label: "Starting mileage", value: "\(kmText(shoe.initialMileageKm)) km")
                }

                VStack(spacing: 10) {
                    Button { showingEdit = true } label: {
                        Label("Edit shoe", systemImage: "pencil")
                            .frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .buttonStyle(.bordered)

                    Button(role: shoe.status == .active ? .destructive : nil) {
                        toggleStatus()
                    } label: {
                        Label(shoe.status == .active ? "Retire shoe" : "Reactivate shoe", systemImage: shoe.status == .active ? "archivebox" : "arrow.uturn.backward")
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
                }
            }
        }
    }

    private func detailSection<Content: View>(_ title: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        TorCard {
            VStack(alignment: .leading, spacing: 12) {
                TorEyebrow(title).tracking(2)
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

    private var status: ShoeWearStatus {
        ShoeWearStatusService.wearStatus(currentMileageKm: mileageKm, expectedLifespanKm: shoe.expectedLifespanKm)
    }

    var body: some View {
        switch status {
        case .normal:
            EmptyView()
        case .approaching:
            warning("Approaching recommended mileage", "No action needed yet.")
        case .inspect:
            warning("Check your \(shoe.displayName)", "Consider cushioning feel, outsole wear, uneven wear, and new discomfort.")
        case .pastRange:
            warning("Past typical mileage range", "You can keep using it if it still feels good, or retire it from automatic assignment.")
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

    private var editingShoe: RunningShoe? {
        if case let .edit(shoe) = mode { return shoe }
        return nil
    }

    var body: some View {
        Form {
            if step == 0 {
                Section("Basic information") {
                    TextField("Brand", text: $brand)
                    TextField("Model", text: $model)
                    TextField("Nickname", text: $nickname)
                    Toggle("Set purchase date", isOn: $hasPurchaseDate)
                    if hasPurchaseDate {
                        DatePicker("Purchase date", selection: $purchaseDate, displayedComponents: .date)
                    }
                    Stepper("Starting mileage: \(kmText(startingMileage)) km", value: $startingMileage, in: 0...5000, step: 5)
                }
            } else if step == 1 {
                Section("What do you use this shoe for?") {
                    ShoeUsageTypeSelector(selectedTypes: $selectedTypes)
                }
                Section("Primary use") {
                    Picker("Primary use", selection: $primaryType) {
                        ForEach(Array(selectedTypes).sorted(by: { $0.displayName < $1.displayName }), id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                }
            } else {
                Section("Mileage") {
                    Stepper("Expected lifespan: ~\(kmText(expectedLifespan)) km", value: $expectedLifespan, in: 100...1200, step: 50)
                    Text("You can adjust this anytime.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(step == 2 ? "Save" : "Next") {
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
                primaryType = newValue.sorted(by: { $0.displayName < $1.displayName }).first ?? .easy
            } else if newValue.count == 1, let only = newValue.first {
                primaryType = only
            }
        }
    }

    private var title: String {
        switch mode {
        case .add: "Add Shoe"
        case .edit: "Edit Shoe"
        }
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
        target.preferredWorkoutTypes = Array(selectedTypes).sorted { $0.displayName < $1.displayName }
        target.primaryWorkoutType = primaryType
        target.expectedLifespanKm = expectedLifespan
        target.updatedAt = .now
        onSave(target)
        dismiss()
    }
}

struct ShoeUsageTypeSelector: View {
    @Binding var selectedTypes: Set<ShoeWorkoutType>

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
                    Text(type.displayName)
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
        .navigationTitle("Shoe Assignment")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func settingsForm(_ preferences: RunningShoePreferences) -> some View {
        Form {
            Section("Automatic shoe assignment") {
                Toggle("Auto-pick a shoe", isOn: Binding(
                    get: { preferences.shoeAutoAssignmentEnabled },
                    set: {
                        preferences.shoeAutoAssignmentEnabled = $0
                        preferences.updatedAt = .now
                        reassign()
                    }
                ))
                Text("When a workout does not already have a shoe, TrainOrRest can choose one based on workout type and your shoe preferences.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Selection strategy") {
                Picker("Strategy", selection: Binding(
                    get: { preferences.shoeAutoAssignmentStrategy },
                    set: {
                        preferences.shoeAutoAssignmentStrategy = $0
                        reassign()
                    }
                )) {
                    ForEach(ShoeAutoAssignmentStrategy.allCases) { strategy in
                        Text(strategy.displayName).tag(strategy)
                    }
                }
                Text(preferences.shoeAutoAssignmentStrategy.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Mileage range") {
                Toggle("Avoid shoes near mileage limit", isOn: Binding(
                    get: { preferences.avoidNearRetirementShoes },
                    set: {
                        preferences.avoidNearRetirementShoes = $0
                        preferences.updatedAt = .now
                        reassign()
                    }
                ))
                Stepper("Avoid after \(Int(preferences.nearRetirementThresholdPercent.rounded()))%", value: Binding(
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

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "shoeprints.fill")
                .foregroundStyle(isNearMileageRange ? Theme.warn : Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(shoe?.displayName ?? "Choose shoe")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(isNearMileageRange ? Theme.warn : Theme.dim)
            }
            Spacer()
            if source == .auto {
                Text("Auto")
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
        if isNearMileageRange { return "Near recommended mileage range" }
        if source == .auto { return "Automatically selected" }
        if shoe == nil { return "Add shoe" }
        return "Running shoe"
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
                    Section("Recommended") {
                        shoeButton(recommended, trailing: "Recommended")
                    }
                }
                if !matches.isEmpty {
                    Section("Other matches") {
                        ForEach(matches, id: \.id) { shoeButton($0) }
                    }
                }
                if !others.isEmpty {
                    Section("Other shoes") {
                        ForEach(others, id: \.id) { shoeButton($0) }
                    }
                }
                Section {
                    if allowsAutomaticSelection, let onAutomatic {
                        Button("Use automatic selection") {
                            onAutomatic()
                            dismiss()
                        }
                    }
                    Button("No shoe") {
                        onSelect(nil)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Choose a shoe")
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
                    Text("\(shoe.preferredTypesText) · \(kmText(ShoeMileageService.currentMileageKm(for: shoe, ledger: mileageEntries))) km")
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

func kmText(_ value: Double) -> String {
    let rounded = value.rounded()
    if abs(value - rounded) < 0.05 {
        return "\(Int(rounded))"
    }
    return String(format: "%.1f", value)
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
