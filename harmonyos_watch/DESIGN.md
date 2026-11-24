# Watch interaction design

TechPie Watch opens on the campus code. Turning the Crown or swiping vertically moves through campus code, timetable and deadlines. A rightward swipe returns from a detail view; at the root it exits the app. The GT 6 Pro implementation follows watchOS principles for glanceable content and shallow navigation using HarmonyOS Lite controls and system fonts.

## Round-screen layout

The 466 px round display centers the campus code on black. The timetable and deadline pages show up to three summaries with the title above the time and location or course. Deadlines within 24 hours and overdue items use amber text. A capsule opens the full list. Three dots near the lower edge mark the current page. Tap the campus-code title to open the account view.

| Element | Dimensions |
| --- | --- |
| Main title | 30 px in a 210 × 48 px target |
| Summary card | 338 × 80 px with 28 px primary and 22 px secondary text |
| List action | 218 × 48 px |
| Detail card | 338 × 196 px |
| Campus-code canvas | 265 × 265 px. A 45-module code uses 5 px cells and a four-module quiet zone. |

The vertical native `swiper` owns Crown focus on the root. Native `list` owns it in details through `rotation({focus: true})`. Root pages contain stacks rather than nested lists. The QR encoder uses byte mode, error correction M, integer-sized modules and a quiet zone of at least four modules. Circular launcher icons preserve the original red P pixels.

## Data and connection lifecycle

Account, timetable and deadlines are stored in the app's private files under a stable account binding. Transport closure, heartbeat loss, sleep and app exit end the session while preserving cached data. The next launch reads that data before synchronization. Last-sync labels distinguish cached content from a current sync. The seven-day timetable and deadline window advance only when the phone provides a new snapshot.

Android remembers the explicitly selected watch and its signing identity. Foreground launch/resume, native reconnection and a watch `peer.ready` signal trigger a fresh authenticated handshake and snapshot sync without repeating an already granted permission prompt. Retries run only while the phone app is in the foreground. Huawei Health must have paired and connected the devices. Lite apps stop running after exit; synchronization resumes when both apps can run.

Logout, account changes and explicit revocation clear the owner's cached data. When disconnected, Android records a pending clear and drains it before a new account binding. A disconnected watch receives that revocation on the next sync.

## Campus codes

Android fetches the online campus code using the signed-in campus card, encodes the original bytes as a QR matrix and sends it over the authenticated Wear Engine session. The watch paints the matrix until its 30-second validity ends. After explicit Android opt-in, the watch saves an unlimited-use offline grant under the paired account using AES-GCM. Opening the campus-code page displays a valid code or requests one from the connected phone. When disconnected or after a phone request times out, a restored offline grant starts generation automatically. Tap to refresh an expired code or retry a failed attempt.

The first offline request during a page visit checks the public key against the signing key. Each presentation uses native randomness and signs the issuer bytes and timestamp with SM2/SM3. The page draws the binary payload until the earlier of grant expiry and 30 seconds from its timestamp. Changing pages or hiding the app cancels queued work.

A paired watch can request a code while TechPie is in the background if Android can run the Flutter engine and the Wear Engine receiver is registered. Reopening the watch can initiate a new handshake through that receiver. After process death, force-stop or receiver loss, open TechPie on the phone to restore the connection.

## Acceptance

On 0.4.19, with Android TechPie stopped, the GT 6 Pro displayed the offline QR code and countdown on launch without a tap. The user turned the Crown through the timetable and deadlines and confirmed that summaries and buttons fit the round screen.

On a GT 6 Pro running 0.4.16, the watch acknowledged the offline grant and timetable. With the Android app force-stopped, reopening the watch app and tapping the campus-code prompt displayed a QR code and expiry countdown. The user estimated 13 seconds. The device recorded 17,707 ms from tap to draw, including 8,476 ms for key preparation and signing, 8,984 ms for QR encoding and 127 ms for painting. Reader acceptance remains unverified.

The GT 6 Pro recorded 8,996 ms for the original QR encoder in 0.4.17. Scoring eight masks took 4,802 ms. The screen went black during that run and the user could return to the watch face. Version 0.4.18 reuses one layout and scores 32 columns at a time. Across 87 synthetic inputs, the resulting matrices and all 696 mask scores matched the previous encoder.

With Android TechPie force-stopped, the user opened 0.4.18 on the watch and confirmed that the offline QR code and countdown appeared. The watch recorded 10,428 ms from tap to draw, including 8,509 ms for key preparation and signing, 1,676 ms for encoding and 124 ms for painting. Within the encoder, scoring took 681 ms, layout 358 ms, data and error correction 169 ms, packing 141 ms and version selection 4 ms.

Host tests cover background handshakes, online QR data, expiry, account isolation and cache persistence. GT 6 Pro background delivery, screen-off stability and optical scanning still require device verification for 0.4.8.

## References

- [Designing for watchOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-watchos)
- [Apple layout](https://developer.apple.com/design/human-interface-guidelines/layout)
- [Apple typography](https://developer.apple.com/design/human-interface-guidelines/typography)
- [Apple accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- [Huawei Lite Wearable guide](https://developer.huawei.com/consumer/en/doc/lite-wearable-guides/lite-wearable-bpta-guide/)
- [Huawei Lite swiper](https://developer.huawei.com/consumer/en/doc/harmonyos-references/js-lite-components-container-swiper/)

The device JerryScript profile disables regular expressions and ES2015 built-ins. Validation uses character checks. The package hook rejects RegExp and BigInt syntax in the final generated AST. See the [OpenHarmony JerryScript profile](https://github.com/openharmony/third_party_jerryscript/blob/master/jerry-core/config.h).
