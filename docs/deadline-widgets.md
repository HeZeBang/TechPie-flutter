# Native Widgets

TechPie ships four native widgets across Apple platforms (sharing `apple/DeadlineWidgets/` UI & support code inside the existing iOS `EcardPayWidget` extension and macOS `DeadlineWidgets` extension):

1. **Campus Card (`EcardPayWidget`)**: Small (`2×2`) & Medium (`4×2`) physical-card surface styled after `TpCampusCardStrip`, iOS Lock Screen `accessoryCircular` / `accessoryInline`, and an iOS 18+ Control Center `ControlWidgetButton` (`EcardPayControlWidget`). Supports in-widget balance mask toggling (`ToggleEcardBalanceMaskIntent`) synced cleanly with the main app's privacy toggle, plus `.privacySensitive()` Lock Screen redaction. Deep link: `techpie://ecard/pay`.
2. **Schedule (`ScheduleWidget`)**: Small (`2×2`), Medium (`4×2`), Large (`4×4`), plus iOS Lock Screen `accessoryRectangular` / `accessoryInline`. Reads a 7-day rolling schedule window (`schedule-widget-v1.json`) with per-course OKLCH light/dark accent colors, live in-class `ProgressView(timerInterval:)`, automatic end-of-day rollover to the next teaching day, and an in-widget Today/Tomorrow toggle (`ToggleScheduleDayIntent`). Deep link: `techpie://schedule`.
3. **Deadlines (`DeadlineWidget`)**: Small (`2×2`), Medium (`4×2`), Large (`4×4`), plus iOS Lock Screen `accessoryRectangular` / `accessoryInline`. Aligns with TechPie's TechRed accent & urgency-bar hierarchy (`< 24h` urgent crimson, `< 72h` amber, upcoming neutral). Deep link: `techpie://deadlines`.
4. **Today Overview (`TodayOverviewWidget`)**: Medium (`4×2`) two-column dashboard and Large (`4×4`) stacked dashboard combining the active/next class with upcoming deadlines, using zone-targeted `Link(destination:)` deep links (`techpie://schedule` and `techpie://deadlines`).

---

## Deadlines Contract

Widgets display future, incomplete assignments and exams from local data,
respecting hidden items and completion overrides. Items are ordered by deadline,
then internal identifier. Small shows the next deadline alone: its title,
subtitle, countdown capsule, and weekday date; medium lists up to three; large
lists up to seven under Today, Tomorrow, Next 7 days and Later headings, fewer
when they spread over many days.
A medium or large widget with a single deadline shows it the way small does.
The header counts total deadlines and overflows when truncated.

Each item shows its title, a subtitle, its absolute deadline, urgency accent bar,
and remaining time. A symbol before the date names the kind: a document for an
assignment, a calendar for an exam. Urgency indicators use a 3pt accent bar and
tinted countdown pill (`<= 24h` crimson, `<= 72h` amber, neutral otherwise) and
adapt cleanly across Light, Dark, and iOS 18+ Tinted/Clear rendering modes.
Truncated text retains the full title, subtitle and deadline in accessibility
labels.

Remaining time is rounded down to whole hours and gets coarser further out:
hours below a day, days and hours below two days, whole days beyond that. Below
one hour it reads "Due soon" ("即将截止" in Chinese).
Absolute deadlines use the device's local time zone and include the year when it
differs from the current year.

---

## Snapshot Protocols (App Group `Library/Application Support/`)

All snapshots are written atomically inside the shared App Group container (`CompleteUntilFirstUserAuthentication` on iOS) and **never** contain credentials, student/card IDs, session cookies, or offline payment secrets:

### 1. `deadline-widget-v1.json` (channel: `techpie/deadline_widgets`)

```json
{
  "schemaVersion": 1,
  "writtenAt": 1791763200,
  "items": [
    {
      "id": "assignment:example",
      "kind": "assignment",
      "title": "Problem Set",
      "subtitle": "Example Course",
      "dueAt": 1791849600
    }
  ]
}
```

### 2. `schedule-widget-v1.json` (channel: `techpie/home_widgets`)

Covers a rolling 7-day window computed via `coursesOnDay()` (undergraduate, graduate, custom courses, and exam entries):

```json
{
  "schemaVersion": 1,
  "generatedAt": "2026-11-27T01:00:00Z",
  "weekNumber": 12,
  "days": [
    {
      "date": "2026-11-27",
      "weekday": 5,
      "weekNumber": 12,
      "courses": [
        {
          "id": "2026-11-27|08:15|09:55|Linear Algebra",
          "title": "Linear Algebra",
          "location": "SIST 1A-204",
          "teacher": "Prof. Li",
          "startAt": "2026-11-27T00:15:00Z",
          "endAt": "2026-11-27T01:55:00Z",
          "startPeriod": 1,
          "endPeriod": 2,
          "periodLabel": "1-2",
          "isExam": false,
          "colorLightHex": "#217AD0",
          "colorDarkHex": "#5BA5F6"
        }
      ]
    }
  ]
}
```

### 3. `ecard-widget-v1.json` (channel: `techpie/home_widgets`)

Display-only binding & cached balance state:

```json
{
  "schemaVersion": 1,
  "generatedAt": "2026-11-27T01:00:00Z",
  "configured": true,
  "balanceText": "¥ 86.20",
  "hideBalance": false
}
```

When `hideCampusCardBalance` changes in Flutter, `WidgetPreferenceStore` clears any local widget-level eye-toggle override so the main app setting remains authoritative.

---

## Update rules & Platform configuration

- Hosts publish after cache hydration, schedule/deadline/balance/visibility mutations, and foreground return; semantic equality deduplicates reloads. Logout clears `deadline-widget-v1.json` and `schedule-widget-v1.json`.
- macOS embeds `DeadlineWidgets`, supporting Notification Center on macOS 12+ and desktop widgets on macOS 14+ across all four desktop widgets.
- iOS reuses the existing `EcardPayWidget` extension (`TechPieWidgets: WidgetBundle`) and existing App Group so no additional App IDs or provisioning profiles are needed.
- Build settings:
  - `TECHPIE_DEADLINE_APP_GROUP`: `$(TeamIdentifierPrefix)club.geekpie.techpie.deadlines` on macOS; `group.club.geekpie.techpie.deadlines` on iOS.
  - `TECHPIE_HOST_BUNDLE_IDENTIFIER`: matches the macOS host bundle identifier.
  - `TECHPIE_WIDGET_URL_SCHEME`: defaults to `techpie`.
