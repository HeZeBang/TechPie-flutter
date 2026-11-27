import SwiftUI
import WidgetKit
import DeadlineWidgetSupport

struct DeadlineEntry: TimelineEntry {
  let date: Date
  let state: DeadlineSnapshotState
}

struct DeadlineProvider: TimelineProvider {
  func placeholder(in context: Context) -> DeadlineEntry {
    let now = Date()
    let sample = DeadlineSnapshot(
      writtenAt: now.timeIntervalSince1970,
      items: [
        DeadlineItem(
          id: "sample-1",
          kind: .assignment,
          title: WidgetL10n.string("deadline.widget.sampleTitle1"),
          subtitle: "CS101",
          dueAt: now.addingTimeInterval(5 * 3600).timeIntervalSince1970
        ),
        DeadlineItem(
          id: "sample-2",
          kind: .exam,
          title: WidgetL10n.string("deadline.widget.sampleTitle2"),
          subtitle: "SIST 1A-200",
          dueAt: now.addingTimeInterval(32 * 3600).timeIntervalSince1970
        ),
      ]
    )
    return DeadlineEntry(date: now, state: .ready(sample))
  }

  func getSnapshot(in context: Context, completion: @escaping (DeadlineEntry) -> Void) {
    let now = Date()
    completion(DeadlineEntry(date: now, state: read()))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<DeadlineEntry>) -> Void) {
    let now = Date()
    let state = read()
    let dates: [Date]
    if case .ready(let snapshot) = state {
      dates = snapshot.timelineDates(after: now)
    } else {
      dates = [now, now.addingTimeInterval(24 * 3600)]
    }
    completion(Timeline(entries: dates.map { DeadlineEntry(date: $0, state: state) }, policy: .atEnd))
  }

  private func read() -> DeadlineSnapshotState {
    DeadlineSnapshotStore.configured()?.read() ?? .unavailable
  }
}

struct DeadlineWidget: Widget {
  static let kind = "DeadlineWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: Self.kind, provider: DeadlineProvider()) { entry in
      DeadlineWidgetView(entry: entry)
    }
    .configurationDisplayName("deadline.widget.title")
    .description("deadline.widget.description")
    .supportedFamilies(supportedFamilies)
  }

  private var supportedFamilies: [WidgetFamily] {
    #if os(iOS)
    if #available(iOS 16.0, *) {
      return [.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline]
    }
    #endif
    return [.systemSmall, .systemMedium, .systemLarge]
  }
}
