import CoreImage
import ImageIO
import PhotosUI
import SwiftUI
import UIKit

enum WorkoutContextSelection: Equatable {
    case planned(UUID)
    case completed(UUID)
}

struct ChatContextTrayView: View {
    @Binding var evidence: EvidenceSelection
    @Binding var selectedPhotoItem: PhotosPickerItem?
    @Binding var selectedImageAttachment: CoachImageAttachment?
    @Binding var selectedImage: UIImage?

    let language: CoachLanguage
    let plannedWorkouts: [PlannedWorkout]
    let completedActivities: [CompletedActivity]
    let onReviewEvidence: () -> Void

    private static let ciContext = CIContext()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ContextChip(
                        title: language.readinessSourceTitle,
                        detail: evidence.readinessSnapshot ? language.contextIncludedLabel : language.contextNotIncludedLabel,
                        systemImage: "heart.text.square",
                        isSelected: evidence.readinessSnapshot
                    ) {
                        evidence.readinessSnapshot.toggle()
                    }
                    ContextChip(
                        title: language.planSourceTitle,
                        detail: evidence.weekPlan ? language.contextIncludedLabel : language.contextNotIncludedLabel,
                        systemImage: "calendar",
                        isSelected: evidence.weekPlan
                    ) {
                        evidence.weekPlan.toggle()
                    }
                    workoutMenu
                    imagePicker
                    ContextChip(
                        title: language.genericSourceTitle,
                        detail: language.contextReviewLabel,
                        systemImage: "doc.text.magnifyingglass",
                        isSelected: true,
                        action: onReviewEvidence
                    )
                }
                .padding(.vertical, 1)
            }
            imagePreview
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label(language.genericSourceTitle, systemImage: "paperclip")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.dim)
            Spacer()
            Label(language.checkedDataRowTitle, systemImage: "checkmark.shield")
                .font(.caption2)
                .foregroundStyle(Theme.faint)
        }
    }

    private var workoutMenu: some View {
        Menu {
            if evidence.workout != nil {
                Button(language.removeWorkoutContextLabel, role: .destructive) {
                    evidence.workout = nil
                }
            }
            if !upcomingWorkouts.isEmpty {
                Section(language.plannedWorkoutsLabel) {
                    ForEach(upcomingWorkouts, id: \.uuid) { workout in
                        Button(workoutLabel(workout)) {
                            evidence.workout = .planned(workout.uuid)
                        }
                    }
                }
            }
            if !completedActivities.isEmpty {
                Section(language.recentRunsLabel) {
                    ForEach(Array(completedActivities.prefix(6)), id: \.hkUUID) { activity in
                        Button(activityLabel(activity)) {
                            evidence.workout = .completed(activity.hkUUID)
                        }
                    }
                }
            }
        } label: {
            ContextChipLabel(
                title: language.workoutMenuLabel,
                detail: workoutContextDetail,
                systemImage: "figure.run",
                isSelected: evidence.workout != nil
            )
        }
    }

    private var imagePicker: some View {
        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
            ContextChipLabel(
                title: language.imageChipLabel,
                detail: selectedImageAttachment == nil ? language.contextAddLabel : language.contextReadyLabel,
                systemImage: "photo",
                isSelected: evidence.hasPhoto
            )
        }
        .onChange(of: selectedPhotoItem) { _, item in
            loadImageAttachment(from: item)
        }
    }

    @ViewBuilder
    private var imagePreview: some View {
        if let selectedImage {
            HStack(spacing: 8) {
                Image(uiImage: selectedImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(language.imageAttachedLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.text)
                    Text(language.imageAttachmentDetail((selectedImageAttachment?.data.count ?? 0) / 1024))
                        .font(.caption2)
                        .foregroundStyle(Theme.faint)
                }
                Spacer()
                Button {
                    clearImageAttachment()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(language.removeImageLabel)
                .foregroundStyle(Theme.dim)
            }
            .padding(8)
            .background(Theme.card2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
        }
    }

    private var upcomingWorkouts: [PlannedWorkout] {
        let dayStart = Calendar.current.startOfDay(for: .now)
        return Array(plannedWorkouts.filter { $0.date >= dayStart }.prefix(8))
    }

    private var workoutContextDetail: String {
        switch evidence.workout {
        case .planned(let uuid):
            guard let workout = plannedWorkouts.first(where: { $0.uuid == uuid }) else { return language.contextSelectedLabel }
            return workout.kind.map { language.name($0) } ?? language.genericRunLabel
        case .completed(let uuid):
            guard let activity = completedActivities.first(where: { $0.hkUUID == uuid }) else { return language.contextSelectedLabel }
            return localizedDistance(meters: activity.distanceMeters)
        case nil:
            return language.contextAddLabel
        }
    }

    private func workoutLabel(_ workout: PlannedWorkout) -> String {
        language.contextWorkoutListItem(
            date: language.shortWeekdayDate(workout.date),
            title: workout.kind.map { language.name($0) } ?? language.genericRunLabel,
            distance: localizedKilometers(workout.distanceKm)
        )
    }

    private func activityLabel(_ activity: CompletedActivity) -> String {
        language.contextWorkoutListItem(
            date: language.shortWeekdayDate(activity.date),
            title: localizedDistance(meters: activity.distanceMeters),
            distance: Formatters.pace(activity.avgPaceSecondsPerKm)
        )
    }

    private func localizedKilometers(_ kilometers: Double) -> String {
        "\(String(format: "%.1f", locale: language.uiLocale, kilometers)) km"
    }

    private func localizedDistance(meters: Double?) -> String {
        guard let meters else { return "–" }
        return localizedKilometers(meters / 1_000)
    }

    private func loadImageAttachment(from item: PhotosPickerItem?) {
        guard let item else {
            clearImageAttachment()
            return
        }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let compressed = compressedImageData(from: data),
                  let image = UIImage(data: compressed) else { return }
            selectedImageAttachment = CoachImageAttachment(
                data: compressed,
                mediaType: "image/jpeg",
                filename: "training-context.jpg"
            )
            selectedImage = image
            evidence.hasPhoto = true
        }
    }

    private func clearImageAttachment() {
        selectedPhotoItem = nil
        selectedImageAttachment = nil
        selectedImage = nil
        evidence.hasPhoto = false
    }

    private func compressedImageData(from data: Data) -> Data? {
        guard var image = CIImage(data: data, options: [.applyOrientationProperty: true]) else { return nil }
        let maxSide: CGFloat = 1280
        let largestSide = max(image.extent.width, image.extent.height)
        let scale = largestSide > maxSide ? maxSide / largestSide : 1
        image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let options: [CIImageRepresentationOption: Any] = [
            CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.78
        ]
        return Self.ciContext.jpegRepresentation(
            of: image,
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            options: options
        )
    }
}
