# Campus-card spending alerts

Android users can opt into **校园卡消费提醒** in Settings. An alert shows the amount, merchant/location and balance when a fresh consumption record is discovered. Refunds, recharges, subsidies and transfers are not announced as spending. Notification details use private lock-screen visibility.

The existing payment/history refresh supplies its full recent page to the notification port. A separate WorkManager task also checks up to 50 recent records when networking is available, at the platform's 15-minute minimum interval. This is polling, not a server push: delivery depends on ledger publication, network availability, notification permission and Android scheduling. It is not guaranteed to arrive at the time of the transaction.

## State and lifecycle

- Off by default. Scheduling requires accepted privacy terms, a signed-in primary account, a configured campus card and Android notification permission.
- The first successful snapshot is recorded silently. An empty first page is still an initialized baseline, so the first subsequent payment can be announced.
- Foreground and background Flutter engines submit snapshots to one synchronized native ledger. The ledger stores only an opaque hash of the primary/card identity, up to 200 hashed transaction IDs and timestamps. Notification text and credentials are not persisted there or logged.
- Snapshot merging deduplicates repeated IDs, sorts fresh receipts oldest-first, announces at most three per refresh and folds the remaining count into the last message. Only the first alert in a burst can make a sound. Old timestamps below the retained window cannot replay when IDs are evicted. Backfilled transactions older than that window may therefore be omitted.
- Disabling, signing out or changing accounts cancels periodic work, clears visible spending notices and resets the baseline. Native generation checks discard results from a request started before disable/re-enable, including when the same account returns.
- Background runs create and dispose their Flutter engine and channels on Android's main thread; only the bounded wait uses the worker thread. Work is network-constrained, limited to 60 seconds and at most two retries per failed cycle. No foreground service or resident keepalive is added.
- Payment success and history rendering do not depend on notification delivery. Demo/debug transactions are not sent to the notification port.

## Scope and compatibility

Ported from RCCE's spending-alert and periodic-refresh implementation, with explicit account scoping, a first-read baseline and a shared native deduplication ledger for upstream integration. The existing upstream application ID, minimum Android SDK, release version, signing, Apple Watch integration, pubspec/lock and release workflows are retained.

This PR is independent of #194 (course/deadline island), #195 (Xiaomi wearable integration and class reminders) and #196 (cover/rear glance). It does not copy their modules. Class reminders already belong to #195; this change covers campus-card consumption notifications.

## Validation

- Flutter analysis; 777 Flutter tests passed.
- Nine native `SpendingLedgerTest` cases passed: first/empty baseline, duplicate/overlapping pages, same-timestamp payments, non-spending records, disabled/in-flight reads, owner changes, bounded history and invalid timestamps.
- Dart service tests: opt-in, consent/platform gates, opaque payloads, account mismatches, concurrent configuration, background cancellation and transient failures.
- Android debug and minified release APKs, and native unit tests. The release smoke build used a local test key only; upstream signing configuration remains unchanged. Real campus transactions, OS background restrictions and notification permission UX require device acceptance; mocked tests cannot establish delivery latency.

Full Android lint also reports two pre-existing upstream errors outside this change: the API-28 private-DNS diagnostic call in `EcardBindVpnService.kt`, and the missing optional-camera hardware declaration in the base manifest. No errors remain in the added notification code. These unrelated base issues are not suppressed or folded into this feature PR.
