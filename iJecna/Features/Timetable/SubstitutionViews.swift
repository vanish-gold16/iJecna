import SwiftUI

/// Označení hodiny, se kterou hýbe mimořádný rozvrh.
struct SubstitutionBadge: View {
    let change: SubstitutionChange

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 9, weight: .bold))
            Text(change.displayText)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.orange.gradient, in: .capsule)
        .accessibilityLabel("Změna v rozvrhu: \(change.displayText)")
    }
}

/// Poznámka ke dni z mimořádného rozvrhu — ředitelské volno, maturity a podobně.
struct SubstitutionDayBanner: View {
    let day: SubstitutionDay

    var body: some View {
        if day.hasAnything, !day.changes.contains(where: { $0 != nil }) || !day.isSchoolDay || day.note != nil {
            GlassCard(tint: day.isSchoolDay ? .orange : .red) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(
                        day.isSchoolDay ? "Mimořádný rozvrh" : "Dnes se neučí",
                        systemImage: day.isSchoolDay ? "arrow.triangle.2.circlepath" : "calendar.badge.exclamationmark"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(day.isSchoolDay ? .orange : .red)

                    if let note = day.note {
                        Text(note)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ForEach(day.announcements) { announcement in
                        if let text = announcement.textContent {
                            Text(text)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}

/// Seznam změn a nepřítomných učitelů pro jeden den.
struct SubstitutionSummary: View {
    let day: SubstitutionDay
    let periods: [LessonPeriod]

    private var changes: [(period: Int, change: SubstitutionChange)] {
        day.changes.enumerated().compactMap { index, change in
            guard let change else { return nil }
            return (index + 1, change)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !changes.isEmpty {
                SectionHeader("Změny v rozvrhu", subtitle: "\(changes.count) hodin")
                ContentCard {
                    VStack(spacing: 0) {
                        ForEach(Array(changes.enumerated()), id: \.element.period) { index, item in
                            if index > 0 { Divider().padding(.leading, 56) }
                            HStack(spacing: 12) {
                                Text("\(item.period).")
                                    .font(.headline.weight(.bold))
                                    .monospacedDigit()
                                    .foregroundStyle(.orange)
                                    .frame(width: 32)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.change.displayText)
                                        .font(.subheadline.weight(.medium))
                                    if let period = periods.first(where: { $0.number == item.period }) {
                                        Text(period.displayRange)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer(minLength: 0)

                                if !item.change.isConfirmed {
                                    Text("upřesní se")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                        }
                    }
                }
            }

            if !day.absences.isEmpty {
                SectionHeader("Nepřítomní učitelé", subtitle: "\(day.absences.count)")
                ContentCard {
                    VStack(spacing: 0) {
                        ForEach(Array(day.absences.enumerated()), id: \.element.id) { index, absence in
                            if index > 0 { Divider().padding(.leading, 14) }
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(absence.displayName)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                    Text(absence.scopeDescription)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Text(absence.teacherCode.uppercased())
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(14)
                        }
                    }
                }
            }
        }
    }
}
