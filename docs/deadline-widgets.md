# Deadline Widgets

## Display contract

Widgets display future, incomplete assignments and exams from local data,
respecting hidden items and completion overrides. Items are ordered by deadline,
then internal identifier. Small, medium and large display at most 2, 4 and 8 items.
Each item shows its title, course, type, absolute deadline and remaining time.
Truncated text retains the full title, course and deadline in accessibility labels.

Remaining time is rounded down to whole hours and displayed as days/hours or
hours only. Below one hour it becomes red "Due soon" ("即将截止" in Chinese).
Remaining minutes and seconds are never displayed. Absolute deadlines use the
device's local time zone and include the year when it differs from the current
year. Compact list rows use "Today" or "Tomorrow" where applicable.

An empty snapshot displays "No upcoming deadlines". A missing snapshot requests
opening TechPie to sync; unreadable or invalid data displays an unavailable state.
`techpie://deadlines` selects the existing Deadlines page, waiting for navigation
to become ready on a cold launch.

## Snapshot protocol

The Flutter channel is `techpie/deadline_widgets`. The native bridge atomically
writes a complete snapshot to `Library/Application Support/deadline-widget-v1.json`
inside the shared App Group:

```json
{
  "schemaVersion": 1,
  "writtenAt": 1791763200,
  "items": [
    {
      "id": "assignment:example",
      "kind": "assignment",
      "title": "Problem Set",
      "course": "Example Course",
      "dueAt": 1791849600
    }
  ]
}
```

`writtenAt` and `dueAt` are Unix timestamps in seconds. Identifiers must be
nonempty and unique; `kind` is `assignment` or `exam`. Unsupported schema versions,
invalid timestamps and duplicate identifiers are rejected before replacing the
existing snapshot. Snapshots contain display data only, without credentials,
account details or source URLs.

## Update rules

The host publishes after cache hydration, deadline/completion/visibility changes
and foreground return. Unchanged display data does not request another widget
reload. Foreground return also requests a deadline fetch if the last attempt was
at least five minutes ago. Widgets perform no network requests.

Logout clears shared data. Source-account changes remove affected deadlines;
identity generation checks prevent older asynchronous work from restoring them.

Widget timelines schedule hourly label changes, local midnight and deadline
expiry over the next 24 hours. Expired items are removed and later items become
visible. WidgetKit may delay transitions, so the absolute deadline remains visible.

## Platform configuration

macOS embeds `DeadlineWidgets`, supporting Notification Center on macOS 11+ and
desktop widgets on macOS 14+. iOS uses the existing `EcardPayWidget` extension's
WidgetBundle, preserving its bundle identifier and campus-code widget kind.
The deadline widget kind is `DeadlineWidget` on both platforms.

The host and extension must use the same App Group and signing team. Build settings:

- `TECHPIE_DEADLINE_APP_GROUP`: `$(TeamIdentifierPrefix)club.geekpie.techpie.deadlines`
  on macOS; `group.club.geekpie.techpie.deadlines` on iOS.
- `TECHPIE_HOST_BUNDLE_IDENTIFIER`: must match the macOS host bundle identifier.
- `TECHPIE_WIDGET_URL_SCHEME`: defaults to `techpie`; must match the host URL scheme.

Before iOS distribution, register the App Group for Runner and EcardPayWidget
and regenerate both provisioning profiles. Signing must preserve the shared
App Group entitlement when changing bundle identifiers.
