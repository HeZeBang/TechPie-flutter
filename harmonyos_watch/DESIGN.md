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

Logout, account changes and explicit revocation clear the owner's cached data. When disconnected, Android records a pending clear and drains it before a new account binding. A disconnected watch receives that revocation on the next sync.

## Campus codes

Android fetches the online campus code using the signed-in campus card, encodes the original bytes as a QR matrix and sends it over the authenticated Wear Engine session. The watch paints the matrix until its 30-second validity ends. After explicit Android opt-in, the watch saves an unlimited-use offline grant under the paired account using AES-GCM. A tap on the code page then generates a new code on the watch.

The first offline request during a page visit checks the public key against the signing key. Each presentation uses native randomness and signs the issuer bytes and timestamp with SM2/SM3. The page draws the binary payload until the earlier of grant expiry and 30 seconds from its timestamp. Changing pages or hiding the app cancels queued work.

A paired watch can request a code while TechPie is in the background if Android can run the Flutter engine and the Wear Engine receiver is registered. Reopening the watch can initiate a new handshake through that receiver. After process death, force-stop or receiver loss, open TechPie on the phone to restore the connection.

## Acceptance

On a GT 6 Pro running 0.4.16, the watch acknowledged the offline grant and timetable. With the Android app force-stopped, reopening the watch app and tapping the campus-code prompt displayed a QR code and expiry countdown. The user estimated 13 seconds. The device recorded 17,707 ms from tap to draw, including 8,476 ms for key preparation and signing, 8,984 ms for QR encoding and 127 ms for painting. Reader acceptance remains unverified.

Host tests cover background handshakes, online QR data, expiry, account isolation and cache persistence. GT 6 Pro background delivery, screen-off stability and optical scanning still require device verification for 0.4.8.

## References

- [Designing for watchOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-watchos)
- [Apple layout](https://developer.apple.com/design/human-interface-guidelines/layout)
- [Apple typography](https://developer.apple.com/design/human-interface-guidelines/typography)
- [Apple accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- [Huawei Lite Wearable guide](https://developer.huawei.com/consumer/en/doc/lite-wearable-guides/lite-wearable-bpta-guide/)
- [Huawei Lite swiper](https://developer.huawei.com/consumer/en/doc/harmonyos-references/js-lite-components-container-swiper/)

The device JerryScript profile disables regular expressions and ES2015 built-ins. Validation uses character checks. The package hook rejects RegExp and BigInt syntax in the final generated AST. See the [OpenHarmony JerryScript profile](https://github.com/openharmony/third_party_jerryscript/blob/master/jerry-core/config.h).
