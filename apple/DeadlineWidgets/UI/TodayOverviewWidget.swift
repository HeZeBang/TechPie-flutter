import SwiftUI
import WidgetKit
import DeadlineWidgetSupport

struct TodayOverviewEntry: TimelineEntry {
  let date: Date
  let schedule: WidgetSnapshotState<ScheduleWidgetSnapshot>
  let deadlines: DeadlineSnapshotState
}

struct TodayOverviewProvider: TimelineProvider {
  func placeholder(in context: Context) -> TodayOverviewEntry {
    let now = Date()
    let sampleStart = Calendar.current.date(byAdding: .minute, value: 25, to: now) ?? now
    let sampleEnd = Calendar.current.date(byAdding: .minute, value: 115, to: now) ?? now.addingTimeInterval(3600)
    let key = ScheduleWidgetResolver.dateKey(for: now)
    let wd = ScheduleWidgetResolver.isoWeekday(for: now)
    let sampleSchedule = ScheduleWidgetSnapshot(
      generatedAt: now,
      weekNumber: 12,
      days: [
        ScheduleWidgetDay(
          date: key,
          weekday: wd,
          weekNumber: 12,
          courses: [
            ScheduleWidgetCourse(
              id: "overview-1",
              title: WidgetL10n.string("schedule.widget.sampleTitle1"),
              location: "SIST 1A-204",
              startAt: sampleStart,
              endAt: sampleEnd,
              colorLightHex: "#217AD0",
              colorDarkHex: "#5BA5F6"
            )
          ]
        )
      ]
    )
    let sampleDeadlines = DeadlineSnapshot(
      writtenAt: now.timeIntervalSince1970,
      items: [
        DeadlineItem(
          id: "ov-ddl-1",
          kind: .assignment,
          title: WidgetL10n.string("deadline.widget.sampleTitle1"),
          subtitle: "CS101",
          dueAt: now.addingTimeInterval(5 * 3600).timeIntervalSince1970
        ),
        DeadlineItem(
          id: "ov-ddl-2",
          kind: .exam,
          title: WidgetL10n.string("deadline.widget.sampleTitle2"),
          subtitle: "SIST 1A-200",
          dueAt: now.addingTimeInterval(30 * 3600).timeIntervalSince1970
        ),
      ]
    )
    return TodayOverviewEntry(
      date: now,
      schedule: .ready(sampleSchedule),
      deadlines: .ready(sampleDeadlines)
    )
  }

  func getSnapshot(in context: Context, completion: @escaping (TodayOverviewEntry) -> Void) {
    let now = Date()
    completion(loadEntry(at: now))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<TodayOverviewEntry>) -> Void) {
    let now = Date()
    let scheduleState = ScheduleSnapshotStore.configured()?.read() ?? .notSynced
    let deadlineState = DeadlineSnapshotStore.configured()?.read() ?? .unavailable

    var dateSet: Set<Date> = [now, now.addingTimeInterval(24 * 3600)]
    if case .ready(let schedule) = scheduleState {
      dateSet.formUnion(ScheduleWidgetResolver.timelineDates(snapshot: schedule, after: now))
    }
    if case .ready(let deadlines) = deadlineState {
      dateSet.formUnion(deadlines.timelineDates(after: now))
    }
    let entries = dateSet.sorted().map {
      TodayOverviewEntry(date: $0, schedule: scheduleState, deadlines: deadlineState)
    }
    completion(Timeline(entries: entries, policy: .atEnd))
  }

  private func loadEntry(at date: Date) -> TodayOverviewEntry {
    TodayOverviewEntry(
      date: date,
      schedule: ScheduleSnapshotStore.configured()?.read() ?? .notSynced,
      deadlines: DeadlineSnapshotStore.configured()?.read() ?? .unavailable
    )
  }
}

struct TodayOverviewWidgetView: View {
  let entry: TodayOverviewEntry

  @Environment(\.widgetFamily) private var family
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.calendar) private var calendar

  var body: some View {
    TpWidgetFullColorReader { isFullColor in
      Group {
        if family == .systemLarge {
          largeLayout(isFullColor: isFullColor)
        } else {
          mediumLayout(isFullColor: isFullColor)
        }
      }
      .tpWidgetSurfaceBackground(isFullColor: isFullColor, colorScheme: colorScheme)
    }
  }

  // MARK: - Medium (Left: Schedule, Right: Deadlines)

  private func mediumLayout(isFullColor: Bool) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Link(destination: TechPieWidgetURL.schedule()) {
        mediumScheduleZone(isFullColor: isFullColor)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }
      .buttonStyle(.plain)

      TpWidgetColor.divider(colorScheme).frame(width: 0.5)

      Link(destination: TechPieWidgetURL.deadlines()) {
        mediumDeadlinesZone(isFullColor: isFullColor)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }
      .buttonStyle(.plain)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  @ViewBuilder
  private func mediumScheduleZone(isFullColor: Bool) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      let badge = scheduleBadgeText()
      TpWidgetHeader(
        icon: "calendar",
        titleKey: "schedule.widget.title",
        badgeText: badge
      )

      switch entry.schedule {
      case .notSynced:
        TpWidgetEmptyState(icon: "arrow.triangle.2.circlepath", messageKey: "schedule.widget.notSynced")
      case .unavailable:
        TpWidgetEmptyState(icon: "exclamationmark.circle", messageKey: "schedule.widget.unavailable")
      case .ready(let snapshot):
        let resolution = ScheduleWidgetResolver.resolve(
          snapshot: snapshot,
          at: entry.date,
          mode: .auto,
          calendar: calendar
        )
        switch resolution {
        case .inProgress(let current, _, _, _, _, _, _, _):
          overviewHeroCourse(current, isInProgress: true, isFullColor: isFullColor)
        case .upcoming(let next, _, _, _, _, _, _):
          overviewHeroCourse(next, isInProgress: false, isFullColor: isFullColor)
        case .rollover(_, _, _, _, let courses) where !courses.isEmpty:
          overviewHeroCourse(courses[0], isInProgress: false, isFullColor: isFullColor)
        default:
          TpWidgetEmptyState(icon: "checkmark.circle", messageKey: "schedule.widget.emptyAuto")
        }
      }
    }
  }

  private func overviewHeroCourse(
    _ course: ScheduleWidgetCourse,
    isInProgress: Bool,
    isFullColor: Bool
  ) -> some View {
    let accent = TpWidgetColor.courseAccent(
      lightHex: course.colorLightHex,
      darkHex: course.colorDarkHex,
      isExam: course.isExam,
      scheme: colorScheme
    )

    return HStack(alignment: .top, spacing: 8) {
      TpAccentBar(color: accent)
      VStack(alignment: .leading, spacing: 3) {
        Text(course.title)
          .font(.system(size: 13.5, weight: .semibold))
          .foregroundColor(TpWidgetColor.textPrimary(colorScheme))
          .lineLimit(2)

        Spacer(minLength: 2)

        if isInProgress, #available(iOS 16.0, macOS 13.0, *) {
          ProgressView(timerInterval: course.startAt...course.endAt, countsDown: false) {
            EmptyView()
          } currentValueLabel: {
            EmptyView()
          }
          .labelsHidden()
          .tint(isFullColor ? accent : .primary)
          .frame(height: 4)
        }

        if !course.location.isEmpty {
          Label(course.location, systemImage: "mappin.and.ellipse")
            .font(.system(size: 11))
            .foregroundColor(TpWidgetColor.textSecondary(colorScheme))
            .lineLimit(1)
        }

        Text(course.clockRangeText(calendar: calendar))
          .font(.system(size: 11, weight: .medium).monospacedDigit())
          .foregroundColor(TpWidgetColor.textMuted(colorScheme))
          .lineLimit(1)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  @ViewBuilder
  private func mediumDeadlinesZone(isFullColor: Bool) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      let upcoming = upcomingDeadlines(limit: 2)
      let totalCount = upcomingDeadlines(limit: .max).count
      TpWidgetHeader(
        icon: "checkmark.circle.fill",
        titleKey: "deadline.widget.title",
        badgeText: totalCount > 0 ? "\(totalCount)" : nil
      )

      switch entry.deadlines {
      case .notSynced:
        TpWidgetEmptyState(icon: "arrow.triangle.2.circlepath", messageKey: "deadline.widget.notSynced")
      case .unavailable:
        TpWidgetEmptyState(icon: "exclamationmark.circle", messageKey: "deadline.widget.unavailable")
      case .ready where upcoming.isEmpty:
        TpWidgetEmptyState(icon: "checkmark.circle", messageKey: "deadline.widget.empty")
      case .ready:
        VStack(alignment: .leading, spacing: 7) {
          ForEach(upcoming) { item in
            overviewDeadlineRow(item, showSubtitle: false, isFullColor: isFullColor)
          }
          Spacer(minLength: 0)
        }
      }
    }
  }

  // MARK: - Large (Top: Schedule, Bottom: Deadlines)

  private func largeLayout(isFullColor: Bool) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Link(destination: TechPieWidgetURL.schedule()) {
        largeScheduleZone(isFullColor: isFullColor)
          .frame(maxWidth: .infinity, alignment: .topLeading)
      }
      .buttonStyle(.plain)

      TpWidgetColor.divider(colorScheme).frame(height: 0.5)

      Link(destination: TechPieWidgetURL.deadlines()) {
        largeDeadlinesZone(isFullColor: isFullColor)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }
      .buttonStyle(.plain)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  @ViewBuilder
  private func largeScheduleZone(isFullColor: Bool) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      TpWidgetHeader(
        icon: "calendar",
        titleKey: "schedule.widget.title",
        badgeText: scheduleBadgeText()
      )

      switch entry.schedule {
      case .notSynced:
        compactEmptyLine("schedule.widget.notSynced", icon: "arrow.triangle.2.circlepath")
      case .unavailable:
        compactEmptyLine("schedule.widget.unavailable", icon: "exclamationmark.circle")
      case .ready(let snapshot):
        let resolution = ScheduleWidgetResolver.resolve(
          snapshot: snapshot,
          at: entry.date,
          mode: .auto,
          calendar: calendar
        )
        let courses = previewCourses(from: resolution)
        if courses.isEmpty {
          compactEmptyLine("schedule.widget.emptyAuto", icon: "checkmark.circle")
        } else {
          VStack(alignment: .leading, spacing: 5) {
            ForEach(courses.prefix(3)) { course in
              let accent = TpWidgetColor.courseAccent(
                lightHex: course.colorLightHex,
                darkHex: course.colorDarkHex,
                isExam: course.isExam,
                scheme: colorScheme
              )
              HStack(spacing: 8) {
                TpAccentBar(color: accent)
                  .frame(height: 22)
                VStack(alignment: .leading, spacing: 1) {
                  Text(course.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(TpWidgetColor.textPrimary(colorScheme))
                    .lineLimit(1)
                  if !course.location.isEmpty {
                    Text(course.location)
                      .font(.system(size: 10.5))
                      .foregroundColor(TpWidgetColor.textMuted(colorScheme))
                      .lineLimit(1)
                  }
                }
                Spacer(minLength: 4)
                Text(course.clockRangeText(calendar: calendar))
                  .font(.system(size: 11, weight: .medium).monospacedDigit())
                  .foregroundColor(TpWidgetColor.textSecondary(colorScheme))
                  .lineLimit(1)
              }
            }
          }
        }
      }
    }
  }

  @ViewBuilder
  private func largeDeadlinesZone(isFullColor: Bool) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      let all = upcomingDeadlines(limit: .max)
      let shown = Array(all.prefix(3))
      TpWidgetHeader(
        icon: "checkmark.circle.fill",
        titleKey: "deadline.widget.title",
        badgeText: all.isEmpty ? nil : "\(all.count)"
      ) {
        if all.count > shown.count {
          Text(WidgetL10n.format("deadline.widget.more", all.count - shown.count))
            .font(.system(size: 10.5, weight: .medium).monospacedDigit())
            .foregroundColor(TpWidgetColor.textMuted(colorScheme))
        }
      }

      switch entry.deadlines {
      case .notSynced:
        compactEmptyLine("deadline.widget.notSynced", icon: "arrow.triangle.2.circlepath")
      case .unavailable:
        compactEmptyLine("deadline.widget.unavailable", icon: "exclamationmark.circle")
      case .ready where shown.isEmpty:
        compactEmptyLine("deadline.widget.empty", icon: "checkmark.circle")
      case .ready:
        VStack(alignment: .leading, spacing: 6) {
          ForEach(shown) { item in
            overviewDeadlineRow(item, showSubtitle: true, isFullColor: isFullColor)
          }
          Spacer(minLength: 0)
        }
      }
    }
  }

  private func overviewDeadlineRow(
    _ item: DeadlineItem,
    showSubtitle: Bool,
    isFullColor: Bool
  ) -> some View {
    let urgency = item.urgency(at: entry.date)
    let barColor: Color
    let pillFg: Color
    let pillBg: Color
    if !isFullColor {
      barColor = Color.primary.opacity(0.6)
      pillFg = .primary
      pillBg = Color.primary.opacity(0.12)
    } else {
      switch urgency {
      case .overdue, .urgent:
        barColor = TpWidgetColor.dangerRed(colorScheme)
        pillFg = barColor
        pillBg = barColor.opacity(colorScheme == .dark ? 0.18 : 0.10)
      case .soon:
        barColor = TpWidgetColor.warningAmber(colorScheme)
        pillFg = barColor
        pillBg = barColor.opacity(colorScheme == .dark ? 0.16 : 0.10)
      case .upcoming:
        barColor = TpWidgetColor.textMuted(colorScheme).opacity(0.45)
        pillFg = TpWidgetColor.textSecondary(colorScheme)
        pillBg = TpWidgetColor.surfaceSubtle(colorScheme)
      }
    }

    return HStack(spacing: 7) {
      TpAccentBar(color: barColor)
        .frame(height: showSubtitle ? 24 : 18)
      VStack(alignment: .leading, spacing: 1) {
        Text(item.title)
          .font(.system(size: 12.5, weight: .semibold))
          .foregroundColor(TpWidgetColor.textPrimary(colorScheme))
          .lineLimit(1)
        if showSubtitle, !item.subtitle.isEmpty {
          Text(item.subtitle)
            .font(.system(size: 10.5))
            .foregroundColor(TpWidgetColor.textMuted(colorScheme))
            .lineLimit(1)
        }
      }
      Spacer(minLength: 4)
      if let hours = DeadlineSnapshot.remainingHours(item, at: entry.date) {
        let value = DeadlineRemaining(hours: hours)
        TpCountPill(
          text: remainingText(value),
          foreground: pillFg,
          background: pillBg,
          fontSize: 10.5
        )
        .tpAccentable(value.isUrgent)
      }
    }
  }

  private func compactEmptyLine(_ key: String, icon: String) -> some View {
    HStack(spacing: 6) {
      Image(systemName: icon)
        .font(.system(size: 13))
        .foregroundColor(TpWidgetColor.textMuted(colorScheme))
      Text(LocalizedStringKey(key))
        .font(.system(size: 12))
        .foregroundColor(TpWidgetColor.textSecondary(colorScheme))
    }
    .padding(.vertical, 8)
  }

  // MARK: - Helpers

  private func upcomingDeadlines(limit: Int) -> [DeadlineItem] {
    guard case .ready(let snapshot) = entry.deadlines else { return [] }
    return snapshot.upcoming(at: entry.date, limit: limit)
  }

  private func scheduleBadgeText() -> String? {
    guard case .ready(let snapshot) = entry.schedule else { return nil }
    let resolution = ScheduleWidgetResolver.resolve(
      snapshot: snapshot,
      at: entry.date,
      mode: .auto,
      calendar: calendar
    )
    switch resolution {
    case .inProgress:
      return WidgetL10n.string("schedule.widget.live")
    case .rollover(_, let weekday, _, let daysAhead, _):
      return daysAhead == 1
        ? WidgetL10n.string("deadline.widget.section.tomorrow")
        : WidgetL10n.weekdayShort(weekday)
    default:
      return nil
    }
  }

  private func previewCourses(from resolution: ScheduleDayResolution) -> [ScheduleWidgetCourse] {
    switch resolution {
    case .inProgress(_, _, let remaining, _, _, _, _, _):
      return remaining
    case .upcoming(_, let remaining, _, _, _, _, _):
      return remaining
    case .rollover(_, _, _, _, let courses):
      return courses
    case .empty:
      return []
    }
  }

  private func remainingText(_ value: DeadlineRemaining) -> String {
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
}

struct TodayOverviewWidget: Widget {
  static let kind = "TodayOverviewWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: Self.kind, provider: TodayOverviewProvider()) { entry in
      TodayOverviewWidgetView(entry: entry)
    }
    .configurationDisplayName("overview.widget.title")
    .description("overview.widget.description")
    .supportedFamilies([.systemMedium, .systemLarge])
  }
}
