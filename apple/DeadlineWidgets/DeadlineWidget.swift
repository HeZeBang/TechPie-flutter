import SwiftUI
import WidgetKit

struct DeadlineEntry: TimelineEntry {
  let date: Date
  let state: DeadlineSnapshotState
}

struct DeadlineProvider: TimelineProvider {
  func placeholder(in context: Context) -> DeadlineEntry {
    DeadlineEntry(date: Date(), state: .notSynced)
  }

  func getSnapshot(in context: Context, completion: @escaping (DeadlineEntry) -> Void) {
    let now = Date()
    completion(DeadlineEntry(date: now, state: read()))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<DeadlineEntry>) -> Void) {
    let now = Date()
    let state = read()
    let dates: [Date]
    if case .ready(let snapshot) = state { dates = snapshot.timelineDates(after: now) }
    else { dates = [now, now.addingTimeInterval(24 * 3600)] }
    completion(Timeline(entries: dates.map { DeadlineEntry(date: $0, state: state) }, policy: .atEnd))
  }

  private func read() -> DeadlineSnapshotState {
    DeadlineSnapshotStore.configured()?.read() ?? .unavailable
  }
}

#if os(macOS)
@main
#endif
struct DeadlineWidget: Widget {
  static let kind = "DeadlineWidget"
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: Self.kind, provider: DeadlineProvider()) { entry in
      DeadlineWidgetView(entry: entry)
    }
    .configurationDisplayName("deadline.widget.title")
    .description("deadline.widget.description")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}

struct DeadlineWidgetView: View {
  let entry: DeadlineEntry
  @Environment(\.widgetFamily) private var family
  @Environment(\.locale) private var locale
  @Environment(\.calendar) private var calendar

  private var limit: Int {
    switch family { case .systemSmall: return 2; case .systemMedium: return 4; default: return 8 }
  }

  var body: some View {
    Group {
      if #available(iOS 17.0, macOS 14.0, *) {
        content.containerBackground(for: .widget) { Color.widgetBackground }
      } else {
        content.padding(16).background(Color.widgetBackground)
      }
    }
    .widgetURL(URL(string: "techpie://deadlines"))
  }

  private var content: some View {
    VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : family == .systemMedium ? 4 : 10) {
      HStack {
        Text("deadline.widget.title").font(.system(size: 12, weight: .semibold))
        Spacer(minLength: 4)
        Text("TechPie").font(.system(size: 10, weight: .medium)).foregroundColor(.secondary)
      }.frame(height: 16, alignment: .leading)
      switch entry.state {
      case .notSynced: message("deadline.widget.notSynced", icon: "arrow.triangle.2.circlepath")
      case .unavailable: message("deadline.widget.unavailable", icon: "exclamationmark.circle")
      case .ready(let snapshot):
        let items = snapshot.upcoming(at: entry.date, limit: limit)
        if items.isEmpty {
          message("deadline.widget.empty", icon: "checkmark.circle")
        } else if items.count == 1 {
          single(items[0])
        } else {
          VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
              if index > 0 {
                Divider().opacity(0.45).padding(.vertical, family == .systemSmall ? 5 : family == .systemMedium ? 0.5 : 3)
              }
              if family == .systemSmall {
                compactRow(item)
              } else {
                listRow(item, spacious: family == .systemLarge && items.count <= 4)
              }
            }
          }.frame(maxHeight: .infinity, alignment: .top)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private func message(_ text: LocalizedStringKey, icon: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Spacer(minLength: 0)
      Image(systemName: icon).font(.system(size: 22)).foregroundColor(.secondary).accessibilityHidden(true)
      Text(text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
  }

  private func icon(_ item: DeadlineItem, size: CGFloat = 11) -> some View {
    Image(systemName: item.kind == .exam ? "calendar.badge.clock" : "doc.text")
      .font(.system(size: size)).foregroundColor(item.kind == .exam ? .orange : .accentColor)
      .frame(width: size + 2).accessibilityHidden(true)
  }

  private func label(_ item: DeadlineItem, compact: Bool) -> String {
    DeadlineDateLabel.string(for: item.due, at: entry.date, compact: compact, calendar: calendar, locale: locale)
  }

  private func accessibility(_ item: DeadlineItem) -> String {
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.timeZone = calendar.timeZone
    formatter.dateStyle = .long
    formatter.timeStyle = .short
    let remaining = DeadlineSnapshot.remainingHours(item, at: entry.date).map {
      "\(NSLocalizedString("deadline.widget.remaining", comment: "Remaining time")), \(remainingLabel($0))"
    } ?? ""
    return "\(item.title), \(item.course), \(item.kind.rawValue), \(formatter.string(from: item.due)), \(remaining)"
  }

  private func compactRow(_ item: DeadlineItem) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 3) {
        icon(item)
        Text(item.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
      }
      HStack(spacing: 3) {
        Text(item.course).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
        Spacer(minLength: 0)
        remainingTime(item, size: 10, width: 64)
      }.frame(height: 12)
      Text(label(item, compact: true)).font(.system(size: 10)).lineLimit(1).minimumScaleFactor(0.9)
    }
    .frame(height: 43, alignment: .topLeading)
    .accessibilityElement(children: .ignore).accessibilityLabel(accessibility(item))
  }

  private func listRow(_ item: DeadlineItem, spacious: Bool) -> some View {
    HStack(alignment: .center, spacing: 6) {
      icon(item)
      VStack(alignment: .leading, spacing: spacious ? 4 : 1) {
        Text(item.title).font(.system(size: spacious ? 15 : 12, weight: .semibold)).lineLimit(1)
        HStack(spacing: 6) {
          Text(item.course).lineLimit(1)
          Text(label(item, compact: false)).lineLimit(1).fixedSize()
        }.font(.system(size: spacious ? 11 : 10)).foregroundColor(.secondary)
      }.frame(maxWidth: .infinity, alignment: .leading)
      remainingTime(item, size: spacious ? 13 : 11, width: spacious ? 88 : 78)
    }
    .frame(height: spacious ? 48 : 25)
    .accessibilityElement(children: .ignore).accessibilityLabel(accessibility(item))
  }

  @ViewBuilder
  private func single(_ item: DeadlineItem) -> some View {
    if family == .systemMedium {
      HStack(alignment: .center, spacing: 16) {
        details(item, titleSize: 20, secondarySize: 12)
          .frame(maxWidth: .infinity, alignment: .leading)
        VStack(alignment: .trailing, spacing: 4) {
          Text("deadline.widget.remaining").font(.system(size: 10)).foregroundColor(.secondary)
          remainingTime(item, size: 30, width: 116)
        }.frame(width: 116, alignment: .trailing)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
      .accessibilityElement(children: .ignore).accessibilityLabel(accessibility(item))
    } else {
      VStack(alignment: .leading, spacing: family == .systemSmall ? 2 : 12) {
        details(item, titleSize: family == .systemSmall ? 16 : 26,
                secondarySize: family == .systemSmall ? 11 : 13)
        Spacer(minLength: 0)
        if family != .systemSmall {
          Text("deadline.widget.remaining").font(.system(size: 12)).foregroundColor(.secondary)
        }
        remainingTime(item, size: family == .systemSmall ? 24 : 44, alignment: .leading)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
      .accessibilityElement(children: .ignore).accessibilityLabel(accessibility(item))
    }
  }

  private func details(_ item: DeadlineItem, titleSize: CGFloat, secondarySize: CGFloat) -> some View {
    VStack(alignment: .leading, spacing: family == .systemSmall ? 3 : 6) {
      HStack(alignment: .firstTextBaseline, spacing: 5) {
        icon(item, size: family == .systemSmall ? 11 : 14)
        Text(item.title).font(.system(size: titleSize, weight: .semibold)).lineLimit(2)
      }
      Text(item.course).font(.system(size: secondarySize)).foregroundColor(.secondary).lineLimit(1)
      Text(label(item, compact: false)).font(.system(size: secondarySize))
        .foregroundColor(.secondary).lineLimit(1).minimumScaleFactor(0.8)
    }
  }

  @ViewBuilder private func remainingTime(_ item: DeadlineItem, size: CGFloat,
                                         width: CGFloat? = nil, alignment: Alignment = .trailing) -> some View {
    if let hours = DeadlineSnapshot.remainingHours(item, at: entry.date) {
      Text(remainingLabel(hours))
        .font(.system(size: size, weight: .semibold, design: .rounded))
        .foregroundColor(hours == 0 ? .red : hours < 24 ? .accentColor : .primary)
        .lineLimit(1).minimumScaleFactor(0.5)
        .frame(width: width, alignment: alignment)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
    }
  }

  private func remainingLabel(_ hours: Int) -> String {
    if hours == 0 { return NSLocalizedString("deadline.widget.dueSoon", comment: "Less than one hour remains") }
    if hours < 24 {
      return String.localizedStringWithFormat(NSLocalizedString("deadline.widget.hours", comment: "Full remaining hours"), hours)
    }
    return String.localizedStringWithFormat(NSLocalizedString("deadline.widget.daysHours", comment: "Full remaining days and hours"), hours / 24, hours % 24)
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
