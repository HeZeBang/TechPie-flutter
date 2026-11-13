# Watch interaction design

TechPie Watch provides quick access to campus codes, the next class, deadlines and account identity on HUAWEI WATCH GT 6 Pro. Its interface follows Apple's watchOS Human Interface Guidelines for glanceable content, shallow navigation, readable text and direct actions. The implementation uses HarmonyOS Lite components and the device's system font.

## Information hierarchy

The home screen presents the next class and the campus-code action first. Scrolling reveals the timetable entry, the next deadline, the deadline list, account details and connection help. Each destination returns directly home through a visible button or the system back action.

| View | Primary content | Actions |
| --- | --- | --- |
| Home | Next class, start time and location; next deadline | Open campus code, timetable, deadlines, account or help |
| Timetable | One campus day, ordered course blocks | Previous/next day across the seven-day snapshot, sync, home |
| Deadlines | Open tasks, due time, overdue/near-due label | Scroll, previous/next six-item group, sync, home |
| Campus code | Black modules on a white canvas and remaining validity | Refresh, home |
| Account | Name, student ID and connection state | Sync, text size, home |
| Connection help | Pair in Huawei Health, then connect from TechPie | Retry, home |

Read-only cards carry content. Capsule buttons carry actions. Text names every action; status and urgency also have explicit labels. The app uses native vertical lists for touch and Crown scrolling. Huawei's Lite Wearable guide identifies `list`, `slider` and `swiper` as Crown-enabled components. Crown behavior on the target firmware awaits GT 6 Pro acceptance. Crown presses remain system-owned.

## Visual system

The 466-logical-pixel round target uses a black canvas, neutral cards and one blue action accent. Amber marks due-state labels, accompanied by text. Device system fonts provide Chinese and Latin glyphs. Apple font binaries and SF Symbols are not embedded.

| Role | Source size |
| --- | --- |
| Page title | 38 px |
| Card headline | 32 px |
| Primary action | 45 px |
| Standard action | 42 px |
| Supporting text | 26 px |
| Caption / status | 24 px |
| Primary and secondary action height | 88 px |
| Card / primary action width | 336 px |
| Round-edge leading/trailing space | 56 px |

Apple's watchOS typography guidance specifies a 16-point default and 12-point minimum. Its accessibility guidance gives a 44-by-44-point default control size and a 28-by-28-point minimum. The pixel values above are implementation choices for GT 6 Pro; physical readability and touch comfort require device acceptance. The account view provides a 140-percent text option for the current app session.
Content text scales by semantic role. Action labels use large fixed sizes; controls retain their touch area and content
remains vertically scrollable. Source defaults are in `pages/index/index.css`;
the scale values live in `pages/index/index.js`.

Standard actions fill the available content width. Day navigation places two text buttons in one row. Content rows scroll vertically, with one flex child per Lite `list-item`. Each view keeps contextual actions close to its content. The QR view also scrolls so refresh and back retain full-height touch targets.

The QR canvas is 264 by 264 pixels. Integer-sized black modules retain a quiet zone of at least four modules. The code's expiry and refresh behavior continue to use the phone-calibrated session clock. The launcher icons retain the original red P pixels inside an exact circular alpha mask.

## Lifecycle and permissions

First paint precedes native Wear Engine initialization. Startup failures appear on screen and in the lifecycle log. Vibration loads when a reminder fires. Account, timetable, deadline and code data continue over the approved device-manager P2P channel. Local reminders require phone opt-in, a valid connection and a foreground watch app. Hiding the app clears the session and code.

Apple-specific system integrations such as SwiftUI controls, Dynamic Type, complications, Always On and watchOS notifications require an Apple Watch target. The GT 6 Pro build uses its available platform features. Its approved Wear Engine scope covers basic device information and P2P; notification delivery and remote app launch remain unapproved.

## Acceptance status

The Huawei SDK compiled the redesigned page, and its minified output fits the 48 KiB project page limit. Device testing is deferred at the user's request. Pending checks cover first paint after the reported black screen, round-screen clipping, long names, empty/loading/error states, touch and Crown navigation, code scanning/expiry, all synchronized resources and reminder/session cleanup. A successful build records source compatibility; device results determine runtime acceptance.

## Design references

- [Designing for watchOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-watchos)
- [Layout](https://developer.apple.com/design/human-interface-guidelines/layout)
- [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons)
- [Typography](https://developer.apple.com/design/human-interface-guidelines/typography)
- [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- [Digital Crown](https://developer.apple.com/design/human-interface-guidelines/digital-crown)
- [Scroll views](https://developer.apple.com/design/human-interface-guidelines/scroll-views)
- [Apple Design Resources](https://developer.apple.com/design/resources/#watchos-apps)

- [Huawei Lite Wearable guide](https://developer.huawei.com/consumer/cn/doc/lite-wearable-guides/lite-wearable-bpta-guide/)
