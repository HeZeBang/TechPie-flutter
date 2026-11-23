import SwiftUI
import WidgetKit
import DeadlineWidgetSupport

struct DeadlineWidgetView: View {
  let entry: DeadlineEntry
  @Environment(\.widgetFamily) private var family
  @Environment(\.locale) private var locale
  @Environment(\.calendar) private var calendar

  var body: some View {
    Group {
      if #available(iOS 17.0, macOS 14.0, *) {
        content.containerBackground(for: .widget) { Color.widgetBackground }
      } else {
        content.padding(16).background(Color.widgetBackground)
      }
    }
    .widgetURL(URL(string: "\(Bundle.main.object(forInfoDictionaryKey: "TechPieWidgetURLScheme") as? String ?? "techpie")://deadlines"))
  }

  @ViewBuilder
  private var content: some View {
    switch entry.state {
    case .notSynced: message("deadline.widget.notSynced", icon: "arrow.triangle.2.circlepath")
    case .unavailable: message("deadline.widget.unavailable", icon: "exclamationmark.circle")
    case .ready(let snapshot):
      let all = snapshot.upcoming(at: entry.date, limit: .max)
      if all.isEmpty {
        message("deadline.widget.empty", icon: "checkmark.circle")
      } else {
        layout(all)
      }
    }
  }

  /// Small always shows the one deadline that matters next; medium and large
  /// list a few, and only fall back to that hero when there is just one.
  @ViewBuilder
  private func layout(_ all: [DeadlineItem]) -> some View {
    switch family {
    case .systemSmall:
      card(more: all.count - 1) { hero(all[0], large: false) }
    case .systemMedium where all.count == 1:
      card(more: 0) { wideHero(all[0]) }
    case .systemMedium:
      let shown = Array(all.prefix(3))
      card(more: all.count - shown.count) {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(shown) { row($0, timeOnly: false) }
        }
      }
    case _ where all.count == 1:
      card(more: 0) { hero(all[0], large: true) }
    default:
      let sections = sections(all)
      card(more: all.count - sections.reduce(0) { $0 + $1.items.count }) {
        VStack(alignment: .leading, spacing: 12) {
          ForEach(sections) { section in
            VStack(alignment: .leading, spacing: 6) {
              Text(section.title).font(.system(size: 11, weight: .semibold)).foregroundColor(.accentColor)
              ForEach(section.items) { row($0, timeOnly: section.day <= .tomorrow) }
            }
          }
        }
      }
    }
  }

  private func card<Rows: View>(more: Int, @ViewBuilder _ rows: () -> Rows) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      header(more: more)
      rows().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }

  /// The app's accent colour sits on structure — this header and the large
  /// widget's day headings — where it makes the widget recognisable without
  /// competing with the deadlines themselves, which stay neutral.
  private func header(more: Int) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text("deadline.widget.title").font(.system(size: 13, weight: .semibold))
        .foregroundColor(.accentColor).accentable()
      Spacer(minLength: 4)
      if more > 0 {
        Text(String.localizedStringWithFormat(NSLocalizedString("deadline.widget.more", comment: "Deadlines not shown"), more))
          .font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
      }
    }
  }

  private func message(_ text: LocalizedStringKey, icon: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      header(more: 0)
      Spacer(minLength: 0)
      Image(systemName: icon).font(.system(size: 22)).foregroundColor(.secondary).accessibilityHidden(true)
      Text(text).font(.system(size: 13)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
  }

  // MARK: - Layouts

  private func row(_ item: DeadlineItem, timeOnly: Bool) -> some View {
    HStack(alignment: .center, spacing: 8) {
      VStack(alignment: .leading, spacing: 1) {
        Text(item.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
        detail(item, secondary(item, timeOnly: timeOnly), size: 11)
      }
      Spacer(minLength: 8)
      remaining(item, size: 14, prominent: false)
    }
    .accessibilityElement(children: .ignore).accessibilityLabel(accessibility(item))
  }

  /// What is due sits under the header and when it is due closes the widget,
  /// at fixed sizes. The subtitle may take a second line, so a course name is
  /// usually shown in full; it gives that line up first when the title needs
  /// two. The date and subtitle each get a line of their own instead of
  /// truncating each other.
  private func hero(_ item: DeadlineItem, large: Bool) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 2) {
        Text(item.title).font(.system(size: large ? 22 : 14, weight: .semibold)).lineLimit(2)
          .layoutPriority(1)
        if !item.subtitle.isEmpty {
          Text(item.subtitle).font(.system(size: large ? 13 : 11)).foregroundColor(.secondary)
            .lineLimit(2)
        }
      }
      Spacer(minLength: large ? 12 : 6)
      remaining(item, size: large ? 44 : 30, prominent: true).layoutPriority(1)
      detail(item, date(item, timeOnly: false, weekday: true), size: large ? 13 : 11).layoutPriority(1)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .accessibilityElement(children: .ignore).accessibilityLabel(accessibility(item))
  }

  private func wideHero(_ item: DeadlineItem) -> some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(item.title).font(.system(size: 17, weight: .semibold)).lineLimit(2)
        detail(item, secondary(item, timeOnly: false), size: 12)
      }.frame(maxWidth: .infinity, alignment: .leading)
      remaining(item, size: 30, prominent: true)
    }
    .frame(maxHeight: .infinity)
    .accessibilityElement(children: .ignore).accessibilityLabel(accessibility(item))
  }

  // MARK: - Pieces

  /// A secondary line, led by a symbol for the item's kind. The shape alone
  /// tells the kinds apart — in grey, like the line it leads, so colour is
  /// left to urgency and survives a tinted or clear appearance unchanged.
  private func detail(_ item: DeadlineItem, _ text: String, size: CGFloat) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 3) {
      Image(systemName: item.kind == .exam ? "calendar" : "doc.text")
        .font(.system(size: size - 1, weight: .semibold))
        .foregroundColor(.secondary).accessibilityHidden(true)
      Text(text).font(.system(size: size)).foregroundColor(.secondary).lineLimit(1)
    }
  }

  /// Date first, so a long course name or location truncates instead of it.
  private func secondary(_ item: DeadlineItem, timeOnly: Bool) -> String {
    let date = date(item, timeOnly: timeOnly, weekday: false)
    return item.subtitle.isEmpty ? date : "\(date) · \(item.subtitle)"
  }

  private func date(_ item: DeadlineItem, timeOnly: Bool, weekday: Bool) -> String {
    timeOnly
      ? DeadlineDateLabel.time(for: item.due, calendar: calendar, locale: locale)
      : DeadlineDateLabel.string(for: item.due, at: entry.date, compact: true, weekday: weekday,
                                 calendar: calendar, locale: locale)
  }

  /// Red is kept for the one thing worth interrupting for: less than a day
  /// left. In a list the countdown otherwise steps back behind the titles, so
  /// each row has one heavy element; the hero's countdown is its focus.
  @ViewBuilder
  private func remaining(_ item: DeadlineItem, size: CGFloat, prominent: Bool) -> some View {
    if let hours = DeadlineSnapshot.remainingHours(item, at: entry.date) {
      let value = DeadlineRemaining(hours: hours)
      Text(label(value))
        .font(.system(size: size, weight: prominent || value.isUrgent ? .semibold : .medium, design: .rounded))
        .foregroundColor(value.isUrgent ? .red : prominent ? .primary : .secondary)
        .accentable(value.isUrgent)
        .lineLimit(1).minimumScaleFactor(0.6).fixedSize(horizontal: size < 20, vertical: false)
    }
  }

  private func label(_ value: DeadlineRemaining) -> String {
    switch value {
    case .dueSoon:
      return NSLocalizedString("deadline.widget.dueSoon", comment: "Less than one hour remains")
    case .hours(let hours):
      return String.localizedStringWithFormat(NSLocalizedString("deadline.widget.hours", comment: "Full remaining hours"), hours)
    case .daysHours(let days, let hours):
      return String.localizedStringWithFormat(NSLocalizedString("deadline.widget.daysHours", comment: "Full remaining days and hours"), days, hours)
    case .days(let days):
      return String.localizedStringWithFormat(NSLocalizedString("deadline.widget.days", comment: "Full remaining days"), days)
    }
  }

  private func accessibility(_ item: DeadlineItem) -> String {
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.timeZone = calendar.timeZone
    formatter.dateStyle = .long
    formatter.timeStyle = .short
    let remaining = DeadlineSnapshot.remainingHours(item, at: entry.date).map {
      "\(NSLocalizedString("deadline.widget.remaining", comment: "Remaining time")), \(label(DeadlineRemaining(hours: $0)))"
    } ?? ""
    return [item.title, item.subtitle, item.kind.rawValue, formatter.string(from: item.due), remaining]
      .filter { !$0.isEmpty }.joined(separator: ", ")
  }

  // MARK: - Large sections

  private struct Section: Identifiable {
    let day: DeadlineDay
    let items: [DeadlineItem]
    var id: Int { day.rawValue }
    var title: String {
      let key: String
      switch day {
      case .today: key = "deadline.widget.section.today"
      case .tomorrow: key = "deadline.widget.section.tomorrow"
      case .nextWeek: key = "deadline.widget.section.nextWeek"
      case .later: key = "deadline.widget.section.later"
      }
      return NSLocalizedString(key, comment: "Deadline day group")
    }
  }

  /// Up to seven rows, fewer when they spread over many days: a row and a
  /// section heading cost about the same height, and nine of them fill it.
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
}

private extension View {
  /// In a tinted or clear appearance the system splits the widget into an
  /// accent and a primary group; this puts a view in the accent group.
  @ViewBuilder func accentable(_ isAccent: Bool = true) -> some View {
    if #available(iOS 16.0, macOS 13.0, *) { widgetAccentable(isAccent) } else { self }
  }
}

private extension Color {
  static var widgetBackground: Color {
    #if os(macOS)
    Color(NSColor.windowBackgroundColor)
    #else
    Color(uiColor: .systemBackground)
    #endif
  }
}
