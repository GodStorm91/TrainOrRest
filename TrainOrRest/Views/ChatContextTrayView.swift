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
                        title: "Readiness snapshot",
                        detail: evidence.readinessSnapshot ? "on" : "off",
                        systemImage: "heart.text.square",
                        isSelected: evidence.readinessSnapshot
                    ) {
                        evidence.readinessSnapshot.toggle()
                    }
                    ContextChip(
                        title: "This week plan",
                        detail: evidence.weekPlan ? "on" : "off",
                        systemImage: "calendar",
                        isSelected: evidence.weekPlan
                    ) {
                        evidence.weekPlan.toggle()
                    }
                    workoutMenu
                    imagePicker
                    ContextChip(
                        title: "Evidence",
                        detail: "review",
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
            Label("Evidence", systemImage: "paperclip")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.dim)
            Spacer()
            Label("Validated before plan changes", systemImage: "checkmark.shield")
                .font(.caption2)
                .foregroundStyle(Theme.faint)
        }
    }

    private var workoutMenu: some View {
        Menu {
            if evidence.workout != nil {
                Button("Remove workout context", role: .destructive) {
                    evidence.workout = nil
                }
            }
            if !upcomingWorkouts.isEmpty {
                Section("Planned Workouts") {
                    ForEach(upcomingWorkouts, id: \.uuid) { workout in
                        Button(workoutLabel(workout)) {
                            evidence.workout = .planned(workout.uuid)
                        }
                    }
                }
            }
            if !completedActivities.isEmpty {
                Section("Recent Runs") {
                    ForEach(Array(completedActivities.prefix(6)), id: \.hkUUID) { activity in
                        Button(activityLabel(activity)) {
                            evidence.workout = .completed(activity.hkUUID)
                        }
                    }
                }
            }
        } label: {
            ContextChipLabel(
                title: "Workout",
                detail: workoutContextDetail,
                systemImage: "figure.run",
                isSelected: evidence.workout != nil
            )
        }
    }

    private var imagePicker: some View {
        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
            ContextChipLabel(
                title: "Image",
                detail: selectedImageAttachment == nil ? "add" : "ready",
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
                    Text("Image attached")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.text)
                    Text("\((selectedImageAttachment?.data.count ?? 0) / 1024) KB, sent with this message")
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
            guard let workout = plannedWorkouts.first(where: { $0.uuid == uuid }) else { return "selected" }
            return workout.kind?.displayName ?? "planned"
        case .completed(let uuid):
            guard let activity = completedActivities.first(where: { $0.hkUUID == uuid }) else { return "selected" }
            return Formatters.kilometers(activity.distanceMeters)
        case nil:
            return "add"
        }
    }

    private func workoutLabel(_ workout: PlannedWorkout) -> String {
        let date = workout.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        return "\(date): \(workout.kind?.displayName ?? workout.kindRaw), \(String(format: "%.1f", workout.distanceKm)) km"
    }

    private func activityLabel(_ activity: CompletedActivity) -> String {
        let date = activity.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        return "\(date): \(Formatters.kilometers(activity.distanceMeters)), \(Formatters.pace(activity.avgPaceSecondsPerKm))"
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
