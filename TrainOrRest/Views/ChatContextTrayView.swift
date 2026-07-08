import PhotosUI
import SwiftUI
import UIKit

enum WorkoutContextSelection: Equatable {
    case planned(UUID)
    case completed(UUID)
}

struct ChatContextTrayView: View {
    @Binding var includeHealthContext: Bool
    @Binding var selectedWorkoutContext: WorkoutContextSelection?
    @Binding var selectedPhotoItem: PhotosPickerItem?
    @Binding var selectedImageAttachment: CoachImageAttachment?
    @Binding var selectedImage: UIImage?

    let plannedWorkouts: [PlannedWorkout]
    let completedActivities: [CompletedActivity]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ContextChip(
                        title: "Health",
                        detail: includeHealthContext ? "on" : "off",
                        systemImage: "heart.text.square",
                        isSelected: includeHealthContext
                    ) {
                        includeHealthContext.toggle()
                    }
                    workoutMenu
                    imagePicker
                }
                .padding(.vertical, 1)
            }
            imagePreview
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label("Context", systemImage: "paperclip")
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
            if selectedWorkoutContext != nil {
                Button("Remove workout context", role: .destructive) {
                    selectedWorkoutContext = nil
                }
            }
            if !upcomingWorkouts.isEmpty {
                Section("Planned Workouts") {
                    ForEach(upcomingWorkouts, id: \.uuid) { workout in
                        Button(workoutLabel(workout)) {
                            selectedWorkoutContext = .planned(workout.uuid)
                        }
                    }
                }
            }
            if !completedActivities.isEmpty {
                Section("Recent Runs") {
                    ForEach(Array(completedActivities.prefix(6)), id: \.hkUUID) { activity in
                        Button(activityLabel(activity)) {
                            selectedWorkoutContext = .completed(activity.hkUUID)
                        }
                    }
                }
            }
        } label: {
            ContextChipLabel(
                title: "Workout",
                detail: workoutContextDetail,
                systemImage: "figure.run",
                isSelected: selectedWorkoutContext != nil
            )
        }
    }

    private var imagePicker: some View {
        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
            ContextChipLabel(
                title: "Image",
                detail: selectedImageAttachment == nil ? "add" : "ready",
                systemImage: "photo",
                isSelected: selectedImageAttachment != nil
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
        switch selectedWorkoutContext {
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
        }
    }

    private func clearImageAttachment() {
        selectedPhotoItem = nil
        selectedImageAttachment = nil
        selectedImage = nil
    }

    private func compressedImageData(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let maxSide: CGFloat = 1280
        let largestSide = max(image.size.width, image.size.height)
        let scale = largestSide > maxSide ? maxSide / largestSide : 1
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let rendered = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return rendered.jpegData(compressionQuality: 0.78)
    }
}
