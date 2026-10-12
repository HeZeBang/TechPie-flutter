import SwiftUI
import WidgetKit
import DeadlineWidgetSupport

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
    .widgetURL(URL(string: "\(Bundle.main.object(forInfoDictionaryKey: "TechPieWidgetURLScheme") as? String ?? "techpie")://deadlines"))
  }

  private var content: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 5) {
        Image(systemName: "checklist").foregroundColor(.accentColor).accessibilityHidden(true)
        Text("deadline.widget.title").fontWeight(.semibold)
      }.font(.system(size: 12)).frame(height: 16, alignment: .leading)
      switch entry.state {
      case .notSynced: message("deadline.widget.notSynced", icon: "arrow.triangle.2.circlepath")
      case .unavailable: message("deadline.widget.unavailable", icon: "exclamationmark.circle")
      case .ready(let snapshot):
        let items = snapshot.upcoming(at: entry.date, limit: limit)
        if items.isEmpty {
          message("deadline.widget.empty", icon: "checkmark.circle")
        } else if family == .systemSmall && items.count == 1 {
          single(items[0])
        } else {
          VStack(alignment: .leading, spacing: family == .systemSmall ? 8 : 5) {
            ForEach(items) { item in
              if family == .systemSmall { compactRow(item) } else { listRow(item) }
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

  private func icon(_ item: DeadlineItem) -> some View {
    Image(systemName: item.kind == .exam ? "calendar.badge.clock" : "doc.text")
      .font(.system(size: 10)).foregroundColor(item.kind == .exam ? .orange : .accentColor)
      .frame(width: 13).accessibilityHidden(true)
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
    return "\(item.title), \(item.course), \(item.kind.rawValue), \(formatter.string(from: item.due))"
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

  private func listRow(_ item: DeadlineItem) -> some View {
    HStack(alignment: .center, spacing: 6) {
      icon(item)
      VStack(alignment: .leading, spacing: 1) {
        Text(item.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
        HStack(spacing: 6) {
          Text(item.course).lineLimit(1)
          Text(label(item, compact: false)).lineLimit(1).fixedSize()
        }.font(.system(size: 10)).foregroundColor(.secondary)
      }.frame(maxWidth: .infinity, alignment: .leading)
      remainingTime(item, size: 11, width: 78)
    }
    .frame(height: 25)
    .accessibilityElement(children: .ignore).accessibilityLabel(accessibility(item))
  }

  private func single(_ item: DeadlineItem) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .top, spacing: 4) {
        icon(item).padding(.top, 4)
        Text(item.title).font(.system(size: 16, weight: .semibold)).lineLimit(2)
      }
      Text(item.course).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
      Text(label(item, compact: false)).font(.system(size: 11)).lineLimit(1).minimumScaleFactor(0.8)
      Spacer(minLength: 0)
      remainingTime(item, size: 22, width: 130)
    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
      .accessibilityElement(children: .ignore).accessibilityLabel(accessibility(item))
  }

  @ViewBuilder private func remainingTime(_ item: DeadlineItem, size: CGFloat, width: CGFloat) -> some View {
    if let hours = DeadlineSnapshot.remainingHours(item, at: entry.date) {
      Text(hours == 0
        ? NSLocalizedString("deadline.widget.dueSoon", comment: "Less than one hour remains")
        : String.localizedStringWithFormat(NSLocalizedString("deadline.widget.hours", comment: "Full remaining hours"), hours))
        .font(.system(size: size, weight: .medium, design: .monospaced))
        .foregroundColor(hours == 0 ? .red : .orange).frame(width: width, alignment: .trailing)
        .multilineTextAlignment(.trailing).lineLimit(1).minimumScaleFactor(0.9)
    }
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
