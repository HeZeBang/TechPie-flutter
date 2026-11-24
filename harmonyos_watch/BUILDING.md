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

The phone's DDL reminder switch sends an opt-in in `ddl.snapshot`. The watch checks cached `remindAtMs` against the phone-calibrated clock and vibrates locally using `@system.vibrator` / `ohos.permission.VIBRATE` while the app is in the foreground. Communication loss preserves the snapshot. Lite apps provide no background process after exit. Wear Engine `NOTIFY` and remote app launch remain unapproved.

The app uses P2P as a synchronization channel. First authorize and select the watch in Android Settings → HUAWEI WATCH. Later launches restore the saved pairing and synchronize automatically while both applications can run. Account, timetable and deadlines remain available from private watch files after disconnect and restart. The watch requests online campus codes from the Android companion. See [interaction design](DESIGN.md) for the receiver lifecycle.

Device acceptance uses matching signed companions. Check Crown switching and right-swipe navigation, the default campus-code screen, cached content after both app exit and full disconnection, automatic sync in both launch orders, logout/account isolation, and online-code expiry while the phone app is in the background. Validate optical scanning separately. Keep signing material and credential payloads out of logs and artifacts.

Vendor vibration API: https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-system-vibrate/

Android authorization callbacks contain Parcelable `Permission` objects.
Compare their `name` values when reading grants; this SDK does not implement
value equality for those objects.


The local-vibration permission declares its reason and `MainAbility` in-use
scene in `module.reqPermissions`. Keep permission declarations there; the
source Lite schema does not accept `abilities.permissions`.

The application store owns Wear Engine and cache lifecycle; the page observes that store. Keep each generated `app.js` and page JS at or below 48 KiB. The packaging hook minifies ES5 output with Terser before BIN generation.

The 0.3.1/0.3.2 acceptance established the explicit-dimension startup fix and circular icons. The 0.4.1 application and page bundles evaluated to booleans, and the GT 6 Pro showed a black screen. The 0.4.2 build preserves the final expression and checks that each entry returns its ViewModel. The device accepted the package.

On GT 6 Pro with 0.4.3, Android reported a ready session and the watch acknowledged the account and deadline snapshots. The schedule snapshot failed with `SERVICE_UNAVAILABLE` while the phone timetable source reported an error. The connection subsequently dropped. The receiver test covers an undeliverable startup announcement when the phone opens second.

## SM2 device benchmark

Generate a separate Lite project from the repository root. Choose a new output directory.

```sh
node harmonyos_watch/benchmark/prepare.cjs ../gt6-bench
```

Configure signing in the generated project's `harmonyos_watch` directory and run
`build.ps1` there. On the GT 6 Pro, tap **测试签名** once. Record the total and
the **执行 / 等待** times from the same run. **测试绘制** measures QR drawing
separately. Both tests use public fixtures. The regular build opens the online
campus code and omits the benchmark.

On a GT 6 Pro, the 0.4.13 public-fixture run took 3,705 ms, including
3,214 ms executing and 491 ms waiting between slices.
