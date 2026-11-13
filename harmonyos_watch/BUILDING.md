# Watch companion builds

On a clean checkout, `build.ps1` creates an unsigned local `build-profile.json5`
from `build-profile.template.json5`. It never overwrites an existing profile.
The generated profile is ignored by Git. Configure device installation signing
locally in DevEco Studio; signing material and passwords must stay local.

The committed phone identity matches the signed Android release certificate.
Both `build.ps1` and the Lite packaging hook validate it against
`.github/workflows/android-release.yml` before packaging and signing.

For a local Android debug APK, explicitly supply its public certificate SHA256:

```powershell
$env:HUAWEI_PHONE_FINGERPRINT = '<64 hexadecimal characters from your debug certificate>'
./build.ps1
Remove-Item Env:HUAWEI_PHONE_FINGERPRINT
```

The override changes generated watch JavaScript only. Never commit a debug
certificate into `wear-config.js`, and leave this environment variable unset
when packaging the companion for Android release users. The build mode named
`debug` is the SDK's Lite BIN packaging path; it does not select the phone's
certificate. A fresh compilation is required when changing the override.

Run the portable checks without the Huawei SDK:

```sh
node --test harmonyos_watch/scripts/*.test.cjs harmonyos_watch/scripts/*.test.mjs
```

Before distribution, verify pairing using the signed phone and watch artifacts,
then check code scanning, code expiry, reconnect, logout, and reminder delivery
on a supported watch. Unit tests cannot verify vendor authorization or optics.


## Approved Wear Engine scope

The Android companion is `club.geekpie.techpie`, App ID `119331345`. The
approved service is device basic information, including P2P. The normal status,
device discovery and connection flow only checks/requests `DEVICE_MANAGER`.
Account, DDL, timetable and campus-code snapshots use that P2P channel.

The watch advertises `schedule.display` and `reminder.watchLocal` alongside the
existing capabilities. Timetable snapshots contain the next seven campus days
(Asia/Shanghai), including fetched courses, custom sessions and exams from the
phone's selected semester. A snapshot contains at most 50 complete course
blocks; the watch shows a truncation message when needed. Old peers negotiate
their supported resources. Each resource has its own revision and receipt.

The phone's DDL reminder switch sends an opt-in in `ddl.snapshot`. The watch
checks `remindAtMs` against the phone-calibrated clock and vibrates locally using
`@system.vibrator` / `ohos.permission.VIBRATE`. Opt-in is off on each connection.
Only future triggers fire, once, while the watch app is open and the P2P session
is valid. Hiding/closing the app, disconnecting, logging out or the 24-hour lease
expiring clears the session. There is no background delivery through this path.
The existing native phone-notification integration is not exposed by this
switch; Wear Engine `NOTIFY` and remote-app launch remain unapproved.

For device acceptance, install matching signed companions, open the watch app,
and connect through Settings → HUAWEI WATCH on Android. Check name/student ID,
DDL receipt, seven-day courses (including a custom session and exam), QR scan
and expiry, and a future reminder while the watch app stays open. Then check
app hide, disconnect, account switch and reconnect clear old data and reminder
consent. Confirm the Android certificate matches the watch's configured phone
fingerprint; a debug APK needs the explicit debug-fingerprint override above.

Vendor vibration API: https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-system-vibrate/
