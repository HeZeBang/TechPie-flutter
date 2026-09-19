# TechPie Apple Watch

This watchOS 10+ companion application is embedded in the existing iPhone app.
Open `Runner.xcworkspace`; use `Runner` for the phone and `TechPieWatch` for the watch.
Configure Flutter with the SDK matching this repository's locked dependencies
before building. `Watch.xcconfig` uses Flutter's generated version/build number so
the phone and embedded watch app remain aligned.

The home screen opens a native vertical `TabView` inside a `NavigationStack`.
The system owns back navigation. Payment uses a transparent, zero-padding deep-red
binary QR; tapping the QR or caption regenerates it locally. A valid code is
prepared on foreground entry; periodic generation runs only on the active payment
page. Brief inactivity, page previews and Always On retain the rendered code and
card information. Renewal replaces the image only when the new one is ready;
revocation, expiry or an account switch clears it. Card data contains the holder name, student ID,
balance in fen, and the phone fetch time.

## Pairing and updates

1. Install the phone and watch apps, and open TechPie on the watch.
2. In the phone's Settings, open Apple Watch and enable the campus card.
3. The phone must have a verified campus-card identity and an offline authorization.
   It sends a complete matching key/authorization bundle to the enrolled watch
   installation. Missing/expired credentials still allow card information to sync.
4. Phone card refreshes and successful authorization renewals trigger sync.
   “更新并同步” refreshes the card and attempts renewal when due. The watch stores
   the version atomically in Keychain and acknowledges it before the phone reports
   completion. Sending a cached balance preserves its original fetch timestamp.

The phone settings show one status summary and one update action. The two device
expiry fields, version counters and a deduplicated 20-entry in-memory operation
history are available under the initially collapsed sync details. Passive status
checks do not create a foreground loading state or clear an outstanding failure
merely because an older revision was acknowledged.

Both devices share the existing private key and author info. The phone derives
the offline protocol's one-byte SM3/XOR device checksum, so the watch produces
the same time field without receiving the raw campus-card OpenID. No login
identifier, session cookie or SSO credential is exported.
Only unlimited grants with a known expiry are eligible for watch export. The
upstream inclusive UTC expiry is sent as the next day's exclusive boundary.
A bounded/undated grant requires phone-side renewal; the watch invents no allowance.

Transfers target one watch installation and carry a persisted phone source ID and
increasing revision. A new source must answer the watch's current enrollment
challenge. Stale/duplicate deliveries cannot reinstall older grants. Disable or
sign-out transmits an empty versioned state. A disconnected watch receives that
revocation on reconnection and remains subject to local expiry until then.
WatchConnectivity queues the latest full state and also uses live messaging when
available. Pending and received credentials use device-only Keychain storage,
not UserDefaults or application logs.

Enrollment requires a live handshake from the system-authenticated counterpart.
The watch installation ID, not `watchDirectoryURL`, binds subsequent delivery.
When iOS reports stale installation metadata despite a working handshake, the
watch can fetch the enrolled snapshot through the reply to its own sync request.
It checks while the app is active and stops on inactivity. The optional cache
diagnostic contains only fixed stage names, platform codes and connection flags;
it contains no identity or credential values.

## Validation

Run `swift test --package-path ios/WatchSupport` for signature interoperability,
binary QR, expiry, credential matching and snapshot version tests. Flutter tests
in `test/watch_sync_service_test.dart` cover enrollment and account/disable races.
Actual background delivery and payment acceptance require paired physical devices.
Simulator arguments `--watch-preview --preview-pay` / `--preview-info` exist only
in Debug simulator builds; they use synthetic data and never persist or transfer
it. Launch without them to test the real unconfigured flow.

Transparent QR presentation requires validation on the campus scanners, including
small watch displays. A successful build/preview does not prove a completed payment.
