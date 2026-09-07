import SwiftUI

enum Theme {

    // MARK: - Barvy

    /// Základní barva aplikace. Modrá je blízko identitě školy, ale není to její znak.
    static let accent = Color(light: Color(red: 0.05, green: 0.42, blue: 0.78),
                              dark: Color(red: 0.36, green: 0.68, blue: 1.00))

    /// Odpadlá hodina. Zeleně schválně: pro studenta je to dobrá zpráva a barva
    /// se neplete s oranžovou (změna v rozvrhu) ani červenou (celý den se neučí).
    static let cancelled = Color(light: Color(hue: 0.42, saturation: 0.78, brightness: 0.58),
                                 dark: Color(hue: 0.42, saturation: 0.62, brightness: 0.85))

    /// Barva známky na škále 1 (zelená) → 5 (červená). „N“ je neutrálně šedá.
    static func gradeColor(for value: Int) -> Color {
        switch value {
        case 1: Color(light: Color(hue: 0.34, saturation: 0.80, brightness: 0.66),
                      dark: Color(hue: 0.34, saturation: 0.68, brightness: 0.86))
        case 2: Color(light: Color(hue: 0.22, saturation: 0.85, brightness: 0.62),
                      dark: Color(hue: 0.22, saturation: 0.72, brightness: 0.84))
        case 3: Color(light: Color(hue: 0.12, saturation: 0.92, brightness: 0.78),
                      dark: Color(hue: 0.13, saturation: 0.85, brightness: 0.90))
        case 4: Color(light: Color(hue: 0.06, saturation: 0.90, brightness: 0.86),
                      dark: Color(hue: 0.07, saturation: 0.82, brightness: 0.92))
        case 5: Color(light: Color(hue: 0.00, saturation: 0.82, brightness: 0.82),
                      dark: Color(hue: 0.00, saturation: 0.72, brightness: 0.92))
        default: Color.secondary
        }
    }

    /// Barva pro průměr — plynulý přechod mezi barvami sousedních známek.
    static func averageColor(for average: Double) -> Color {
        let clamped = min(5, max(1, average))
        let lower = Int(clamped)
        let upper = min(5, lower + 1)
        return gradeColor(for: lower).mix(with: gradeColor(for: upper), by: clamped - Double(lower))
    }

    /// Barva podle druhu vlastního záznamu.
    static func taskColor(for kind: StudyTaskKind) -> Color {
        switch kind {
        case .homework: accent
        case .test: .orange
        case .project: .purple
        case .note: .gray
        }
    }

    // MARK: - Tvary

    static let cardRadius: CGFloat = 22
    static let compactRadius: CGFloat = 16
    static let cardShape = RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
    static let compactShape = RoundedRectangle(cornerRadius: compactRadius, style: .continuous)
}

extension Color {
    /// Odstín odvozený z textu, stejný při každém spuštění.
    ///
    /// `String.hashValue` je ve Swiftu solený náhodným semínkem procesu,
    /// takže by předmět po každém startu aplikace dostal jinou barvu.
    static func stable(for text: String, saturation: Double = 0.55, brightness: Double = 0.72) -> Color {
        var hash: UInt64 = 5381
        for byte in text.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        return Color(hue: Double(hash % 360) / 360, saturation: saturation, brightness: brightness)
    }

    /// Dvojice barev pro světlý a tmavý režim.
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}

// MARK: - Pozadí

/// Jemné barevné pozadí. Bez něj sklo nemá co lámat a vypadá jako obyčejná šeď.
struct AuroraBackground: View {
    var tint: Color = Theme.accent
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                [0.0, 0.5], [0.5, 0.5], [1.0, 0.5],
                [0.0, 1.0], [0.5, 1.0], [1.0, 1.0],
            ],
            colors: colors
        )
        .ignoresSafeArea()
        .overlay(Color(.systemBackground).opacity(colorScheme == .dark ? 0.55 : 0.35))
        .ignoresSafeArea()
    }

    private var colors: [Color] {
        let base = Color(.systemBackground)
        let strength: Double = colorScheme == .dark ? 0.35 : 0.22
        return [
            tint.opacity(strength * 0.9), base, tint.opacity(strength * 0.5),
            base, tint.opacity(strength * 0.3), base,
            tint.opacity(strength * 0.4), base, tint.opacity(strength * 0.7),
        ]
    }
}

// MARK: - Haptika

enum Haptics {
    @MainActor
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    @MainActor
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    @MainActor
    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}
