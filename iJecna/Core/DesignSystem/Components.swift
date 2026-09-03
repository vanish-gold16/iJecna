import SwiftUI

// MARK: - Skleněné plochy

/// Karta ze skla. Používá se pro plovoucí obsah nad pozadím —
/// ne pro husté seznamy, tam by se sklo vrstvilo na sklo.
struct GlassCard<Content: View>: View {
    var tint: Color?
    var radius: CGFloat = Theme.cardRadius
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(glass, in: .rect(cornerRadius: radius, style: .continuous))
    }

    private var glass: Glass {
        if let tint { .regular.tint(tint.opacity(0.30)) } else { .regular }
    }
}

/// Neprůhledná karta pro obsahové seznamy. Sklo si šetříme na ovládací prvky.
struct ContentCard<Content: View>: View {
    var radius: CGFloat = Theme.cardRadius
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: .rect(cornerRadius: radius, style: .continuous))
    }
}

/// Nadpis sekce s volitelnou akcí vpravo.
struct SectionHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.weight(.semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 4)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

// MARK: - Známky

/// Kolečko se známkou. Velká známka (váha 2) je znatelně větší než malá.
struct GradeBadge: View {
    let grade: Grade
    var size: Size = .regular

    enum Size {
        case small, regular, large

        func diameter(isSmallGrade: Bool) -> CGFloat {
            let base: CGFloat = switch self {
            case .small: 26
            case .regular: 34
            case .large: 52
            }
            return isSmallGrade ? base * 0.78 : base
        }

        var font: Font {
            switch self {
            case .small: .caption.weight(.bold)
            case .regular: .callout.weight(.bold)
            case .large: .title.weight(.bold)
            }
        }
    }

    private var color: Color {
        grade.isNotWritten ? .secondary : Theme.gradeColor(for: grade.value)
    }

    var body: some View {
        let diameter = size.diameter(isSmallGrade: grade.isSmall)
        Text(grade.label)
            .font(size.font)
            .monospacedDigit()
            .foregroundStyle(.white)
            .frame(width: diameter, height: diameter)
            .background(color.gradient, in: .circle)
            .overlay {
                // Malá známka má tenčí prstenec — váha je poznat i bez čtení.
                Circle()
                    .strokeBorder(.white.opacity(grade.isSmall ? 0.0 : 0.35), lineWidth: 2)
            }
            .accessibilityElement()
            .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let value = grade.isNotWritten ? "nepsáno" : "známka \(grade.value)"
        return "\(value), \(grade.weightDescription)\(grade.detail.map { ", \($0)" } ?? "")"
    }
}

/// Uzavřená známka nebo varování na konci pololetí.
struct FinalGradeBadge: View {
    let finalGrade: FinalGrade

    var body: some View {
        Text(finalGrade.label)
            .font(.callout.weight(.heavy))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(color.gradient, in: .rect(cornerRadius: 8, style: .continuous))
            .accessibilityLabel(finalGrade.explanation)
    }

    private var color: Color {
        switch finalGrade {
        case .grade(let value): Theme.gradeColor(for: value)
        case .excused: .secondary
        default: .orange
        }
    }
}

/// Číselný průměr s barvou odpovídající hodnotě.
struct AverageLabel: View {
    let average: Double?
    var style: Style = .inline

    enum Style { case inline, prominent }

    var body: some View {
        if let average {
            Text(average.averageFormatted)
                .font(style == .prominent ? .largeTitle.weight(.bold) : .subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.averageColor(for: average))
                .contentTransition(.numericText())
        } else {
            Text("—")
                .font(style == .prominent ? .largeTitle.weight(.bold) : .subheadline.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }
}

/// Barevná zkratka předmětu — rychlá vizuální kotva v seznamech.
struct SubjectMonogram: View {
    let name: DisplayName
    var size: CGFloat = 42

    private var color: Color { .stable(for: name.full) }

    var body: some View {
        Text(name.abbreviation)
            .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .padding(.horizontal, 4)
            .frame(width: size, height: size)
            .background(color.gradient, in: .rect(cornerRadius: size * 0.3, style: .continuous))
    }
}

// MARK: - Stavy

/// Prázdný stav se symbolem, nadpisem a popisem.
struct EmptyStateView: View {
    let symbol: String
    let title: String
    var message: String?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            if let message { Text(message) }
        }
    }
}

/// Chybový stav s možností opakování.
struct ErrorStateView: View {
    let error: JecnaError
    var retry: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(error.errorDescription ?? "Něco se pokazilo", systemImage: error.symbolName)
        } description: {
            if let suggestion = error.recoverySuggestion {
                Text(suggestion)
            }
        } actions: {
            if let retry {
                Button("Zkusit znovu", action: retry)
                    .buttonStyle(.glassProminent)
            }
        }
    }
}

/// Kroužek postupu hodiny.
///
/// `ProgressView(value:)` se stylem `.circular` se na iOSu vykreslí jako
/// nekonečný spinner — určitý postup v kruhu systém nenabízí, kreslíme si ho sami.
struct LessonProgressRing: View {
    let progress: Double
    var lineWidth: CGFloat = 3
    var tint: Color = Theme.accent

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .accessibilityElement()
        .accessibilityLabel("Postup hodiny")
        .accessibilityValue("\(Int(progress * 100)) procent")
    }
}

/// Odznak „Nové“ u čerstvě přidaných známek.
struct NewBadge: View {
    var body: some View {
        Text("Nové")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Theme.accent.gradient, in: .capsule)
            // Bez tohohle se odznak v těsném řádku zalomí na dva řádky
            // a ukousne místo názvu předmětu.
            .fixedSize()
    }
}

// MARK: - Pomocné modifikátory

extension View {
    /// Skryje prvek pro VoiceOver, když nese jen dekorativní význam.
    func decorative() -> some View {
        accessibilityHidden(true)
    }
}
