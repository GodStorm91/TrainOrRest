import XCTest
import SwiftUI
@testable import TrainOrRest

@MainActor
final class CoachGlossaryRasterTests: XCTestCase {
    func testGlossaryCardRasterizes() throws {
        guard #available(iOS 16.0, *) else { return }

        let output = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: ".verify-artifacts", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let response = CoachStructuredResponse(
            title: "Ưu tiên phục hồi hôm nay",
            summary: "Theo dõi [[term:acwr|ACWR]], [[term:hrv|HRV]] và [[term:rhr|RHR]] mỗi sáng.",
            safetyNote: nil,
            recommendations: [
                .init(id: "easy", title: "Giữ buổi tới ở [[term:e_pace|E pace]].", description: nil, priority: 1)
            ],
            details: nil,
            followUps: [],
            status: .recoveryRecommended,
            metrics: [
                .init(id: "acwr", label: "ACWR", value: "1.2", interpretation: "Cần chú ý", status: .attention)
            ],
            primaryAction: nil,
            secondaryAction: nil,
            sources: []
        )

        let card = CoachResponseCard(response: response, language: .vi)
            .frame(width: 390)
            .padding(16)
            .background(Theme.bg)

        try write(card, to: output.appending(path: "coach-glossary-card-light.png"))
        try write(card.environment(\.colorScheme, .dark), to: output.appending(path: "coach-glossary-card-dark.png"))

        let sheet = CoachGlossarySheet(termId: "acwr", currentValue: "1.2", language: .vi)
            .frame(width: 390, height: 620)
        try write(sheet, to: output.appending(path: "coach-glossary-sheet-vi.png"))

        let longFollowUps = CoachStructuredResponse(
            title: "Kế hoạch tuần này",
            summary: "Tóm tắt ngắn cho tuần này.",
            safetyNote: nil,
            recommendations: [],
            details: nil,
            followUps: [
                .init(id: "next", label: "Đi tới bước tiếp theo để áp dụng qua đề xuất chỉnh sửa", description: nil, value: "next"),
                .init(id: "detail", label: "Xem chi tiết đề xuất", description: nil, value: "detail")
            ],
            status: .recoveryRecommended,
            metrics: [],
            primaryAction: nil,
            secondaryAction: nil,
            sources: []
        )
        let followUpCard = CoachResponseCard(response: longFollowUps, language: .vi)
            .frame(width: 390)
            .padding(16)
            .background(Theme.bg)
        try write(followUpCard, to: output.appending(path: "coach-followup-overflow.png"))
    }

    private func write(_ view: some View, to url: URL) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        let image = try XCTUnwrap(renderer.uiImage)
        let data = try XCTUnwrap(image.pngData())
        try data.write(to: url)
    }
}
