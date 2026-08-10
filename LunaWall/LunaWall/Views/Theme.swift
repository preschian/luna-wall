import SwiftUI

/// Palette and control styles from the LunaWall prototype (Claude Design).
enum Theme {
    static let shell = Color(red: 0.043, green: 0.051, blue: 0.071) // #0b0d12
    static let bar = Color(red: 0.063, green: 0.075, blue: 0.098) // #101319
    static let tile = Color(red: 0.125, green: 0.141, blue: 0.180) // #20242e
    static let scrim = Color(red: 0.024, green: 0.031, blue: 0.047) // #06080c
    /// oklch(0.84 0.11 78)
    static let amber = Color(red: 0.949, green: 0.714, blue: 0.353)
    /// oklch(0.78 0.14 45)
    static let pinned = Color(red: 0.961, green: 0.541, blue: 0.392)
    static let onAmber = Color(red: 0.078, green: 0.063, blue: 0.039) // #14100a
    static let hairline = Color.white.opacity(0.09)

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// Outlined button; `glass` adds the blurred plate used over the hero image.
struct GhostButtonStyle: ButtonStyle {
    var glass = false
    var size: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background {
                let shape = RoundedRectangle(cornerRadius: 8)
                ZStack {
                    if glass { shape.fill(.ultraThinMaterial) }
                    shape.fill(.white.opacity(configuration.isPressed ? 0.18 : 0))
                    shape.strokeBorder(.white.opacity(0.18))
                }
            }
    }
}

/// Ghost button that also names itself for VoiceOver — a custom `ButtonStyle` alone
/// leaves `AXTitle` empty, so every chrome button would read as just "button".
struct ChromeButton: View {
    let title: String
    var glass = false
    var size: CGFloat = 12
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(GhostButtonStyle(glass: glass, size: size))
            .accessibilityLabel(title)
    }
}

struct AmberButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.onAmber)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(Theme.amber.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 8))
    }
}
