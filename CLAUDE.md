# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

TechPie is a Flutter app providing third-party campus services for ShanghaiTech University. It supports Android, iOS, Linux, macOS, and HarmonyOS NEXT (OHOS). The backend API lives at `techpie.geekpie.club/api` (prod) / `localhost:3000` (dev toggle in settings).

## Two Flutter SDKs

The project requires **two separate Flutter SDK checkpoints** depending on the build target:

- **Upstream Flutter** (`~/dev/flutter`) — for Linux, Android, iOS, macOS, Windows, web builds. The OHOS fork's gen_snapshot crashes on Linux x64 AOT.
- **OHOS Flutter fork** (`~/dev/flutter_flutter`, channel `ohos`) — required for `flutter build hap`. Stock Flutter has no OHOS engine.

The `.envrc` (managed by direnv) points `PATH` at the OHOS fork by default. Build scripts in `scripts/` enforce the correct SDK.

## Build Commands

```bash
# Day-to-day dev (uses whichever SDK is on PATH)
flutter pub get
flutter run              # run on connected device/emulator

# Linux release (forces upstream SDK)
scripts/build-linux.sh

# OHOS HAP release (forces OHOS fork)
scripts/build-ohos.sh           # default: hap
scripts/build-ohos.sh app       # or: app, har, hsp
```

OHOS signing material is injected from env vars (`OHOS_*`) via `ohos/scripts/generate-build-profile.mjs`. Copy `.envrc.example` and fill in your DevEco-encrypted passwords.

## Lint & Test

```bash
flutter analyze          # static analysis (flutter_lints)
flutter test             # run all tests
flutter test test/assignment_service_test.dart   # single test
```

## Architecture

### Service layer (`lib/services/`)

All services are created in `main.dart`, wired together manually (no DI framework), and provided to the widget tree via a single `ServiceProvider` (InheritedWidget). Access with `ServiceProvider.of(context)`.

Key services:
- **AuthService** — primary account ONLY: GeekPie Uni-Auth (Casdoor) SSO login via `UniAuthService`, SSO token refresh, logout cascade. Owns the SSO identity session (`UserSession` with `geekpieToken`/`geekpieRefreshToken`). It deliberately knows nothing about CASTGC/CpDaily — `UserSession` has no `tgc`/`cookies`/`sessionToken`/`tenantId` fields.
- **UniAuthService** — Casdoor OAuth: `login()`/`loginSdkOnly()` exchange an authorization code for an `SsoTokens` bundle (access + refresh + expiry); `refresh()` rotates them.
- **ScheduleService** — semester list, course table, term-begin date; CpDaily cookies from the eGate binding (`ThirdPartyAuthService.egateCookies()`); auto-retries with `renewEgateBinding()` on 401
- **AssignmentService** — aggregates deadlines from Blackboard + exam table (both via the eGate binding's CpDaily session), Gradescope, and Hydro (third-party tokens); merges per-platform results so a single platform failure doesn't wipe others
- **ThirdPartyAuthService** — bind/unbind/auto-renew for Gradescope, Hydro, **and eGate**. The eGate binding (`ThirdPartyPlatform.egate`) is the SINGLE source of CASTGC / CpDaily session in the app: `hasEgateBinding`, `egateBinding`, `egateCookies()` (always appends `CASTGC=<tgc>`), `egateStudentId`, `renewEgateBinding()` (renews via `/api/auth/renew` and persists back). Every campus-system feature (schedule, blackboard, exam, oa-gym, ecourse/student-leave webviews) reads its CpDaily session through these accessors, never from `AuthService.session`.
- **StorageService** — wraps `FlutterSecureStorage` (credentials) + `SharedPreferences` (caches, settings). **Important:** imports `flutter_secure_storage_ohos` (a hard fork), NOT the upstream `flutter_secure_storage` facade
- **ThemeService** — Material dynamic color, theme mode persistence

### Auth model boundary (important)

There are two distinct account tiers — do not cross them:
- **Primary account** = GeekPie SSO (Casdoor). Determines `auth.isLoggedIn` and user identity (userName). Produces NO CASTGC.
- **eGate binding** = a third-party account that holds the campus CpDaily session (CASTGC). Required by every campus-system feature. A user can be SSO-logged-in but have no eGate binding — such a user is "logged in" but cannot use schedule/blackboard/exam/gym/webview features until they bind eGate.

CASTGC must never be read off `AuthService.session`. Always go through `ThirdPartyAuthService.egateCookies()` / `egateStudentId` / `renewEgateBinding()`.

### Boot sequence (`main.dart`)

1. Synchronous: hydrate all caches from local storage (critical path — no network).
2. `runApp` immediately with cached data.
3. Unawaited background: renew tokens (main + third-party in parallel), then fan out schedule/assignment fetches.

### Navigation (`lib/widgets/app_shell/`)

Responsive shell: `DesktopShell` (sidebar, >=600px; collapsible >=960px) or `MobileShell` (bottom nav). Page transitions use `FadeThroughTransition`.

### Platform adaptation (`lib/utils/platform.dart`)

iOS Liquid Glass (iOS 26+) vs legacy iOS chrome is detected at boot via a MethodChannel (`techpie/platform`). Helper functions `isIos()`, `usesIosLiquidGlass()`, `usesLegacyIosChrome()` gate UI branches throughout the app.

### Features / WebView (`lib/models/feature.dart`)

Campus web services (ecourse, student leave, etc.) are opened in an in-app WebView with injected CASTGC cookies sourced from the eGate binding (`ThirdPartyAuthService.egateCookies()`). The `Feature` model declares `FeatureMode.native` vs `FeatureMode.webviewWithCookie`.

## OHOS-Specific Gotchas

- Many upstream pub packages lack OHOS platform implementations. The `dependency_overrides` in `pubspec.yaml` point to OpenHarmony-SIG forks that add OHOS MethodChannel bindings. Don't remove these overrides without testing on OHOS.
- Dart/Flutter SDK is pinned to an older version for HarmonyOS compatibility (see README warning).
- `flutter_secure_storage_ohos` is NOT a federated plugin — it's a full fork with its own `FlutterSecureStorage` class. Importing the upstream package will crash on OHOS.

## API Pattern

All services talk to a Node.js backend. Pattern: POST JSON with auth tokens, check `{success: true}`, handle 401 with token renewal + retry. Base URL is toggled by a `useLocalhost` setting in `StorageService`.
