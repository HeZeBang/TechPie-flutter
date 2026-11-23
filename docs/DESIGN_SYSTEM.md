# TechPie Design System

This document is the single visual source of truth for **TechPie-flutter** across iOS, Android, HarmonyOS NEXT (OHOS), macOS, Windows, and Linux.

## 1. Core Architectural Rule

**Unified content language; platform-native shell & system controls.**

- **Content layer (`lib/pages/`, `lib/widgets/design_system/`)**: 100% unified across every platform. All colors, surfaces, radii, typography, icons, cards, badges, and progress rows come from `lib/theme/` and `lib/widgets/design_system/`. Pages must **not** branch on `isIos()` / `usesIosLiquidGlass()` / `TargetPlatform` to alter visual styling, and must **not** use raw `Color(0x...)`, `Card.outlined`, or `Card.filled`.
- **Shell & system layer (`lib/widgets/app_shell/`, `lib/widgets/adaptive_*.dart`, `lib/widgets/ios/`)**: Owns platform-native chrome and interactions — iOS 26 Liquid Glass `IosNativeTabBar` / `IosNativeNavigationBar` + SF Symbols + haptics, Android/OHOS floating glass `TgBottomNavBar`, Desktop `DesktopShell` sidebar, and native system dialogs/pickers/switches.

## 2. Design Tokens (`lib/theme/tp_tokens.dart`)

### Spacing (4 dp grid)

| Token | Value |
|---|---|
| `space1` / `space2` / `space3` / `space4` / `space5` / `space6` / `space8` | `4 / 8 / 12 / 16 / 24 / 32 / 48` |
| `pageHorizontalPadding` / `pageHorizontalPaddingWide` | `16` / `24` |
| `cardPaddingHorizontal` / `cardPaddingVertical` | `16` / `14` |
| `sectionGap` | `12` |
| `singleColumnMaxWidth` / `bentoBreakpoint` | `680` / `960` |

### Border Radii (4 standard tiers + pill)

| Token | Value | Usage |
|---|---|---|
| `radiusBar` | `2` | 3 dp vertical accent bar & 4 dp progress bar |
| `radiusXs` | `6` | Compact micro-chips |
| `radiusS` | `10` | Quick-action icon tiles, timetable course blocks, embedded chips |
| `radiusM` | `16` | Standard cards (`TpCard`), Deadline cards, floating snackbars |
| `radiusL` | `24` | Dialogs, bottom sheets, campus card hero |
| `radiusPill` | `999` | Status badges (`TpBadge`), floating tab capsules |

## 3. Color System (`lib/theme/tp_colors.dart`)

Access via `context.tpColors` (registered as a `ThemeExtension<TpColors>` by `ThemeService`).

| Role | Light | Dark | Dark AMOLED | Purpose |
|---|---|---|---|---|
| `canvas` | `#F2F2F7` | `#0A0A0A` | `#000000` | Page background (`scaffoldBackgroundColor`) |
| `surface` | `#FFFFFF` | `#1C1C1E` | `#141414` | Primary card surface (contrast against `canvas`) |
| `surfaceSubtle` | `#F2F2F7` | `#2C2C2E` | `#1E1E20` | Icon tiles, input fills, progress tracks |
| `surfacePressed` | `#E5E5EA` | `#3A3A3C` | `#28282B` | Pressed/disabled fill |
| `border` | transparent | `#14FFFFFF` | `#1AFFFFFF` | Hairline card border (light uses contrast only) |
| `divider` | `#14000000` | `#14FFFFFF` | `#1AFFFFFF` | Subtle inset row divider inside cards |
| `brand` (default) | `#A30B19` | `#E03140` | `#E03140` | TechRed primary brand accent |
| `brandSoft` | 9% `brand` | 14% `brand` | 14% `brand` | Active pill & badge soft tint |
| `onBrand` | `#FFFFFF` | `#FFFFFF` | `#FFFFFF` | Foreground on `brand` |
| `textPrimary` | `#171717` | `#FAFAFA` | `#FFFFFF` | Primary titles, body copy, key metrics |
| `textSecondary` | `#3A3A3C` | `#D1D1D6` | `#D1D1D6` | Tile labels, secondary body |
| `textMuted` | `#8E8E93` | `#8E8E93` | `#8E8E93` | Dates, rooms, sources, metadata |
| `infoBlue` | `#007AFF` | `#0A84FF` | `#0A84FF` | Non-urgent deadlines, secondary course bars |
| `successGreen` | `#30D158` | `#30D158` | `#30D158` | Online status, custom events, completed state |
| `warningAmber` | `#D97706` | `#F59E0B` | `#F59E0B` | Upcoming deadline warning (24–72 h) |
| `dangerRed` | `#A30B19` | `#FF453A` | `#FF453A` | Urgent deadline (<24 h), destructive/error states |

### Accent Preference Rule

- **Default on every platform (including iOS)**: `AppColorScheme.techRed`.
- **Optional `AppColorScheme.system`**: Android uses Material You dynamic accent; iOS uses System Blue (`#007AFF` / `#0A84FF`).
- Switching accent **only** overrides `brand`, `brandSoft`, and `onBrand`. Neutral surfaces (`canvas`, `surface`, `surfaceSubtle`, `border`, `text*`) stay completely neutral and are never tinted by Material 3 seed generation.

## 4. Typography & Iconography

- **Typography (`lib/theme/tp_typography.dart`)**: Uses the platform primary font with TechPie's shared CJK `fontFamilyFallback`. Numeric counters, countdowns, balances, and times always apply `FontFeature.tabularFigures()`.
- **Icons (`lib/theme/tp_icons.dart`)**:
  - Content UI uses `TpIcons` backed by pure-Dart `flutter_lucide` (thin-stroke, `@staticIconProvider` for release tree-shaking, zero native plugins for OHOS safety).
  - iOS native navigation bars and tab bars retain SF Symbols via `IosNativeNavigationBar` / `IosNativeTabBar`.

## 5. Campus Card Bridge

`lib/features/campus_card/presentation/theme/colors.dart` (`GpColors.fromTheme`) automatically derives its semantic surface, text, border, and accent colors from `TpColors` whenever `TpColors` is attached to the host `ThemeData`, while preserving campus-card-specific QR contrast tokens (`qrForeground`, `qrBackground`, `cardMat`, `textOnCard`). Do not duplicate surface workarounds inside `campus_card`.

## 6. Guardrails & Enforcement

`test/architecture/design_system_guard_test.dart` enforces these rules automatically on every PR:

- Pages listed in `migratedDesignSystemPages` are locked against raw `Color(0x...)`, `Card.outlined`, `Card.filled`, direct `isIos()` / `usesIosLiquidGlass()` style branches, and non-token `BorderRadius.circular(...)` magic numbers.
- Every PR that migrates a page adds that file to `migratedDesignSystemPages` until the full repository switches to opt-out enforcement.
