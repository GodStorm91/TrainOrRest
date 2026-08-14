import SwiftUI
import UIKit
import XCTest
@testable import TrainOrRest

final class VerdictContrastTests: XCTestCase {
    func testVerdictTokensMeetDarkCardContrast() {
        let traits = UITraitCollection(userInterfaceStyle: .dark)
        let background = UIColor(Theme.card).resolvedColor(with: traits)
        let tokens: [(name: String, color: Color)] = [
            ("Train", Theme.verdictTrain),
            ("Go easy", Theme.verdictEasy),
            ("Rest", Theme.verdictRest),
        ]

        for token in tokens {
            let foreground = UIColor(token.color).resolvedColor(with: traits)
            XCTAssertGreaterThanOrEqual(
                contrastRatio(foreground, background),
                4.5,
                "\(token.name) verdict token must meet WCAG AA contrast against Theme.card in dark mode."
            )
        }
    }

    private func contrastRatio(_ first: UIColor, _ second: UIColor) -> Double {
        let firstLuminance = relativeLuminance(first)
        let secondLuminance = relativeLuminance(second)
        let lighter = max(firstLuminance, secondLuminance)
        let darker = min(firstLuminance, secondLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func relativeLuminance(_ color: UIColor) -> Double {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            XCTFail("Could not resolve color components.")
            return 0
        }

        let linearRed = linearChannel(Double(red))
        let linearGreen = linearChannel(Double(green))
        let linearBlue = linearChannel(Double(blue))
        return 0.2126 * linearRed + 0.7152 * linearGreen + 0.0722 * linearBlue
    }

    private func linearChannel(_ value: Double) -> Double {
        value <= 0.03928
            ? value / 12.92
            : pow((value + 0.055) / 1.055, 2.4)
    }
}
