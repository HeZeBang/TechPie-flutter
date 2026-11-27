import SwiftUI
import WidgetKit
import DeadlineWidgetSupport

struct ScheduleEntry: TimelineEntry {
  let date: Date
  let state: WidgetSnapshotState<ScheduleWidgetSnapshot>
  let mode: ScheduleDayMode
}

struct ScheduleProvider: TimelineProvider {
  func placeholder(in context: Context) -> ScheduleEntry {
    let now = Date()
    let sampleStart = Calendar.current.date(byAdding: .minute, value: -20, to: now) ?? now
    let sampleEnd = Calendar.current.date(byAdding: .minute, value: 70, to: now) ?? now.addingTimeInterval(3600)
    let nextStart = Calendar.current.date(byAdding: .minute, value: 90, to: now) ?? now.addingTimeInterval(5400)
    let nextEnd = Calendar.current.date(byAdding: .minute, value: 180, to: now) ?? now.addingTimeInterval(10800)
    let key = ScheduleWidgetResolver.dateKey(for: now)
    let wd = ScheduleWidgetResolver.isoWeekday(for: now)
    let sample = ScheduleWidgetSnapshot(
      generatedAt: now,
      weekNumber: 12,
      days: [
        ScheduleWidgetDay(
          date: key,
          weekday: wd,
          weekNumber: 12,
          courses: [
            ScheduleWidgetCourse(
              id: "sample-1",
              title: WidgetL10n.string("schedule.widget.sampleTitle1"),
              location: "SIST 1A-204",
              startAt: sampleStart,
              endAt: sampleEnd,
              periodLabel: "1-2",
              colorLightHex: "#217AD0",
              colorDarkHex: "#5BA5F6"
            ),
            ScheduleWidgetCourse(
              id: "sample-2",
              title: WidgetL10n.string("schedule.widget.sampleTitle2"),
              location: "H2-201",
              startAt: nextStart,
              endAt: nextEnd,
              periodLabel: "3-4",
              colorLightHex: "#1D9046",
              colorDarkHex: "#5DB874"
            ),
          ]
        )
      ]
    )
    return ScheduleEntry(date: now, state: .ready(sample), mode: .auto)
  }

  func getSnapshot(in context: Context, completion: @escaping (ScheduleEntry) -> Void) {
    let now = Date()
    completion(loadEntry(at: now))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<ScheduleEntry>) -> Void) {
    let now = Date()
    let state = ScheduleSnapshotStore.configured()?.read() ?? .notSynced
    let mode = WidgetPreferenceStore.configured()?.scheduleDayMode(at: now) ?? .auto
    let dates: [Date]
    if case .ready(let snapshot) = state {
      dates = ScheduleWidgetResolver.timelineDates(snapshot: snapshot, after: now)
    } else {
      dates = [now, now.addingTimeInterval(3600 * 6)]
    }
    let entries = dates.map { ScheduleEntry(date: $0, state: state, mode: mode) }
    completion(Timeline(entries: entries, policy: .atEnd))
  }

  private func loadEntry(at date: Date) -> ScheduleEntry {
    let state = ScheduleSnapshotStore.configured()?.read() ?? .notSynced
    let mode = WidgetPreferenceStore.configured()?.scheduleDayMode(at: date) ?? .auto
    return ScheduleEntry(date: date, state: state, mode: mode)
  }
}

struct ScheduleWidgetView: View {
  let entry: ScheduleEntry

  @Environment(\.widgetFamily) private var family
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.calendar) private var calendar

  var body: some View {
    TpWidgetFullColorReader { isFullColor in
      rootView(isFullColor: isFullColor)
    }
    .widgetURL(TechPieWidgetURL.schedule())
  }

  @ViewBuilder
  private func rootView(isFullColor: Bool) -> some View {
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

  // MARK: - Home & Desktop Layouts

  @ViewBuilder
  private func desktopOrHomeCard(isFullColor: Bool) -> some View {
    switch entry.state {
    case .notSynced:
      stateCard(icon: "arrow.triangle.2.circlepath", messageKey: "schedule.widget.notSynced")
    case .unavailable:
      stateCard(icon: "exclamationmark.circle", messageKey: "schedule.widget.unavailable")
    case .ready(let snapshot):
      let resolution = ScheduleWidgetResolver.resolve(
        snapshot: snapshot,
        at: entry.date,
        mode: entry.mode,
        calendar: calendar
      )
      resolvedLayout(resolution, isFullColor: isFullColor)
    }
  }

  private func stateCard(icon: String, messageKey: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      TpWidgetHeader(icon: "calendar", titleKey: "schedule.widget.title")
      TpWidgetEmptyState(icon: icon, messageKey: messageKey)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  @ViewBuilder
  private func resolvedLayout(_ resolution: ScheduleDayResolution, isFullColor: Bool) -> some View {
    VStack(alignment: .leading, spacing: family == .systemLarge ? 10 : 8) {
      scheduleHeader(resolution: resolution, isFullColor: isFullColor)

      switch resolution {
      case .empty(_, _, _, let isTomorrow, let mode):
        TpWidgetEmptyState(
          icon: "checkmark.circle",
          messageKey: emptyMessageKey(isTomorrow: isTomorrow, mode: mode)
        )

      case .inProgress(let current, _, let remaining, _, _, _, _, _):
        let rest = remaining.filter { $0.id != current.id }
        coursesBody(hero: current, isInProgress: true, upcoming: rest, isFullColor: isFullColor)

      case .upcoming(let next, let remaining, _, _, _, _, _):
        let rest = remaining.filter { $0.id != next.id }
        coursesBody(hero: next, isInProgress: false, upcoming: rest, isFullColor: isFullColor)

      case .rollover(_, _, _, _, let courses):
        if let first = courses.first {
          coursesBody(
            hero: first,
            isInProgress: false,
            upcoming: Array(courses.dropFirst()),
            isFullColor: isFullColor
          )
        } else {
          TpWidgetEmptyState(icon: "checkmark.circle", messageKey: "schedule.widget.emptyAuto")
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private func scheduleHeader(resolution: ScheduleDayResolution, isFullColor: Bool) -> some View {
    let dayBadge = dayBadgeText(for: resolution)
    return TpWidgetHeader(
      icon: "calendar",
      titleKey: "schedule.widget.title",
      badgeText: dayBadge
    ) {
      HStack(spacing: 5) {
        if let overflow = overflowText(for: resolution), family == .systemSmall {
          Text(overflow)
            .font(.system(size: 10.5, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundColor(TpWidgetColor.textMuted(colorScheme))
            .lineLimit(1)
        }
        dayToggleButton(showingTomorrow: resolution.isViewingTomorrowOrLater, isFullColor: isFullColor)
      }
    }
  }

  @ViewBuilder
  private func dayToggleButton(showingTomorrow: Bool, isFullColor: Bool) -> some View {
    if #available(iOS 17.0, macOS 14.0, *) {
      Button(intent: ToggleScheduleDayIntent(showingTomorrowOrLater: showingTomorrow)) {
        Text(LocalizedStringKey(showingTomorrow ? "schedule.widget.switchToday" : "schedule.widget.switchTomorrow"))
          .font(.system(size: 10.5, weight: .semibold))
          .foregroundColor(TpWidgetColor.textSecondary(colorScheme))
          .padding(.horizontal, 7)
          .padding(.vertical, 3)
          .background(
            Capsule(style: .continuous)
              .fill(isFullColor ? TpWidgetColor.surfaceSubtle(colorScheme) : Color.primary.opacity(0.12))
          )
      }
      .buttonStyle(.plain)
      .lineLimit(1)
    }
  }

  @ViewBuilder
  private func coursesBody(
    hero: ScheduleWidgetCourse,
    isInProgress: Bool,
    upcoming: [ScheduleWidgetCourse],
    isFullColor: Bool
  ) -> some View {
    switch family {
    case .systemSmall:
      smallHeroCourse(hero, isInProgress: isInProgress, isFullColor: isFullColor)
    case .systemMedium:
      VStack(alignment: .leading, spacing: 7) {
        heroCourseCard(hero, isInProgress: isInProgress, isFullColor: isFullColor, compact: false)
        if !upcoming.isEmpty {
          TpWidgetColor.divider(colorScheme).frame(height: 0.5)
          VStack(alignment: .leading, spacing: 5) {
            ForEach(upcoming.prefix(2)) { course in
              compactCourseRow(course, isFullColor: isFullColor)
            }
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    default:
      VStack(alignment: .leading, spacing: 7) {
        heroCourseCard(hero, isInProgress: isInProgress, isFullColor: isFullColor, compact: false)
        if !upcoming.isEmpty {
          TpWidgetColor.divider(colorScheme).frame(height: 0.5)
          VStack(alignment: .leading, spacing: 6) {
            ForEach(upcoming.prefix(5)) { course in
              compactCourseRow(course, showPeriods: true, isFullColor: isFullColor)
            }
          }
        }
        Spacer(minLength: 0)
        if upcoming.count > 5 {
          Text(WidgetL10n.format("schedule.widget.moreCourses", upcoming.count - 5))
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(TpWidgetColor.textMuted(colorScheme))
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }

  private func smallHeroCourse(
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
      VStack(alignment: .leading, spacing: 4) {
        if isInProgress {
          TpCountPill(
            text: WidgetL10n.string(course.isExam ? "schedule.widget.examLive" : "schedule.widget.live"),
            foreground: TpWidgetColor.brandInk(colorScheme),
            background: TpWidgetColor.brandSoft(colorScheme),
            fontSize: 10
          )
        } else if course.isExam {
          TpCountPill(
            text: WidgetL10n.string("schedule.widget.exam"),
            foreground: TpWidgetColor.dangerRed(colorScheme),
            background: TpWidgetColor.dangerRed(colorScheme).opacity(colorScheme == .dark ? 0.18 : 0.10),
            fontSize: 10
          )
        }

        Text(course.title)
          .font(.system(size: 14, weight: .semibold))
          .foregroundColor(TpWidgetColor.textPrimary(colorScheme))
          .lineLimit(2)
          .layoutPriority(1)

        Spacer(minLength: 2)

        if isInProgress {
          courseProgressBar(course: course, color: accent, isFullColor: isFullColor)
        }

        if !course.location.isEmpty {
          Label(course.location, systemImage: "mappin.and.ellipse")
            .font(.system(size: 11, weight: .medium))
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

  private func heroCourseCard(
    _ course: ScheduleWidgetCourse,
    isInProgress: Bool,
    isFullColor: Bool,
    compact: Bool
  ) -> some View {
    let accent = TpWidgetColor.courseAccent(
      lightHex: course.colorLightHex,
      darkHex: course.colorDarkHex,
      isExam: course.isExam,
      scheme: colorScheme
    )

    return HStack(alignment: .top, spacing: 9) {
      TpAccentBar(color: accent)
      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 6) {
          Text(course.title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(TpWidgetColor.textPrimary(colorScheme))
            .lineLimit(1)
          Spacer(minLength: 4)
          if isInProgress {
            TpCountPill(
              text: WidgetL10n.string(course.isExam ? "schedule.widget.examLive" : "schedule.widget.live"),
              foreground: TpWidgetColor.brandInk(colorScheme),
              background: TpWidgetColor.brandSoft(colorScheme),
              fontSize: 10
            )
          } else if course.isExam {
            TpCountPill(
              text: WidgetL10n.string("schedule.widget.exam"),
              foreground: TpWidgetColor.dangerRed(colorScheme),
              background: TpWidgetColor.dangerRed(colorScheme).opacity(colorScheme == .dark ? 0.18 : 0.10),
              fontSize: 10
            )
          }
        }

        HStack(spacing: 8) {
          Text(course.clockRangeText(calendar: calendar))
            .font(.system(size: 11.5, weight: .medium).monospacedDigit())
            .foregroundColor(TpWidgetColor.textSecondary(colorScheme))
          if !course.location.isEmpty {
            Label(course.location, systemImage: "mappin.and.ellipse")
              .font(.system(size: 11.5))
              .foregroundColor(TpWidgetColor.textMuted(colorScheme))
              .lineLimit(1)
          }
        }

        if isInProgress {
          courseProgressBar(course: course, color: accent, isFullColor: isFullColor)
            .padding(.top, 2)
        }
      }
    }
    .padding(.horizontal, isInProgress ? 8 : 0)
    .padding(.vertical, isInProgress ? 6 : 2)
    .background {
      if isInProgress && isFullColor {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(accent.opacity(colorScheme == .dark ? 0.15 : 0.08))
      }
    }
  }

  private func compactCourseRow(
    _ course: ScheduleWidgetCourse,
    showPeriods: Bool = false,
    isFullColor: Bool
  ) -> some View {
    let accent = TpWidgetColor.courseAccent(
      lightHex: course.colorLightHex,
      darkHex: course.colorDarkHex,
      isExam: course.isExam,
      scheme: colorScheme
    )

    return HStack(spacing: 8) {
      TpAccentBar(color: accent)
        .frame(height: showPeriods ? 26 : 18)
      VStack(alignment: .leading, spacing: 1) {
        Text(course.title)
          .font(.system(size: 12.5, weight: .medium))
          .foregroundColor(TpWidgetColor.textPrimary(colorScheme))
          .lineLimit(1)
        if showPeriods && !course.location.isEmpty {
          Text(course.location)
            .font(.system(size: 10.5))
            .foregroundColor(TpWidgetColor.textMuted(colorScheme))
            .lineLimit(1)
        }
      }
      Spacer(minLength: 6)
      VStack(alignment: .trailing, spacing: 1) {
        Text(showPeriods ? course.clockRangeText(calendar: calendar) : course.startClockText(calendar: calendar))
          .font(.system(size: 11.5, weight: .medium).monospacedDigit())
          .foregroundColor(TpWidgetColor.textSecondary(colorScheme))
          .lineLimit(1)
        if !showPeriods && !course.location.isEmpty {
          Text(course.location)
            .font(.system(size: 10.5))
            .foregroundColor(TpWidgetColor.textMuted(colorScheme))
            .lineLimit(1)
        }
      }
    }
  }

  @ViewBuilder
  private func courseProgressBar(
    course: ScheduleWidgetCourse,
    color: Color,
    isFullColor: Bool
  ) -> some View {
    if #available(iOS 16.0, macOS 13.0, *) {
      ProgressView(timerInterval: course.startAt...course.endAt, countsDown: false) {
        EmptyView()
      } currentValueLabel: {
        EmptyView()
      }
      .labelsHidden()
      .tint(isFullColor ? color : .primary)
      .frame(height: 4)
    } else {
      let fraction = CGFloat(course.progress(at: entry.date) ?? 0)
      GeometryReader { geo in
        ZStack(alignment: .leading) {
          Capsule().fill(Color.primary.opacity(0.14))
          Capsule()
            .fill(color)
            .frame(width: max(4, geo.size.width * fraction))
        }
      }
      .frame(height: 4)
    }
  }

  // MARK: - Helpers

  private func dayBadgeText(for resolution: ScheduleDayResolution) -> String? {
    switch resolution {
    case .inProgress(_, _, _, _, _, _, let isTomorrow, _),
      .upcoming(_, _, _, _, _, let isTomorrow, _):
      return isTomorrow ? WidgetL10n.string("deadline.widget.section.tomorrow") : nil
    case .rollover(_, let targetWeekday, _, let daysAhead, _):
      if daysAhead == 1 {
        return WidgetL10n.string("deadline.widget.section.tomorrow")
      }
      return WidgetL10n.weekdayShort(targetWeekday)
    case .empty(_, _, _, let isTomorrow, let mode):
      if isTomorrow || mode == .tomorrow {
        return WidgetL10n.string("deadline.widget.section.tomorrow")
      }
      return nil
    }
  }

  private func overflowText(for resolution: ScheduleDayResolution) -> String? {
    let count: Int
    switch resolution {
    case .inProgress(_, _, let remaining, _, _, _, _, _):
      count = max(0, remaining.count - 1)
    case .upcoming(_, let remaining, _, _, _, _, _):
      count = max(0, remaining.count - 1)
    case .rollover(_, _, _, _, let courses):
      count = max(0, courses.count - 1)
    case .empty:
      count = 0
    }
    return count > 0 ? "+\(count)" : nil
  }

  private func emptyMessageKey(isTomorrow: Bool, mode: ScheduleDayMode) -> String {
    if isTomorrow || mode == .tomorrow {
      return "schedule.widget.emptyTomorrow"
    }
    if mode == .today {
      return "schedule.widget.emptyToday"
    }
    return "schedule.widget.emptyAuto"
  }

  // MARK: - iOS Lock Screen Accessories (directly readable, not privacySensitive)

  #if os(iOS)
  @available(iOS 16.0, *)
  @ViewBuilder
  private var rectangularAccessory: some View {
    switch entry.state {
    case .notSynced:
      VStack(alignment: .leading, spacing: 2) {
        Label(LocalizedStringKey("schedule.widget.title"), systemImage: "calendar")
          .font(.system(size: 11, weight: .semibold))
        Text(LocalizedStringKey("schedule.widget.notSynced"))
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    case .unavailable:
      VStack(alignment: .leading, spacing: 2) {
        Label(LocalizedStringKey("schedule.widget.title"), systemImage: "calendar")
          .font(.system(size: 11, weight: .semibold))
        Text(LocalizedStringKey("schedule.widget.unavailable"))
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    case .ready(let snapshot):
      let resolution = ScheduleWidgetResolver.resolve(
        snapshot: snapshot,
        at: entry.date,
        mode: entry.mode,
        calendar: calendar
      )
      rectangularBody(resolution)
    }
  }

  @available(iOS 16.0, *)
  @ViewBuilder
  private func rectangularBody(_ resolution: ScheduleDayResolution) -> some View {
    switch resolution {
    case .inProgress(let current, _, _, _, _, _, _, _):
      accessoryCourseLines(
        eyebrow: "\(WidgetL10n.string("schedule.widget.live")) · \(current.clockRangeText(calendar: calendar))",
        course: current,
        highlighted: true
      )
    case .upcoming(let next, _, _, _, _, let isTomorrow, _):
      let prefix = isTomorrow
        ? WidgetL10n.string("deadline.widget.section.tomorrow")
        : WidgetL10n.string("schedule.widget.next")
      accessoryCourseLines(
        eyebrow: "\(prefix) · \(next.clockRangeText(calendar: calendar))",
        course: next,
        highlighted: false
      )
    case .rollover(_, let weekday, _, let daysAhead, let courses) where !courses.isEmpty:
      let prefix = daysAhead == 1
        ? WidgetL10n.string("deadline.widget.section.tomorrow")
        : WidgetL10n.weekdayShort(weekday)
      accessoryCourseLines(
        eyebrow: "\(prefix) · \(courses[0].clockRangeText(calendar: calendar))",
        course: courses[0],
        highlighted: false
      )
    default:
      VStack(alignment: .leading, spacing: 2) {
        Label(LocalizedStringKey("schedule.widget.title"), systemImage: "calendar")
          .font(.system(size: 11, weight: .semibold))
        Text(LocalizedStringKey("schedule.widget.emptyAuto"))
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  @available(iOS 16.0, *)
  private func accessoryCourseLines(
    eyebrow: String,
    course: ScheduleWidgetCourse,
    highlighted: Bool
  ) -> some View {
    VStack(alignment: .leading, spacing: 1.5) {
      HStack(spacing: 4) {
        Image(systemName: course.isExam ? "calendar.badge.exclamationmark" : "calendar")
          .font(.system(size: 10, weight: .semibold))
          .tpAccentable(highlighted)
        Text(eyebrow)
          .font(.system(size: 11, weight: .semibold).monospacedDigit())
          .lineLimit(1)
      }
      .foregroundStyle(.secondary)

      Text(course.title)
        .font(.system(size: 13.5, weight: .bold))
        .lineLimit(1)

      if !course.location.isEmpty {
        Text(course.location)
          .font(.system(size: 11.5))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @available(iOS 16.0, *)
  @ViewBuilder
  private var inlineAccessory: some View {
    if case .ready(let snapshot) = entry.state {
      let resolution = ScheduleWidgetResolver.resolve(
        snapshot: snapshot,
        at: entry.date,
        mode: .auto,
        calendar: calendar
      )
      switch resolution {
      case .inProgress(let current, _, _, _, _, _, _, _):
        Label("\(current.title) · \(current.location)", systemImage: "calendar")
      case .upcoming(let next, _, _, _, _, _, _):
        Label("\(next.startClockText(calendar: calendar)) \(next.title)", systemImage: "calendar")
      case .rollover(_, let wd, _, let ahead, let courses) where !courses.isEmpty:
        let tag = ahead == 1 ? WidgetL10n.string("deadline.widget.section.tomorrow") : WidgetL10n.weekdayShort(wd)
        Label("\(tag) \(courses[0].startClockText(calendar: calendar)) \(courses[0].title)", systemImage: "calendar")
      default:
        Label(LocalizedStringKey("schedule.widget.emptyAuto"), systemImage: "calendar")
      }
    } else {
      Label(LocalizedStringKey("schedule.widget.title"), systemImage: "calendar")
    }
  }
  #endif
}

struct ScheduleWidget: Widget {
  static let kind = "ScheduleWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: Self.kind, provider: ScheduleProvider()) { entry in
      ScheduleWidgetView(entry: entry)
    }
    .configurationDisplayName("schedule.widget.title")
    .description("schedule.widget.description")
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
