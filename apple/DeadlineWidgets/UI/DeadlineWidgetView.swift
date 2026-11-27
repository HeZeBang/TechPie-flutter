import SwiftUI
import WidgetKit
import DeadlineWidgetSupport

struct DeadlineWidgetView: View {
  let entry: DeadlineEntry
  @Environment(\.widgetFamily) private var family
  @Environment(\.locale) private var locale
  @Environment(\.calendar) private var calendar
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    TpWidgetFullColorReader { isFullColor in
      rootContent(isFullColor: isFullColor)
    }
    .widgetURL(TechPieWidgetURL.deadlines())
  }

  @ViewBuilder
  private func rootContent(isFullColor: Bool) -> some View {
    #if os(iOS)
    if #available(iOS 16.0, *) {
      switch family {
      case .accessoryRectangular:
        rectangularAccessory
          .tpLockScreenContainerBackground()
      case .accessoryInline:
        inlineAccessory
          .tpLockScreenContainerBackground()
      default:
        desktopOrHomeCard(isFullColor: isFullColor)
          .tpWidgetSurfaceBackground(isFullColor: isFullColor, colorScheme: colorScheme)
      }
    } else {
      desktopOrHomeCard(isFullColor: isFullColor)
        .tpWidgetSurfaceBackground(isFullColor: isFullColor, colorScheme: colorScheme)
    }
    #else
    desktopOrHomeCard(isFullColor: isFullColor)
      .tpWidgetSurfaceBackground(isFullColor: isFullColor, colorScheme: colorScheme)
    #endif
  }

  @ViewBuilder
  private func desktopOrHomeCard(isFullColor: Bool) -> some View {
    switch entry.state {
    case .notSynced:
      messageState("deadline.widget.notSynced", icon: "arrow.triangle.2.circlepath")
    case .unavailable:
      messageState("deadline.widget.unavailable", icon: "exclamationmark.circle")
    case .ready(let snapshot):
      let all = snapshot.upcoming(at: entry.date, limit: .max)
      if all.isEmpty {
        messageState("deadline.widget.empty", icon: "checkmark.circle")
      } else {
        layout(all, isFullColor: isFullColor)
      }
    }
  }

  @ViewBuilder
  private func layout(_ all: [DeadlineItem], isFullColor: Bool) -> some View {
    switch family {
    case .systemSmall:
      card(total: all.count, more: all.count - 1) {
        hero(all[0], large: false, isFullColor: isFullColor)
      }
    case .systemMedium where all.count == 1:
      card(total: 1, more: 0) {
        wideHero(all[0], isFullColor: isFullColor)
      }
    case .systemMedium:
      let shown = Array(all.prefix(3))
      card(total: all.count, more: all.count - shown.count) {
        VStack(alignment: .leading, spacing: 7) {
          ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
            deadlineRow(item, timeOnly: false, isFullColor: isFullColor)
            if index < shown.count - 1 {
              TpWidgetColor.divider(colorScheme).frame(height: 0.5)
            }
          }
        }
      }
    case _ where all.count == 1:
      card(total: 1, more: 0) {
        hero(all[0], large: true, isFullColor: isFullColor)
      }
    default:
      let sections = sections(all)
      let shownCount = sections.reduce(0) { $0 + $1.items.count }
      card(total: all.count, more: all.count - shownCount) {
        VStack(alignment: .leading, spacing: 10) {
          ForEach(sections) { section in
            VStack(alignment: .leading, spacing: 5) {
              Text(section.title)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(TpWidgetColor.brandInk(colorScheme))
                .tpAccentable()
              ForEach(section.items) { item in
                deadlineRow(item, timeOnly: section.day <= .tomorrow, isFullColor: isFullColor)
              }
            }
          }
        }
      }
    }
  }

  private func card<Rows: View>(
    total: Int,
    more: Int,
    @ViewBuilder _ rows: () -> Rows
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      header(total: total, more: more)
      rows()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private func header(total: Int, more: Int) -> some View {
    TpWidgetHeader(
      icon: "checkmark.circle.fill",
      titleKey: "deadline.widget.title",
      badgeText: total > 0 ? "\(total)" : nil
    ) {
      if more > 0 {
        Text(WidgetL10n.format("deadline.widget.more", more))
          .font(.system(size: 10.5, weight: .medium).monospacedDigit())
          .foregroundColor(TpWidgetColor.textMuted(colorScheme))
          .lineLimit(1)
      }
    }
  }

  private func messageState(_ textKey: String, icon: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      header(total: 0, more: 0)
      TpWidgetEmptyState(icon: icon, messageKey: textKey)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  // MARK: - Rows & Hero Layouts

  private func deadlineRow(
    _ item: DeadlineItem,
    timeOnly: Bool,
    isFullColor: Bool
  ) -> some View {
    HStack(alignment: .center, spacing: 8) {
      TpAccentBar(color: urgencyBarColor(for: item, isFullColor: isFullColor))
        .frame(height: 26)
      VStack(alignment: .leading, spacing: 1.5) {
        Text(item.title)
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(TpWidgetColor.textPrimary(colorScheme))
          .lineLimit(1)
        detail(item, secondary(item, timeOnly: timeOnly), size: 11)
      }
      Spacer(minLength: 6)
      countdownPill(item, size: 11.5, isFullColor: isFullColor)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibility(item))
  }

  private func hero(_ item: DeadlineItem, large: Bool, isFullColor: Bool) -> some View {
    let urgencyColor = urgencyBarColor(for: item, isFullColor: isFullColor)
    return HStack(alignment: .top, spacing: 8) {
      TpAccentBar(color: urgencyColor)
      VStack(alignment: .leading, spacing: 2) {
        Text(item.title)
          .font(.system(size: large ? 20 : 14, weight: .semibold))
          .foregroundColor(TpWidgetColor.textPrimary(colorScheme))
          .lineLimit(2)
          .layoutPriority(1)
        if !item.subtitle.isEmpty {
          Text(item.subtitle)
            .font(.system(size: large ? 13 : 11))
            .foregroundColor(TpWidgetColor.textMuted(colorScheme))
            .lineLimit(2)
        }
        Spacer(minLength: large ? 12 : 4)
        remainingHeroText(item, size: large ? 38 : 26)
          .layoutPriority(1)
        detail(item, date(item, timeOnly: false, weekday: true), size: large ? 12.5 : 10.5)
          .layoutPriority(1)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibility(item))
  }

  private func wideHero(_ item: DeadlineItem, isFullColor: Bool) -> some View {
    HStack(alignment: .center, spacing: 12) {
      TpAccentBar(color: urgencyBarColor(for: item, isFullColor: isFullColor))
        .frame(height: 46)
      VStack(alignment: .leading, spacing: 4) {
        Text(item.title)
          .font(.system(size: 16, weight: .semibold))
          .foregroundColor(TpWidgetColor.textPrimary(colorScheme))
          .lineLimit(2)
        detail(item, secondary(item, timeOnly: false), size: 12)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      remainingHeroText(item, size: 28)
    }
    .frame(maxHeight: .infinity)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibility(item))
  }

  // MARK: - Helpers

  private func urgencyBarColor(for item: DeadlineItem, isFullColor: Bool) -> Color {
    if !isFullColor { return Color.primary.opacity(0.6) }
    switch item.urgency(at: entry.date) {
    case .overdue, .urgent:
      return TpWidgetColor.dangerRed(colorScheme)
    case .soon:
      return TpWidgetColor.warningAmber(colorScheme)
    case .upcoming:
      return TpWidgetColor.textMuted(colorScheme).opacity(0.45)
    }
  }

  @ViewBuilder
  private func countdownPill(_ item: DeadlineItem, size: CGFloat, isFullColor: Bool) -> some View {
    if let hours = DeadlineSnapshot.remainingHours(item, at: entry.date) {
      let value = DeadlineRemaining(hours: hours)
      let palette = countdownColors(for: item.urgency(at: entry.date), isFullColor: isFullColor)
      TpCountPill(text: label(value), foreground: palette.fg, background: palette.bg, fontSize: size)
        .tpAccentable(value.isUrgent)
    }
  }

  private func countdownColors(for urgency: DeadlineUrgency, isFullColor: Bool) -> (fg: Color, bg: Color) {
    guard isFullColor else {
      return (.primary, Color.primary.opacity(0.12))
    }
    switch urgency {
    case .overdue, .urgent:
      let red = TpWidgetColor.dangerRed(colorScheme)
      return (red, red.opacity(colorScheme == .dark ? 0.18 : 0.10))
    case .soon:
      let amber = TpWidgetColor.warningAmber(colorScheme)
      return (amber, amber.opacity(colorScheme == .dark ? 0.16 : 0.10))
    case .upcoming:
      return (TpWidgetColor.textSecondary(colorScheme), TpWidgetColor.surfaceSubtle(colorScheme))
    }
  }

  @ViewBuilder
  private func remainingHeroText(_ item: DeadlineItem, size: CGFloat) -> some View {
    if let hours = DeadlineSnapshot.remainingHours(item, at: entry.date) {
      let value = DeadlineRemaining(hours: hours)
      Text(label(value))
        .font(.system(size: size, weight: .bold, design: .rounded).monospacedDigit())
        .foregroundColor(
          value.isUrgent
            ? TpWidgetColor.dangerRed(colorScheme)
            : TpWidgetColor.textPrimary(colorScheme)
        )
        .tpAccentable(value.isUrgent)
        .lineLimit(1)
        .minimumScaleFactor(0.65)
    }
  }

  private func detail(_ item: DeadlineItem, _ text: String, size: CGFloat) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 3) {
      Image(systemName: item.kind == .exam ? "calendar" : "doc.text")
        .font(.system(size: size - 1, weight: .semibold))
        .foregroundColor(TpWidgetColor.textMuted(colorScheme))
        .accessibilityHidden(true)
      Text(text)
        .font(.system(size: size))
        .foregroundColor(TpWidgetColor.textMuted(colorScheme))
        .lineLimit(1)
    }
  }

  private func secondary(_ item: DeadlineItem, timeOnly: Bool) -> String {
    let date = date(item, timeOnly: timeOnly, weekday: false)
    return item.subtitle.isEmpty ? date : "\(date) · \(item.subtitle)"
  }

  private func date(_ item: DeadlineItem, timeOnly: Bool, weekday: Bool) -> String {
    timeOnly
      ? DeadlineDateLabel.time(for: item.due, calendar: calendar, locale: locale)
      : DeadlineDateLabel.string(
        for: item.due,
        at: entry.date,
        compact: true,
        weekday: weekday,
        calendar: calendar,
        locale: locale
      )
  }

  private func label(_ value: DeadlineRemaining) -> String {
    switch value {
    case .dueSoon:
      return WidgetL10n.string("deadline.widget.dueSoon")
    case .hours(let hours):
      return WidgetL10n.format("deadline.widget.hours", hours)
    case .daysHours(let days, let hours):
      return WidgetL10n.format("deadline.widget.daysHours", days, hours)
    case .days(let days):
      return WidgetL10n.format("deadline.widget.days", days)
    }
  }

  private func accessibility(_ item: DeadlineItem) -> String {
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.timeZone = calendar.timeZone
    formatter.dateStyle = .long
    formatter.timeStyle = .short
    let remaining = DeadlineSnapshot.remainingHours(item, at: entry.date).map {
      "\(WidgetL10n.string("deadline.widget.remaining")), \(label(DeadlineRemaining(hours: $0)))"
    } ?? ""
    return [item.title, item.subtitle, item.kind.rawValue, formatter.string(from: item.due), remaining]
      .filter { !$0.isEmpty }
      .joined(separator: ", ")
  }

  // MARK: - Sections

  private struct Section: Identifiable {
    let day: DeadlineDay
    let items: [DeadlineItem]
    var id: Int { day.rawValue }
    var title: String {
      switch day {
      case .today: return WidgetL10n.string("deadline.widget.section.today")
      case .tomorrow: return WidgetL10n.string("deadline.widget.section.tomorrow")
      case .nextWeek: return WidgetL10n.string("deadline.widget.section.nextWeek")
      case .later: return WidgetL10n.string("deadline.widget.section.later")
      }
    }
  }

  private func sections(_ all: [DeadlineItem]) -> [Section] {
    var shown = Array(all.prefix(7))
    while true {
      let groups = DeadlineDay.group(shown, at: entry.date, calendar: calendar)
      if shown.count + groups.count <= 9 || shown.count <= 1 {
        return groups.map { Section(day: $0.day, items: $0.items) }
      }
      shown.removeLast()
    }
  }

  // MARK: - iOS Lock Screen Accessories (directly readable, not privacySensitive)

  #if os(iOS)
  @available(iOS 16.0, *)
  @ViewBuilder
  private var rectangularAccessory: some View {
    switch entry.state {
    case .notSynced:
      VStack(alignment: .leading, spacing: 2) {
        Label(LocalizedStringKey("deadline.widget.title"), systemImage: "checkmark.circle")
          .font(.system(size: 11, weight: .semibold))
        Text(LocalizedStringKey("deadline.widget.notSynced"))
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    case .unavailable:
      VStack(alignment: .leading, spacing: 2) {
        Label(LocalizedStringKey("deadline.widget.title"), systemImage: "checkmark.circle")
          .font(.system(size: 11, weight: .semibold))
        Text(LocalizedStringKey("deadline.widget.unavailable"))
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    case .ready(let snapshot):
      let items = snapshot.upcoming(at: entry.date, limit: 2)
      if items.isEmpty {
        VStack(alignment: .leading, spacing: 2) {
          Label(LocalizedStringKey("deadline.widget.title"), systemImage: "checkmark.circle")
            .font(.system(size: 11, weight: .semibold))
          Text(LocalizedStringKey("deadline.widget.empty"))
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      } else {
        VStack(alignment: .leading, spacing: 2) {
          Label(LocalizedStringKey("deadline.widget.title"), systemImage: "checkmark.circle")
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.secondary)
          ForEach(items) { item in
            HStack(spacing: 4) {
              Image(systemName: item.kind == .exam ? "calendar" : "doc.text")
                .font(.system(size: 10, weight: .semibold))
              Text(item.title)
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(1)
              Spacer(minLength: 4)
              if let hours = DeadlineSnapshot.remainingHours(item, at: entry.date) {
                let remaining = DeadlineRemaining(hours: hours)
                Text(label(remaining))
                  .font(.system(size: 11.5, weight: .bold).monospacedDigit())
                  .tpAccentable(remaining.isUrgent)
                  .lineLimit(1)
              }
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  @available(iOS 16.0, *)
  @ViewBuilder
  private var inlineAccessory: some View {
    if case .ready(let snapshot) = entry.state,
      let first = snapshot.upcoming(at: entry.date, limit: 1).first,
      let hours = DeadlineSnapshot.remainingHours(first, at: entry.date)
    {
      let rem = label(DeadlineRemaining(hours: hours))
      Label("\(first.title) · \(rem)", systemImage: first.kind == .exam ? "calendar" : "doc.text")
    } else {
      Label(LocalizedStringKey("deadline.widget.empty"), systemImage: "checkmark.circle")
    }
  }
  #endif
}
