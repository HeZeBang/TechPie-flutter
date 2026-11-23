# Watch interaction design

TechPie Watch opens on the campus code. Turning the Crown or swiping vertically moves through campus code, timetable and deadlines. A rightward swipe returns from a detail view; at the root it exits the app. The GT 6 Pro implementation follows watchOS principles for glanceable content and shallow navigation using HarmonyOS Lite controls and system fonts.

## Round-screen layout

The 466 px canvas is black. Each of the three pages presents one primary item, with neutral capsule actions and a restrained teal accent. Course and deadline lists open as details. The account view opens from the campus-code title. Titles, rows and containers have explicit Lite dimensions. The custom text-enlargement control remains removed.

| Element | Dimensions / size |
| --- | --- |
| Main title | 32 px, centered below the round edge |
| Glance headline | 36 px, 320 px wide |
| Supporting content | 24 px |
| Status | 21 px |
| Main action | 290 × 76 px |
| Detail card | 320 × 196 px |
| Campus-code canvas | 264 × 264 px |

The vertical native `swiper` owns Crown focus on the root. Native `list` owns it in details through `rotation({focus: true})`. Root pages contain stacks rather than nested lists. The QR encoder uses byte mode, error correction M, integer-sized modules and a quiet zone of at least four modules. Circular launcher icons preserve the original red P pixels.

## Data and connection lifecycle

Account, timetable and deadlines are stored in the app's private files under a stable account binding. Transport closure, heartbeat loss, sleep and app exit end the session while preserving cached data. The next launch reads that data before synchronization. Last-sync labels distinguish cached content from a current sync. The seven-day timetable and deadline window advance only when the phone provides a new snapshot.

Android remembers the explicitly selected watch and its signing identity. Foreground launch/resume, native reconnection and a watch `peer.ready` signal trigger a fresh authenticated handshake and snapshot sync without repeating an already granted permission prompt. Retries run only while the phone app is in the foreground. Huawei Health must have paired and connected the devices. Lite apps stop running after exit; synchronization resumes when both apps can run.

Logout, account changes and explicit revocation clear the owner's cached data and offline credential. When disconnected, Android records a pending clear and drains it before a new account binding. A disconnected watch receives that revocation on the next sync.

## Local campus codes

The phone switch explicitly authorizes copying an existing, unexpired, unlimited-use campus-code grant and its signing key to the selected watch. Enrollment does not activate or renew a grant. Limited-use grants remain on the phone because two independent devices cannot share an offline usage counter.

The watch vault uses a native HUKS AES-256-GCM key, fresh native random nonces and the account binding as authenticated data. A successful encrypt/decrypt self-test enables the offline capability. Credential files contain ciphertext; business-data snapshots and pairing metadata contain no signing keys.

The watch constructs the existing five-byte time CRC, signs author-info plus CRC with SM2/SM3 and the protocol's default user ID, then builds the QR matrix locally. Native CSPRNG output supplies signature randomness. An expired grant stops local issuance. Online code snapshots remain a connected fallback and expire after 30 seconds.

The page accesses the store through `getApp().data.api`. The Lite build separates transport, storage and QR encoding in `app.js` from signing and UI in the page bundle. Each generated JS file must fit 48 KiB. The runtime records elapsed milliseconds from local signing through canvas painting. The one-second target requires GT 6 Pro measurement.

## Acceptance

Host checks cover cache retention across restart, account isolation and revocation, persistence receipts, automatic pairing recovery, permission handling, encrypted credential storage and binary QR compatibility. The existing Dart implementation independently verifies the JavaScript SM2 signature and rejects a modified payload.

Device acceptance for 0.4.2 covers Crown page switching, right-swipe return, default campus code, cache after app exit and full disconnection, reconnection with either app opened first, and local-code latency. Optical campus-terminal scanning is a separate acceptance step. Earlier 0.3.1/0.3.2 device confirmations establish startup and icon fixes; they do not validate this redesign. Reminder testing was stopped at the user's request.

## References

- [Designing for watchOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-watchos)
- [Apple layout](https://developer.apple.com/design/human-interface-guidelines/layout)
- [Apple typography](https://developer.apple.com/design/human-interface-guidelines/typography)
- [Apple accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- [Huawei Lite Wearable guide](https://developer.huawei.com/consumer/en/doc/lite-wearable-guides/lite-wearable-bpta-guide/)
- [Huawei Lite swiper](https://developer.huawei.com/consumer/en/doc/harmonyos-references/js-lite-components-container-swiper/)

The device JerryScript profile disables regular expressions and ES2015 built-ins. Validation uses character checks; SM3 clears typed arrays with ES5 loops. The package hook rejects RegExp and BigInt syntax in the final generated AST. See the [OpenHarmony JerryScript profile](https://github.com/openharmony/third_party_jerryscript/blob/master/jerry-core/config.h).
