import SwiftUI
import WidgetKit
import DeadlineWidgetSupport

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
