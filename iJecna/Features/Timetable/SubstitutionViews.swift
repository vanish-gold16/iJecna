import SwiftUI

/// Označení hodiny, se kterou hýbe mimořádný rozvrh.
///
/// Odpadlá hodina má vlastní podobu — zelenou a se „zzz“. Je to jediná změna,
/// která pro studenta znamená volno, tak ať se nemusí luštit z textu buňky.
struct SubstitutionBadge: View {
    let change: SubstitutionChange

    private var isCancelled: Bool { change.isCancelled }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isCancelled ? "zzz" : "arrow.triangle.2.circlepath")
                .font(.system(size: 9, weight: .bold))
            Text(isCancelled ? "Odpadá" : change.displayText)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background((isCancelled ? Theme.cancelled : Color.orange).gradient, in: .capsule)
        .accessibilityLabel(isCancelled ? "Hodina odpadá" : "Změna v rozvrhu: \(change.displayText)")
    }
}

/// Šikmé proužky přes kartu odpadlé hodiny. Škrtnutý text sám o sobě zanikne,
/// šrafování je vidět i koutkem oka při rychlém projetí rozvrhu.
struct HatchPattern: View {
    var color: Color
    var spacing: CGFloat = 9
    var lineWidth: CGFloat = 2

    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += spacing
            }
            context.stroke(path, with: .color(color), lineWidth: lineWidth)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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

    /// Kolik hodin se mění a kolik z nich rovnou odpadá.
    private var changesSubtitle: String {
        let all = "\(changes.count) \(changes.count == 1 ? "hodina" : (changes.count < 5 ? "hodiny" : "hodin"))"
        let cancelled = day.cancelledCount
        guard cancelled > 0 else { return all }
        return "\(all) • \(cancelled) odpadá"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !changes.isEmpty {
                SectionHeader("Změny v rozvrhu", subtitle: changesSubtitle)
                ContentCard {
                    VStack(spacing: 0) {
                        ForEach(Array(changes.enumerated()), id: \.element.period) { index, item in
                            if index > 0 { Divider().padding(.leading, 56) }
                            changeRow(item)
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

    /// Řádek jedné změny. Odpadlá hodina je škrtnutá a zelená — v seznamu se
    /// pozná dřív, než se přečte, co v buňce vlastně stojí.
    private func changeRow(_ item: (period: Int, change: SubstitutionChange)) -> some View {
        let isCancelled = item.change.isCancelled

        return HStack(spacing: 12) {
            Text("\(item.period).")
                .font(.headline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(isCancelled ? Theme.cancelled : Color.orange)
                .strikethrough(isCancelled, color: Theme.cancelled)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.change.displayText)
                    .font(.subheadline.weight(.medium))
                    .strikethrough(isCancelled, color: .secondary)
                    .foregroundStyle(isCancelled ? Color.secondary : Color.primary)
                if let period = periods.first(where: { $0.number == item.period }) {
                    Text(period.displayRange)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            if isCancelled {
                Label("volno", systemImage: "zzz")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.cancelled)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.cancelled.opacity(0.14), in: .capsule)
            } else if !item.change.isConfirmed {
                Text("upřesní se")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background {
            if isCancelled {
                HatchPattern(color: Theme.cancelled.opacity(0.10), spacing: 10, lineWidth: 1.5)
            }
        }
    }
}
