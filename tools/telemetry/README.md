# TechPie usage reports

The collector writes opt-in app events to SQLite. Its command-line report combines aggregate usage counts with store installation counts supplied by distributors. Run the following commands from the repository root with Python 3.9 or later.

## Run locally

Start the collector on `127.0.0.1:8787`. The command creates the database. Use the same file for imports and reporting.

```sh
python3 tools/telemetry/telemetry.py --db /tmp/techpie.sqlite serve
```

Point a local desktop build at that listener with the Flutter build define below. A physical device needs a URL it can reach. The server accepts `--host` and `--port` after `serve`.

```sh
flutter run -d linux --dart-define=TECHPIE_TELEMETRY_URL=http://127.0.0.1:8787/api/telemetry
```

The default build destination is `https://techpie.geekpie.club/api/telemetry`. A public release needs a separately deployed collector reachable at its configured URL. The verification commands here use the local listener.

```sh
python3 tools/telemetry/telemetry.py --db /tmp/techpie.sqlite import-installs store.csv
python3 tools/telemetry/telemetry.py --db /tmp/techpie.sqlite report --as-of 2026-11-25T00:00:00Z
python3 -m unittest discover -s tools/telemetry -v
flutter test --no-pub test/telemetry_client_contract_test.dart
```

The report prints JSON. Omitting `--as-of` uses the current time. The cutoff includes events at that instant and uses client event time, so delayed uploads can revise earlier results.

## Submit events

Send `POST /api/telemetry` with `Content-Type: application/json` and 1–100 events in a body of at most 65,536 bytes. Omit credentials. The collector rejects cookies and authorization headers and supports anonymous CORS preflight. It disables HTTP request logging.

```json
{
  "installation": "a70438eaf24e43d0bebe449ab18bde1b",
  "events": [{
    "id": "86785ed2114d4e0dbe4f135687565ed1",
    "kind": "feature_open",
    "at": 1795564800000,
    "version": "1.1.0+32",
    "platform": "android",
    "feature": "grades"
  }]
}
```

Generate independent random 32-character lowercase hexadecimal identifiers for each installation, event and visit. Reuse the visit identifier throughout a single form or recording visit. Supply UTC epoch milliseconds for `at`, a three-part `version` with optional `-rc.N` and `+build` suffixes (for example `1.1.0-rc.1+32`), and one of `android`, `ios`, `linux`, `windows`, `macos`, `ohos`, `web`, `fuchsia` or `unknown` for `platform`. Each version component and the release candidate number accept up to six decimal digits. The build number accepts up to twelve.

| Event kinds | Additional required fields |
| --- | --- |
| `first_launch`, `app_open`, `first_login` | None |
| `feature_open` | `feature` from the registry in `storage.py` |
| `feedback_open`, `feedback_attempt`, `feedback_success`, `feedback_failure`, `recording_open` | `visit` |
| `recording_ready`, `recording_error`, `recording_exit` | `visit` and `elapsed` in milliseconds since the feature opened |

The collector rejects unknown fields and validates the entire batch before writing. HTTP 204 confirms the database commit. Retry a batch with the same event IDs so an interrupted response cannot count events twice.

## Import store counts

Normalize each distributor's installation export to the CSV header below. Use one UTC date in `YYYY-MM-DD` format, a lowercase distributor slug, a platform and a nonnegative integer daily install count per row.

```csv
day,distributor,platform,installs
```

Reimporting replaces the count for the same day, distributor and platform. Reports include completed UTC days. An absent row means the distributor count is unknown. A row with zero means the distributor reported zero installs.

## Interpret the report

- **Adoption.** Participating first launches count each installation once. Monday UTC cohorts show how many completed their first login within seven days, inclusive, and the percentage of observed first launches. Cohorts stay provisional until the last instant of the week has had a full seven days. The report also counts observed installations whose individual windows have closed.
- **Active installations.** Each installation with a first launch or app open in the 30 days ending at the cutoff counts once. The interval excludes its starting instant and includes guest activity.
- **Daily feature usage.** Each installation counts once per feature per UTC day.
- **Feedback.** Opened and delivered counts refer to distinct forms. Each reported submission error counts separately. The app records an attempt before the request and success after acknowledgement. A request timeout leaves the attempt unconfirmed. For forms at least 24 hours old, the report counts deliveries within 24 hours, forms with no attempt by then, and forms with a failed or unconfirmed attempt by then. A later success contributes once to eventual deliveries and preserves the form's status at 24 hours.
- **Lecture recordings.** Error and exit percentages use all opened visits in their group. Early errors include the first 10 seconds and count affected installations once. A usable recording list is the first nonempty course list. Leaving the recording route or moving the app to the background ends the visit. Resuming on the recording route starts another visit. Early exits include the first 30 seconds and distinguish a usable list, an error, both or neither before exit. Open-window counts identify visits still young enough to change those rates. Each version and platform group also shows its overall error rate and the median and linearly interpolated 95th percentile of first usable list times in milliseconds. An empty timing sample yields `null`.
