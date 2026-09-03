import SwiftUI

struct SubjectDetailView: View {
    let subject: Subject
    @Environment(AppModel.self) private var model
    @State private var predictedValue: Int = 1
    @State private var predictedIsSmall = false
    @State private var showsPredictor = false

    var body: some View {
        ZStack {
            AuroraBackground()

            ScrollView {
                VStack(spacing: 20) {
                    header

                    ForEach(subject.parts) { part in
                        partSection(part)
                    }

                    predictor
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 44)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
        }
        .navigationTitle(subject.name.abbreviation)
        .navigationSubtitle(subject.name.full)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Hlavička

    private var header: some View {
        GlassCard(tint: subject.average.map { Theme.averageColor(for: $0) }) {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Vážený průměr")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    AverageLabel(average: subject.average, style: .prominent)
                    if let average = subject.average {
                        Text("zaokrouhleno na \(average.roundedGrade)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 8) {
                    if let finalGrade = subject.finalGrade {
                        VStack(spacing: 4) {
                            FinalGradeBadge(finalGrade: finalGrade)
                            Text("uzavřeno")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Text("\(subject.gradeCount) známek")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Části předmětu

    @ViewBuilder
    private func partSection(_ part: SubjectPart) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if subject.isSplit {
                SectionHeader(
                    part.title ?? "Ostatní",
                    subtitle: part.average.map { "průměr \($0.averageFormatted)" }
                )
            }

            if part.grades.isEmpty {
                ContentCard {
                    Text("Zatím žádné známky")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(16)
                }
            } else {
                ContentCard {
                    VStack(spacing: 0) {
                        let sorted = part.grades.sorted {
                            ($0.receivedAt ?? .distantPast) > ($1.receivedAt ?? .distantPast)
                        }
                        ForEach(Array(sorted.enumerated()), id: \.element.id) { index, grade in
                            if index > 0 { Divider().padding(.leading, 62) }
                            GradeDetailRow(grade: grade, isNew: model.newGrades.isNew(grade))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Predikce

    private var predictor: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Co když dostanu…", subtitle: "Spočítá nový průměr předmětu") {
                Button(showsPredictor ? "Skrýt" : "Zkusit") {
                    withAnimation(.smooth) { showsPredictor.toggle() }
                }
                .font(.subheadline)
            }

            if showsPredictor {
                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 10) {
                            ForEach(Array(1...5), id: \.self) { value in
                                PredictorGradeButton(
                                    value: value,
                                    isSelected: predictedValue == value
                                ) {
                                    predictedValue = value
                                    Haptics.selection()
                                }
                            }
                        }

                        Picker("Váha", selection: $predictedIsSmall) {
                            Text("Velká známka").tag(false)
                            Text("Malá známka").tag(true)
                        }
                        .pickerStyle(.segmented)

                        Divider()

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Nový průměr")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                AverageLabel(average: predictedAverage, style: .prominent)
                            }

                            Spacer()

                            if let current = subject.average, let predicted = predictedAverage {
                                let delta = predicted - current
                                Label(
                                    String(format: "%+.2f", delta),
                                    systemImage: delta > 0 ? "arrow.up.right" : (delta < 0 ? "arrow.down.right" : "equal")
                                )
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(delta > 0 ? .red : (delta < 0 ? .green : .secondary))
                            }
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var predictedAverage: Double? {
        Grade.weightedAverage(of: subject.allGrades, adding: predictedValue, isSmall: predictedIsSmall)
    }
}

// MARK: - Řádek známky

struct GradeDetailRow: View {
    let grade: Grade
    var isNew: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            GradeBadge(grade: grade)
                .overlay(alignment: .topTrailing) {
                    if isNew {
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 9, height: 9)
                            .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 1.5))
                            .offset(x: 2, y: -2)
                    }
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(grade.detail ?? "Bez popisu")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(grade.detail == nil ? .secondary : .primary)

                HStack(spacing: 6) {
                    Text(grade.weightDescription)
                    if let teacher = grade.teacher {
                        Text("•")
                        Text(teacher.full)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                if grade.isNotWritten {
                    Label("Nezapočítává se do průměru", systemImage: "minus.circle")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 8)

            if let date = grade.receivedAt {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(DateFormatter.jecnaDayMonth.string(from: date))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(date, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

/// Jedno tlačítko v predikci známky.
private struct PredictorGradeButton: View {
    let value: Int
    let isSelected: Bool
    let action: () -> Void

    private var color: Color { Theme.gradeColor(for: value) }

    var body: some View {
        Button(action: action) {
            Text("\(value)")
                .font(.headline.weight(.bold))
                .foregroundStyle(isSelected ? Color.white : color)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(
                    isSelected ? AnyShapeStyle(color.gradient) : AnyShapeStyle(color.opacity(0.14)),
                    in: .rect(cornerRadius: 12, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Známka \(value)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
