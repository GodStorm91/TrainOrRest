import SwiftData
import SwiftUI

struct PostRunReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var activity: CompletedActivity
    let plannedWorkout: PlannedWorkout?
    @Query(sort: \RunningShoe.createdAt, order: .reverse) private var shoes: [RunningShoe]
    @Query private var mileageEntries: [ShoeMileageEntry]
    @Query private var storedShoePreferences: [RunningShoePreferences]

    @AppStorage(CoachLanguage.storageKey) private var languageRaw = CoachLanguage.en.rawValue
    @State private var showDetailedReview = false
    @State private var isChoosingShoe = false

    private var language: CoachLanguage {
        CoachLanguage(rawValue: languageRaw) ?? .en
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    header
                    shoeRow
                    progressBar
                    actions
                    noteEditor
                    if showDetailedReview {
                        RunReviewCard(activity: activity, plannedWorkout: plannedWorkout, compact: false)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 10)
                .padding(.bottom, 28)
            }
            .background(Theme.bg)
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .sheet(isPresented: $isChoosingShoe) {
            ShoePickerSheet(
                workoutType: ShoeWorkoutType.normalized(from: plannedWorkout?.kind),
                shoes: shoes,
                mileageEntries: mileageEntries,
                recommendedShoeID: recommendedShoeID,
                allowsAutomaticSelection: false,
                onSelect: { shoe in
                    activity.shoeID = shoe?.id
                    activity.shoeAssignmentSource = shoe == nil ? .none : .manual
                    try? ShoeMileageService.syncMileage(for: activity, in: modelContext)
                    try? modelContext.save()
                },
                onAutomatic: nil
            )
        }
        .onAppear(perform: copyPlannedShoeIfNeeded)
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 44, height: 44)
                        .background(Theme.chip, in: Circle())
                }
                .accessibilityLabel(language.today.closePostRunReview)

                Spacer()

                Text(language.today.postRunDate(activity.date))
                    .font(.torHeading(15, .bold))
                    .foregroundStyle(Theme.text)

                Spacer()

                Color.clear.frame(width: 44, height: 44)
            }

            VStack(spacing: 7) {
                Text(language.today.running)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.faint)
                Text(headline)
                    .font(.torHeading(22, .bold))
                    .foregroundStyle(Theme.text)
                Text(subheadline)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.dim)
            }
            .padding(.top, 4)
        }
    }

    private var headline: String {
        let distance = language.today.postRunDistance(activity.distanceMeters)
        let minutes = Int((activity.durationSeconds / 60).rounded())
        return language.today.postRunHeadline(distance: distance, minutes: minutes)
    }

    private var subheadline: String {
        "\(Formatters.duration(activity.durationSeconds)) @ \(Formatters.pace(activity.avgPaceSecondsPerKm).replacingOccurrences(of: " /km", with: "/km"))"
    }

    private var progressBar: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(index < filledSegments ? Theme.accent : Theme.line)
                    .frame(height: 54)
            }
        }
        .padding(.top, 8)
    }

    private var filledSegments: Int {
        guard let planned = plannedWorkout?.distanceKm, planned > 0,
              let actual = activity.distanceMeters.map({ $0 / 1000 }) else {
            return min(5, max(1, Int((activity.durationSeconds / 1800).rounded())))
        }
        return min(5, max(1, Int((actual / planned * 5).rounded())))
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button {
                showDetailedReview = false
                close()
            } label: {
                Label(language.today.editAndShare, systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PostRunActionButtonStyle())
            .overlay(alignment: .topTrailing) {
                Text(language.today.new)
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.black, in: Capsule())
                    .offset(x: -8, y: 8)
            }

            Button {
                markReviewed()
                withAnimation(.easeOut(duration: 0.2)) {
                    showDetailedReview.toggle()
                }
            } label: {
                Label(showDetailedReview ? language.today.hideReview : language.today.review, systemImage: "message.badge")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PostRunActionButtonStyle())
        }
    }
    private var shoeRow: some View {
        Button {
            isChoosingShoe = true
        } label: {
            WorkoutShoeRow(
                shoe: assignedShoe,
                source: activity.shoeAssignmentSource,
                isNearMileageRange: assignedShoe.map(isNearMileageRange) ?? false
            )
        }
        .buttonStyle(.plain)
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
        .accessibilityLabel(language.plan.gear)
    }

    private var assignedShoe: RunningShoe? {
        guard let shoeID = activity.shoeID else { return nil }
        return shoes.first { $0.id == shoeID }
    }

    private var shoePreferences: RunningShoePreferences {
        storedShoePreferences.first ?? RunningShoePreferences()
    }

    private var recommendedShoeID: UUID? {
        if let shoeID = plannedWorkout?.shoeID { return shoeID }
        return ShoeAssignmentService.selectShoeForWorkout(
            workoutType: ShoeWorkoutType.normalized(from: plannedWorkout?.kind),
            activeShoes: shoes,
            preferences: shoePreferences,
            existingShoeID: nil,
            existingAssignmentSource: .none,
            mileageEntries: mileageEntries
        ).shoeID
    }

    private func isNearMileageRange(_ shoe: RunningShoe) -> Bool {
        ShoeWearStatusService.isNearRetirement(
            shoe,
            ledger: mileageEntries,
            thresholdPercent: shoePreferences.nearRetirementThresholdPercent
        )
    }

    private func copyPlannedShoeIfNeeded() {
        guard ShoeAssignmentService.inheritPlannedShoe(onto: activity, from: plannedWorkout) else { return }
        try? ShoeMileageService.syncMileage(for: activity, in: modelContext)
        try? modelContext.save()
    }


    private var noteEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(language.today.addNote)
                    .font(.torHeading(18, .bold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(Theme.faint)
            }

            TextEditor(text: reviewNoteBinding)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Theme.text)
                .frame(minHeight: 118)
                .padding(10)
                .scrollContentBackground(.hidden)
                .background(Theme.card2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if (activity.reviewNote ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(language.today.reviewNotePlaceholder)
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.faint)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        }
    }

    private var reviewNoteBinding: Binding<String> {
        Binding(
            get: { activity.reviewNote ?? "" },
            set: { newValue in activity.reviewNote = newValue.isEmpty ? nil : newValue }
        )
    }

    private func markReviewed() {
        if activity.postRunReviewDismissedAt == nil {
            activity.postRunReviewDismissedAt = .now
            try? modelContext.save()
        }
    }

    private func close() {
        markReviewed()
        dismiss()
    }
}

private struct PostRunActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.text)
            .padding(.vertical, 15)
            .background(configuration.isPressed ? Theme.accentSoft : Theme.chip, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}
