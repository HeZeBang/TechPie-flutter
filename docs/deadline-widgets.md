# Deadline Widgets

The native macOS and iOS widgets display upcoming, incomplete assignments and
exams from TechPie's latest local data. Hidden items and completion overrides
apply to widgets. Small, medium and large show at most 2, 4 and 8 items.
The existing iOS campus-code widget remains in the same extension and keeps its
`EcardPayWidget` kind and extension bundle identifier.

## Data and updates

Flutter publishes through `techpie/deadline_widgets` after cache hydration and
deadline changes. The native bridge atomically writes `deadline-widget-v1.json`
in the App Group's `Library/Application Support` directory and reloads only the
`DeadlineWidget` timelines. The snapshot contains schema version 1, a write
timestamp and display items (`id`, `kind`, `title`, `course`, Unix `dueAt`).
It never contains tokens, cookies, account details or source URLs.

Widgets do not fetch from the network. Returning to the foreground republishes
current data and requests a normal deadline fetch if the last attempt was at
least five minutes ago. New server data requires opening or refreshing TechPie.
Account changes invalidate pending requests and clear the shared snapshot.

Deadlines within 24 hours display full remaining hours. With less than one hour
remaining they display a red "Due soon" label ("即将截止" in Chinese). Hours are
rounded down, so 1 hour 30 minutes displays 1 hour. Minutes and seconds are never
shown in the remaining-time label. Timelines precompute hourly transitions,
the one-hour urgency threshold, local midnight, expiry and the 24-hour boundary,
so these labels update while the app is closed. The system may delay a timeline
transition. Absolute due times remain visible in the device's local time zone.
Widgets do not request per-second reloads or network data.

## Signing and installation

Both the host and widget extension need the same App Group entitlement and must
be signed by the same team. `TECHPIE_DEADLINE_APP_GROUP` is a project build setting:

- macOS: `$(TeamIdentifierPrefix)club.geekpie.techpie.deadlines`.
- iOS: `group.club.geekpie.techpie.deadlines`.

For iOS distribution, register that App Group in the Apple developer account,
enable it for Runner and EcardPayWidget, and regenerate both provisioning
profiles. The private signing workflow must preserve the App Group entitlement
when replacing bundle identifiers or entitlements. No certificates, private
keys or personal team identifiers belong in this repository.

macOS 11+ supports Notification Center widgets, and macOS 14+ also supports
desktop widgets. Runner still supports its previous minimum OS version. The
widget extension is embedded during a normal Runner build.
`TECHPIE_HOST_BUNDLE_IDENTIFIER` controls the macOS extension's parent bundle ID
and must match Runner's bundle identifier when packaging a renamed host.

`TECHPIE_WIDGET_URL_SCHEME` defaults to `techpie`; `techpie://deadlines` opens the
existing Deadlines destination on cold and warm launches. Local QA builds should
override the group, scheme and host/extension bundle identifiers using an ignored
or external xcconfig. Use a unique display name, install the host in an application
directory, and select its native widget rather than the iPhone/TestFlight widget.

## Validation

```sh
swift test --package-path apple/DeadlineWidgets
flutter test
flutter analyze --no-pub
git diff --check
```

The `DeadlineWidgets` macOS scheme and `EcardPayWidget` iOS scheme allow compiling
the extensions without building the Flutter host. iOS can be compiled using the
installed `iphoneos` SDK and `CODE_SIGNING_ALLOWED=NO`; no simulator is required.
Real iOS installation, App Group access and system widget behavior still require
physical-device validation. Native system tests should cover all three sizes,
long titles, empty and single-item states, light/dark appearance, hourly and
expiry transitions with the host closed, completion/hidden changes and correct
app navigation.

### Validation performed

- Flutter's full test suite passed. Focused tests also verify cold/warm navigation,
  cache publication, completion/hidden changes, account replacement, logout,
  stale requests and deduplication. `flutter analyze --no-pub` and
  `git diff --check` passed.
- All seven Swift tests passed, covering schema validation, atomic storage,
  local dates/year boundaries, hourly urgency transitions, expiry and 2/4/8 limits.
- A signed macOS source build was installed under a separate QA identity. All
  three native widget sizes displayed real deadlines, and widget navigation
  opened the QA app's Deadlines page. Synthetic long titles/course names and
  2/4/8-item layouts were checked without overlap.
- The iOS widget extension compiled unsigned for arm64 with the installed
  iPhoneOS 18.5 SDK. The native host bridge passed type checking. A full Runner
  build was blocked by the local Xcode installation reporting
  `iOS 18.5 Platform Not Installed` when compiling a plugin storyboard.
  No simulator or platform download was performed. Full host compilation,
  signing and device runtime checks remain necessary before iOS distribution.
