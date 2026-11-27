# TechPie Design System

This document is the single visual source of truth for **TechPie-flutter** across iOS, Android, HarmonyOS NEXT (OHOS), macOS, Windows, and Linux.

## 1. Core Architectural Rule

**Unified content language; platform-native shell & system controls.**

- **Content layer (`lib/pages/`, `lib/widgets/design_system/`)**: 100% unified across every platform. All colors, surfaces, radii, typography, icons, cards, badges, skeletons, empty/error state cards, and progress rows come from `lib/theme/` and `lib/widgets/design_system/`. Pages must **not** branch on `isIos()` / `usesIosLiquidGlass()` / `TargetPlatform` to alter visual styling, and must **not** use raw `Color(0x...)`, bare `Card(` / `Card.outlined` / `Card.filled`, bare `AppBar(`, Material `Icons.*`, or raw `showSnackBar(`.
- **Shell & system layer (`lib/widgets/app_shell/`, `lib/widgets/adaptive_*.dart`, `lib/widgets/ios/`, `android/`, `macos/`)**: Owns platform-native chrome and interactions — iOS Liquid Glass `IosNativeTabBar` / `IosNativeNavigationBar` + SF Symbols + `RefreshIndicator.adaptive` + haptics, Android/OHOS floating glass `TgBottomNavBar`, Android Edge-to-Edge transparent system bars + Predictive Back (`PredictiveBackPageTransitionsBuilder` + `enableOnBackInvokedCallback`), Desktop `DesktopShell` sidebar + compact workbench density, and native system dialogs/pickers/switches.

## 2. Design Tokens & Dual Density (`lib/theme/tp_tokens.dart`, `lib/theme/tp_density.dart`)

### Brand Icon

The [brand tokens](brand-icon/brand-icon.tokens.json) preserve the in-app mark proportions and record the Apple app icon proposal. The [P artwork](brand-icon/01-TechPie-P.svg) is a single foreground layer for Icon Composer. Its nominal height is 672 px on a 1024 px canvas, close to the existing icon's proportions and large enough to retain the triangular counter at small sizes. The vertical gradient is centered on TechRed. The system supplies the outer mask and highlights. The Apple app icon proposal was previewed on the official template and still needs an Icon Composer render.

### Spacing (4 dp grid) & Density Presets

- **Mobile (`TpDensity.comfortable`)**: Touch-first sizing (`16 / 14` card padding, `12` row vertical padding, `48` min row height, `20` icon size).
- **Desktop (`TpDensity.compact`)**: Automatically resolved on `macOS` / `Windows` / `Linux` via `context.tpDensity` (`14 / 12` card padding, `9` row vertical padding, `38` min row height, `18` icon size), with `TpDensityScope` for explicit overrides.

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
| `brand` (default) | `#A30B19` | `#E03140` | `#E03140` | TechRed primary brand accent (solid fills, indicators, bars) |
| `brandInk` | `#A30B19` | `#FF6470` | `#FF6470` | WCAG-AA high-contrast brand text & icons on cards/soft pills |
| `brandSoft` | 9% `brand` | 14% `brand` | 14% `brand` | Active pill & badge soft tint |
| `onBrand` | `#FFFFFF` | `#FFFFFF` | `#FFFFFF` | Foreground on `brand` |
| `textPrimary` | `#171717` | `#FAFAFA` | `#FFFFFF` | Primary titles, body copy, key metrics |
| `textSecondary` | `#3A3A3C` | `#D1D1D6` | `#D1D1D6` | Tile labels, secondary body |
| `textMuted` | `#636366` | `#98989D` | `#98989D` | Dates, rooms, sources, metadata (WCAG AA on `surface`) |
| `infoBlue` | `#007AFF` | `#0A84FF` | `#0A84FF` | Non-urgent deadlines, secondary course bars |
| `successGreen` | `#15803D` | `#30D158` | `#30D158` | Online status, custom events, completed state (WCAG AA) |
| `warningAmber` | `#B45309` | `#F59E0B` | `#F59E0B` | Upcoming deadline warning (24–72 h, WCAG AA) |
| `dangerRed` | `#A30B19` | `#FF453A` | `#FF453A` | Urgent deadline (<24 h), destructive/error states |

Derived opaque container helpers (`opaqueBrandContainer`, `opaqueDangerContainer`, `opaqueSuccessContainer`) composite semantic tints onto `surface` so elevated Material 3 controls, selected sidebar items, and banners avoid muddy alpha stacking or transparent-surface contrast regressions.

### Accent Preference Rule

- **Default on every platform (including iOS)**: `AppColorScheme.techRed`.
- **Optional `AppColorScheme.system`**: Android uses Material You dynamic accent; iOS uses System Blue (`#007AFF` / `#0A84FF`).
- Switching accent **only** overrides `brand`, `brandInk`, `brandSoft`, and `onBrand`. Neutral surfaces (`canvas`, `surface`, `surfaceSubtle`, `border`, `text*`) stay completely neutral and are never tinted by Material 3 seed generation.

## 4. Typography & Iconography

- **Typography (`lib/theme/tp_typography.dart`)**: Uses the platform primary font with TechPie's shared CJK `fontFamilyFallback`. Numeric counters, countdowns, balances, and times always apply `FontFeature.tabularFigures()`.
- **Icons (`lib/theme/tp_icons.dart`)**:
  - Content UI uses `TpIcons` backed by pure-Dart `flutter_lucide` (thin-stroke, `@staticIconProvider` for release tree-shaking, zero native plugins for OHOS safety).
  - iOS native navigation bars and tab bars retain SF Symbols via `IosNativeNavigationBar` / `IosNativeTabBar`.

## 5. Campus Card Bridge

`lib/features/campus_card/presentation/theme/colors.dart` (`GpColors.fromTheme`) automatically derives its semantic surface, text, border, and accent colors from `TpColors` whenever `TpColors` is attached to the host `ThemeData`, while preserving campus-card-specific QR contrast tokens (`qrForeground`, `qrBackground`, `cardMat`, `textOnCard`). Do not duplicate surface workarounds inside `campus_card`.

## 6. Guardrails & Enforcement

`test/architecture/design_system_guard_test.dart` enforces these rules automatically in **repository-wide default-on (opt-out) mode** on every PR:

- **Zero-tolerance rules** across every non-exempt `.dart` file in `lib/pages/` and `lib/widgets/gym/`:
  - Raw `Color(0x...)` literals (`context.tpColors` required)
  - `Card.outlined` / `Card.filled` (`TpCard` required)
  - Direct `isIos()` / `usesIosLiquidGlass()` / `usesLegacyIosChrome()` style branches inside pages
  - Non-token `BorderRadius.circular(...)` magic numbers (`TpTokens.radius*` required)
- **Ratcheted transition rules** (zero tolerance for all newly added or migrated pages; pre-existing pages tracked strictly in `legacyMaterialTransitionPages` with an anti-stale check):
  - Bare `Card(` (`TpCard` required)
  - Bare `AppBar(` (`AdaptiveNavigationScaffold.adaptiveBar` required)
  - Material `Icons.*` (`TpIcons.*` required)
  - Raw `showSnackBar(` (`showAdaptiveFeedback` required)
- **Loading & state primitives**: Prefer `TpSkeleton` / `TpSkeletonList` (respects `MediaQuery.disableAnimationsOf`) for initial loading and `TpStateCard` (`.empty`, `.error`, `.prerequisite`) for empty/error/unbound states; use `PageRefreshIndicator` (`RefreshIndicator.adaptive` on mobile) for pull-to-refresh.
- Only narrowly scoped exemptions listed in `designSystemExemptPages` are skipped: WebView/SSO bridges, the immersive video player (`elrc_player_page.dart`), the Campus Card dedicated feature host (`campus_card_page.dart`, bridged via `GpColors.fromTheme`), and developer/debug utilities.
- New product pages added to `lib/pages/` must pass all 8 rules from their very first commit.
