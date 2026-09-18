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

# Release artifacts are built by CI: release.yml calls one workflow per platform
# (android-release.yml, linux-release.yml, windows-release.yml, ohos-release.yml,
# dispatch-ios-release.yml). The one you can build locally is the OHOS hap:
scripts/build-unsigned-hap.sh
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
- **UpdateService** — the settings page's version tile calls GitHub's `releases/latest` and offers a newer release with its changelog; the update action opens the release page. `utils/product_version.dart` owns the comparison (a candidate ranks below the release it leads to, and `+B` is not part of a version). Deliberately independent of our backend, so it still answers when the API does not, and it needs no account
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

## Releasing

`pubspec.yaml` is the single version source: `version: X.Y.Z[-rc.N]+B`. Nothing
else declares a version — the OHOS `AppScope/app.json5` is generated from it at
build time, Android/iOS/Windows/Linux derive their stamps from it, and a release
tag must agree with it or the release workflow refuses to publish.
`scripts/release-plan.mjs` implements the policy below and runs standalone
(`node scripts/release-plan.mjs --ref master`) to show what a dispatch would
release — the same thing the workflow prints into its run summary before it
tags anything.

### Hard rules

Not preferences — the pipeline refuses work that breaks them, and breaking one by
hand corrupts the record the next release is computed from:

1. **`pubspec.yaml` is the only version source.** Never declare a version, a build
   number or an `-rc.N` anywhere else (no hand-made tags, no `--build-name` that
   disagrees, no store-side override).
2. **A build number is never reused and never reset** — not at a major bump, not
   per version line, not per year. Play requires the versionCode to increase for
   the application as a whole and App Store Connect requires CFBundleVersion to
   increase inside a train, so the counter only ever goes up.
3. **Never create or delete a release tag by hand.** Tags are the ledger the plan
   reads to decide what comes next; a hand-made tag is either refused by the
   platform workflows or, worse, taken as history. Deleting a release *object* is
   fine; deleting its tag is not.
4. **A release always ships notes.** `CHANGELOG.md` must carry a non-empty
   `## [X.Y.Z]` section before anything is tagged: the tag annotation is built
   from it and the release page from the annotation.
5. **Releases come from `master` (candidates) or `release/X.Y.Z` (stable), and
   nothing else.** A push to a release branch publishes only when it moves the
   `version:` line.
6. **Merging the release PR is the release.** Do not push a version-line change
   onto a release branch unless that is exactly what you mean.
7. **Every published artifact is named by one grammar** —
   `TechPie-<version>-<platform>-<arch>[-unsigned].<ext>`, where `<version>` is
   the release name (`1.0.1`, `1.0.1-rc.2`) and never the build number, and the
   release *title* is `v<version>`. See [Artifact names](#artifact-names).

### The numbers

- `X.Y.Z` is the product version, and the only number a user ever sees.
  **MAJOR** — a change users cannot ride through on their own: an account must be
  re-bound or re-authenticated, the cloud-sync envelope breaks, a platform floor
  moves up. **MINOR** — a new user-visible capability: a campus service, a
  screen, a platform. **PATCH** — fixes and maintenance that add nothing a user
  can do. The 0.x line is over: `1.0.0` is the first version that promises this.
- `+B` is the build number: one counter for every platform, strictly greater than
  every build ever shipped. Play requires the versionCode to increase across the
  application and App Store Connect requires CFBundleVersion to increase inside a
  version train, so this single counter satisfies both. It is never reused and
  never reset at a major bump.
- `-rc.N` is derived, never invented: `N` is **which candidate of this version
  line this is**, counted from the tags, so `1.0.0+4` on `master` releases as
  `1.0.0-rc.2` when one `1.0.0` candidate already shipped. It is independent of
  `+B`: the build number is a global counter, the ordinal is per version line. A
  suffix written in pubspec is accepted only when it says exactly what the plan
  derived (`1.0.0-rc.2+4`); anything else is refused, so pubspec and the release
  name cannot disagree.
- The suffix never reaches a platform version stamp: iOS rejects a
  `CFBundleShortVersionString` like `1.0.0-rc.4`, and Android is kept identical
  so that one release has one version everywhere. Stores and the in-app settings
  tile show `X.Y.Z`; `+B` tells two builds of it apart.
- `release-plan.mjs` enforces all of the above before anything is tagged: a build
  number that is not above the highest released one (the refusal names the number
  to write), a leading zero anywhere in the version, a number above Play's
  2100000000 ceiling, an `-rc.N` that disagrees with the derived ordinal, and a
  `version:` line with anything after the number all stop the run.

### What publishes a release

Two entries, both deliberate:

| Entry | What decides | Channel | Release name |
| --- | --- | --- | --- |
| merging the release PR (`prepare-release.yml` → PR → merge) | that merge's push, and only when it *moves* `version:` | stable | `X.Y.Z` |
| `gh workflow run release.yml --ref master` | the dispatch itself | pre-release | `X.Y.Z-rc.N` |

That gate is the difference. A push to `release/**` publishes only when it moves
the `version:` line: merging the release PR does, cutting the release branch does
not, and neither does a later fix pushed to a frozen line. A base that is missing,
all zeros or unreadable also answers "did not move" — the safe way round, since a
release that did not happen can be asked for again and an unintended one cannot be
taken back.

A ref that is neither `master` nor `release/X.Y.Z` is refused, so a mistyped
branch cannot publish from an arbitrary commit. Releasing the same commit twice is
a no-op (the tags already point there); a build number that shipped before is
refused.

`release.yml` only plans and tags; the platform builds are reusable workflows it
calls, because a tag pushed with `GITHUB_TOKEN` does not trigger tag-based
workflows. Nothing is tagged until the commit being released passes
`flutter analyze` and `flutter test` inside that run (`analyze.yml` passing on
the same commit proves nothing — GitHub does not order workflow runs).

A release branch declares exactly the version it freezes: `release/1.0.1` must
carry `1.0.1+B`, with no suffix, and a mismatch is refused rather than guessed.
It is therefore one version train — a higher `+B` on the same branch republishes
`1.0.1` as a new build (the path for a store resubmission), and the next patch
line is a new branch (cut from the old one, so the fixes travel with it). A build
number is never reused, so a stable release lands one above the last candidate
that actually shipped.

### Choosing the channel

| You want | Do | CI publishes |
| --- | --- | --- |
| nothing yet — docs, CI, refactors | leave `version:` alone | nothing |
| a candidate testers can install | bump `+B` on `master`, write the notes, dispatch on `master` | `X.Y.Z-rc.N` |
| another candidate | bump `+B` again, dispatch again | `X.Y.Z-rc.(N+1)` |
| the version users get | `prepare-release.yml` on `master`, review the PR, merge it | `X.Y.Z` |
| a rebuild of the same stable version | `prepare-release.yml` on the release branch, merge | `X.Y.Z`, new build |
| the next patch line | `prepare-release.yml` on the old release branch, with the new `X.Y.Z'` | `X.Y.Z'` |

Tags are never part of the decision and never made by hand: every release —
candidates included — is planned, verified (`flutter analyze`, `flutter test`),
tagged `v<name>+B` / `ios-vX.Y.Z+B`, built, and published by CI in that order.
A candidate is an rc only because it is a build number of a version line that has
not been frozen yet; freezing it is what makes the same numbers a release.

```bash
# a candidate, on master. The plan names it (candidate N of this version line),
# so the build number is the only number you write here.
$EDITOR pubspec.yaml          # version: 1.0.0+5
$EDITOR CHANGELOG.md          # what changed — a release without it is refused
git commit -m "chore(release): 1.0.0 candidate"
git push origin master
gh workflow run release.yml --repo HeZeBang/TechPie-flutter --ref master

# the stable release: CI cuts the branch and proposes the bump, you merge it
gh workflow run prepare-release.yml --repo HeZeBang/TechPie-flutter \
  --ref master -f version=1.0.0
#  → cuts release/1.0.0 at master, opens release-prep/1.0.0 → release/1.0.0
#  → merging that PR is the release: that push moves `version:`
```

The release PR carries the version line, not the notes: the notes are reviewed
where they live, in `CHANGELOG.md`, and `prepare-release.yml` refuses to open a
pull request for a version with no (or an empty) section. Re-running it rewrites
the same branches and updates the same PR, so the loop for "the notes are wrong"
is: fix `CHANGELOG.md` on master, run it again.

When the line's version already equals what is being released — releasing a line
whose candidates were skipped — there is nothing to bump: the branch is still cut
and the run tells you to publish it with `gh workflow run release.yml --ref
release/X.Y.Z`.

Preview a dispatch with `-f dry_run=true` (it still runs `flutter analyze` and
`flutter test`, but tags and builds nothing), and re-run a single platform for an
existing tag with `gh workflow run android-release.yml -f tag=v1.0.0+5`
(`ohos-release.yml` takes `release_tag` instead of `tag`).

### Release notes

`CHANGELOG.md` is where a release says what changed, and it is a gate rather than
a nicety: `release-plan.mjs` looks up `## [<product version>]` before anything is
tagged and refuses the release when that section is missing or empty.

- Sections are keyed by **product version**, not by release name: every candidate
  of a line and the stable release that ends it share one section, because the rc
  ordinal is derived at release time and nobody could write its heading in
  advance.
- The lookup is exact. Taking "the newest section" would publish the wrong notes
  the first time the file is out of order, so a missing section is a refusal —
  which is also why `## [Unreleased]` does not work: notes belong under the version
  they ship as.
- The tag job copies the section into the tag annotation's body (its subject stays
  `TechPie X.Y.Z[-rc.N]`), and the GitHub release page is built from that
  annotation. The notes a user reads are therefore the ones that were reviewed,
  and the tag keeps them even if the release page is edited later.

### When it does not happen

- **Refused at the plan** (missing notes, a build number that already shipped, a
  branch that does not match its version): nothing is tagged and nothing is built.
  Fix the cause first — and for a merge that already landed, run
  `gh workflow run release.yml --ref release/X.Y.Z` afterwards, because the fixing
  push moves no version line and would publish nothing on its own.
- **A platform build was cancelled or failed after the tag was made**: the tag
  stays (the ledger, and the build number is spent). Re-run that job with
  `gh run rerun <run-id> --failed` — but note that this re-runs only the failed or
  cancelled jobs, so the `publish` job, which was *skipped* because of them, does
  not come back with them. Publish by hand afterwards, with the same two flags the
  job computes:
  `gh release edit <tag> --draft=false --prerelease=<true|false> --latest=<true|false>`
  (a candidate is `prerelease=true latest=false`). Re-dispatching `release.yml`
  instead is a no-op: the plan sees the tags already at that commit and skips.
  **A re-run rebuilds that tag's commit, so it can only recover a transient
  failure.** A fix to a workflow — a missing build dependency, a wrong apt
  package — cannot reach a tag that is already cut: bump `+B`, fix, and release
  again. That is what 1.0.1-rc.2 cost: its Linux build died on a missing
  `libwebkit2gtk-4.1-dev`, its Windows job on a shared concurrency group, and its
  OHOS attach on an HTTP 500 from the upload service, all three of which are
  fixed for the next candidate rather than for it.
- **A published release is wrong**: supersede it with a higher build number.
  Deleting the release object is fine; deleting its tag is not, because the next
  release would then be free to reuse the number.
- **A dispatch that asks for nothing** (`skip=true`: the tags already point at that
  commit) is a no-op by design.

### Triggers

`release.yml` has exactly two entries: a push to `release/**` (the merged release
PR) and `workflow_dispatch` (candidates, and anything that has to be asked for
again). `prepare-release.yml` is dispatch-only and only ever opens a pull request
— it builds and publishes nothing. `analyze.yml` stays the push/PR gate that keeps
master green; it never publishes.

Every other workflow is called, never tag-triggered: `android-release.yml`,
`dispatch-ios-release.yml` and `ohos-release.yml` expose `workflow_call` (the
release run drives them) and `workflow_dispatch` (replay one platform for an
existing tag). Two reasons. A tag pushed with `GITHUB_TOKEN` cannot start a
workflow run at all, which is why `release.yml` calls them instead of waiting for
the tags it just pushed. And a tag pushed by hand is exactly what this policy
forbids — it must not be able to start a release.

The release object is opened as a **draft before any platform builds**, and
`publish` flips it public last. That ordering is what lets Android, iOS and OHOS
build in parallel while each attaches what it produced, and it is GitHub's own
recommendation once immutable releases are enabled (a published release refuses
new assets). It also keeps a half-assembled release from notifying watchers. A
release is published in whatever repository runs the workflow
(`HeZeBang/TechPie-flutter` today), so a run in a fork publishes there.

Repository settings that back this: `android-release` is declared by the signing
job but carries **no protection rules, deliberately** — every release is already
a human act (a dispatch, or merging the release PR), so an approval rule would add
a click without adding a check, and the deployment log is what records who did
what. Add one if the project grows maintainers who should sign off:

```bash
printf '{"reviewers": [{"type": "User", "id": <id>}], "prevent_self_review": false}' | \
  gh api -X PUT repos/HeZeBang/TechPie-flutter/environments/android-release --input -
```

(An empty `reviewers` array clears it again. It has to be sent as JSON: a
`-F reviewers=[]` flag is silently ignored.)

The signing material is **repository-scoped** today, so the environment restricts
nothing yet — any workflow in this repository, including one on a collaborator's
pull request, can read `ANDROID_KEYSTORE_BASE64`. Moving the four `ANDROID_*`
secrets into it (`gh secret set ANDROID_KEYSTORE_BASE64 --env android-release`,
once each, values in hand) narrows that to the job that declares the environment,
which is the reason the declaration is there at all.

Immutable releases are still off: the draft order above is what makes them safe,
so switch them on once one release has shipped through it.

One thing to know before enabling required status checks on `master` or
`release/**`: `prepare-release.yml` opens its pull request with `GITHUB_TOKEN`,
and a pull request opened with that token starts no `pull_request` runs (the same
recursion rule that stops CI-pushed tags from triggering workflows). Today that
costs nothing — neither branch is protected and no checks are required — but the
moment a check is required, the release PR could never go green. The fix is to
open it with the GitHub App the iOS dispatch already uses
(`RELEASE_APP_CLIENT_ID` / `RELEASE_APP_PRIVATE_KEY`), granted `contents: write`
and `pull_requests: write` on this repository.

### Tags

CI creates two annotated tags per release, both carrying the changelog:

| Tag | Names | Consumed by |
| --- | --- | --- |
| `v1.0.0-rc.2+5`, `v1.0.0+6` | the release | the Android build, the GitHub release (APKs, then the OHOS hap) |
| `ios-v1.0.0+5` | the same release in iOS's shape | the dispatch to `CNDY1390/TechPie-release` |

The release tag has no platform prefix because its artifacts are the Android APKs
and the OHOS hap — iOS is signed and shipped to TestFlight by the private
workflow — and it keeps the release name, so the tag alone says which candidate
shipped. The iOS tag keeps its prefix because that private workflow validates
exactly `ios-vX.Y.Z+B`, and it cannot carry the suffix because
`CFBundleShortVersionString` forbids it — so that tag alone does not say whether
the build was a candidate; the release tag does. Do not create either tag by
hand: a tag that disagrees with pubspec is refused, and the plan reads tag
history (the older `android-v…` tags included) to keep `+B` above every build
already shipped.

The platform workflows check the tag once more before building: it must name a
commit reachable from `master` or a `release/*` branch. Master alone is not
enough — a stable release's version bump lives only on its release branch, and a
commit on neither ref must not be publishable.

The `ios-vX.Y.Z+B` tag is transitional, and the plan is to end up with the single
`v…` tag. Nothing here can finish that: the private signing workflow validates
`ios-vX.Y.Z+B` today, so the second tag stays until that validator accepts
`vX.Y.Z+B`. The switchover is then small — the `ios` job passes
`needs.plan.outputs.tag` instead of `tag_ios`, `tag_ios` disappears from the
plan, and `highestIosCode` goes with it, because the global build number already
satisfies App Store Connect's per-train rule.

### Artifact names

One grammar for everything a release publishes:

```text
TechPie-<version>-<platform>-<arch>[-unsigned].<ext>

<version>  the release name — what the title says after its `v`. A stable
           release is `1.0.1`, a candidate is `1.0.1-rc.2`, so two candidates of
           one version ship files a downloader can tell apart. The build number
           is in no file name: `+B` is global history, not a version, and the tag
           is where it lives.
platform   android | linux | ohos | ios | macos | windows
arch       universal | x86-64 | arm-64 | arm32v7 | arm64v8
           Android and OHOS use ABI tokens (arm64-v8a -> arm64v8,
           armeabi-v7a -> arm32v7); desktop 64-bit ARM is arm-64; universal is
           one file for every architecture of that platform.
-unsigned  only when nothing signed it: the OHOS hap and App Pack we build here,
           and any iOS build the private signing repo hands back unsigned.
ext        android   apk | aab
           linux     AppImage | deb | rpm | tar.gz | zip
           ohos      hap | hsp | app
           ios       ipa | app
           macos     dmg | app | tar.gz | zip
           windows   exe | msi | zip
```

The shape, with this line's release name:

`TechPie-<version>-<platform>-<arch>[-unsigned].<ext>` names today are
`TechPie-1.0.1-rc.2-android-arm64v8.apk`, `-android-arm32v7.apk`,
`-android-universal.apk`, `-ohos-arm64v8-unsigned.hap` (+ `.sha256`),
`-linux-x86-64.tar.gz` and `-windows-x86-64.zip`; `<version>` is whatever the tag
says, so the next attempt at this line names its files after its own release name.

**Every attempt consumes an `rc.N`.** The ordinal is the highest `-rc.N` among the
tags of that base plus one (`release-plan.mjs` → `highestRcOrdinal`), so a
candidate that dies before publishing still advances it: 1.0.1-rc.2's failure left
the next candidate at 1.0.1-rc.3. Retrying means bump `+B`, push, dispatch — never
write `-rc.N` into pubspec by hand, because the plan refuses a declared suffix that
disagrees with the ordinal it derived. A *local* `release-plan.mjs` run needs
`git fetch --tags` first: with stale tags it answers about a different candidate
than CI will.
macOS and iOS attach nothing to a release — iOS goes to TestFlight through the
private signing repo. Adding a platform means adding a row above, not inventing a
name.

The universal APK's versionCode is the build number itself, while the splits carry
ABI×1000 + B (arm32 1000+B, arm64 2000+B, measured on the shipped APKs). Replacing
a split install with the universal one is therefore a downgrade Android refuses —
uninstall first. It is also the only Android artifact that covers x86_64, which is
what it is for.

Where each name comes from, so workflow and script cannot drift: the tag-to-name
rule lives in exactly one place, `scripts/release-name.sh`, which the Android,
Linux and Windows jobs call and `scripts/build-unsigned-hap.sh` falls back to —
that script reads `RELEASE_NAME`, then the release tag it is checked out at, then
pubspec. One string, the same one the release is titled with.

The release **title** is that release name with a `v` in front — `v1.0.1-rc.2`,
`v1.0.1` — taken from the tag annotation's subject, so the title, the annotation's
first line and what `gh release view` reports are one string. The **tags** keep
the build number (`v1.0.1-rc.2+5`): two builds of one version have to stay
distinguishable in git, and the file names deliberately do not try to.

### Operating the pipeline

- CI signs and publishes every platform's artifacts and stops there: **uploading
  to Play, AppGallery and the App Store is manual**, from those artifacts (for
  AppGallery, that is the dispatch below). Android
  gets three APKs (arm64 and arm32 splits plus a universal one), Linux a `tar.gz`
  of the bundle, Windows a `zip` of the release directory, OHOS the unsigned hap.
  The `publish` job waits for all of them and is what writes the SHA-256 block —
  once, over every asset, since a platform job only knows its own files. The
  Android signing material lives in the `android-release` environment; the iOS
  dispatch needs `RELEASE_APP_*` and the signing repo.
- **One concurrency group per platform.** Group names are repository-wide and a
  group holds only one *pending* entry, so platform workflows that share a group
  cancel each other's queued jobs: 1.0.1-rc.2's Windows job was cancelled one
  second after it started, before any step ran, because Linux and Android were
  queued in the same group. Hence `android-` / `linux-` / `windows-` / `ohos-` /
  `ios-` prefixes, and `cancel-in-progress: false` — which protects a *running*
  job, not a pending one.
- The `publish` job owns the "Latest" label: a candidate never takes it, and
  neither does a maintenance line published after a newer one. A release is
  labelled latest only when it is stable and its `X.Y.Z` is not older than the
  release GitHub currently calls latest.
- **F-Droid**, should we ever ship there: F-Droid builds from the tagged commit
  with its own `flutter build apk --release` and takes the version from
  `pubspec.yaml`, so its metadata wants
  `UpdateCheckMode: Tags v[0-9.]*\+[0-9]+$` — plain `Tags` would read a
  candidate's build number as the current version — and no `subdir:` (our
  pubspec.yaml is at the root). Its rebuild is unsplit, so its versionCode is
  `+B` while ours are `ABI×1000 + B` (arm32 `1000+B`, arm64 `2000+B`, measured on
  the shipped APKs), and the two channels sign with different keys anyway, so a
  user cannot move between them without reinstalling.
- There is no freeze switch: a release waits for its dispatch, so merging a
  version bump publishes nothing on its own.
- **OHOS**: each release also publishes two unsigned packages — the hap you install
  on a device (`TechPie-<release name>-ohos-arm64v8-unsigned.hap`) and the App Pack
  AppGallery publishes (`…-ohos-arm64v8-unsigned.app`, which holds that hap plus
  `pack.info`) — each with its sha256. They are built by
  `scripts/build-unsigned-hap.sh` and `scripts/build-ohos-app.sh` with
  `OHOS_UNSIGNED=1`: the generator writes a profile with no signing material, so
  hvigor packs `-unsigned` artifacts while flutter exits non-zero looking for the
  signed ones, which is why both scripts judge the build by the artifact rather
  than by its exit code. Signing happens on the device owner's machine, never in
  CI — so an AppGallery upload is a maintainer step: sign the pack, then upload it.
  The toolchain reaches CI as a container image, not as a self-hosted runner:
  `ci/Dockerfile.ohos-buildenv` bakes the OHOS Flutter fork and the DevEco
  command-line tools — neither can be installed on a hosted runner, because the
  HarmonyOS SDK sits behind a Huawei developer login and the fork is ~2 GB of git
  history — `ci/publish-buildenv.sh` stages what the developer machine has and
  pushes it to a private GHCR package, and `ohos-release.yml` pulls it with
  `container:`. The job therefore runs on a stock `ubuntu-24.04`, and there is no
  `OHOS_CI_ENABLED` / `OHOS_CI_RUNNER` to configure. Upgrading either toolchain
  means re-running `ci/publish-buildenv.sh` and copying the tag it prints into the
  workflow's `container.image`; the workflow pins that tag, never `latest`, so a
  release always names the toolchain it was built and tested against.
  Two settings on the GHCR package are what let the job pull it, and neither is
  implied by the other: **Connect repository** (links the package to this repo) and,
  under **Manage Actions access**, **Add repository** — the documented way to let a
  workflow's `GITHUB_TOKEN` read it. Linking a package that was already published
  does *not* make it inherit the repository's permissions, so the second step is not
  optional. Symptom when either is missing: the job dies in `Initialize containers`
  with `docker pull … Error response from daemon: denied`, before any step of ours
  runs.
  Note: `flutter build hap` reports "Hvigor build failed to produce an hap file"
  for such a build — it looks for the `-signed.hap` the signing config would
  have produced. The script judges the build by the artifact instead.
  Also note: the OHOS toolchain rewrites `AppScope/app.json5`'s version fields
  itself and hvigor flattens a pre-release name, so a declared `1.0.0-rc.4+5`
  packs as versionName `1.0.0.4` with versionCode 5. Android and iOS strip the
  suffix instead (iOS forbids it in `CFBundleShortVersionString`), so `+B` is
  what identifies a build on every platform.

### Publishing to AppGallery

A release stops at GitHub, AppGallery included, and what the store needs is not
there yet: an AppGallery release is a **`.app` App Pack whose signature Huawei
validates**, and every pack we publish is unsigned. So publishing is its own
dispatch, and the run that performs it is the only one that ever sees the signing
material:

```bash
gh workflow run appgallery-release.yml --ref master \
  -f tag=v1.0.1+11 -f submit=false        # ... -f submit=true to also submit
```

`.github/workflows/appgallery-release.yml` builds the pack **signed** from the
certificate, profile and keystore in the `appgallery-release` environment (the
release's own unsigned `dist/*.app` stays the public artifact), then hands it to
`scripts/appgallery-publish.mjs`, which does the whole flow: OAuth token, version
check, presigned upload to OBS, package registration, and — only when asked —
submission for review. The same script works from a developer machine with the
three `AGC_*` credentials in the environment.

- **Upload is repeatable; submitting is the publishing act.** An upload registers a
  software package in the app's draft. Submitting puts that version in front of
  Huawei's reviewers, so it is a dispatch input defaulting to `false`, and the
  script additionally requires `AGC_CONFIRM_SUBMIT=YES` (which the workflow derives
  from that input) — a second lock, so a later change that adds `--submit` to a
  step still cannot publish anything by itself.
- **The version guard.** Before uploading, the script reads AGC's app info and
  refuses a pack whose `+B` is not above the shelf — the never-reuse-a-build-number
  rule the release plan enforces locally, which AGC enforces by rejecting the
  submission. `--dry-run` stops right after that check: it proves the credentials
  and the version, and changes nothing.
- **The API client must be team-level, and must actually be an API client.** In
  AGC → 用户与访问 → API 密钥 → Connect API the client's 项目 has to be `N/A`, with
  at least the APP管理员 role; a project-scoped client answers every publishing
  call with `403 client token authorization fail`. A value that is *not* an API
  client's at all — the app's 客户端ID, its App ID, or an `agconnect-services.json`
  `client_id` — fails earlier and more confusingly, at the token call:
  `203886599 the type of clientId not match`. No request shape fixes that one (the
  plain `grant_type` form is correct, and adding a `type` of 0 or 1 changes
  nothing), so the script's error names where the right values live.
- **`.app` goes through `app-package-info`, not `app-file-info`.** The latter takes
  icons and screenshots; it also *accepts* a package upload while leaving 软件包管理
  empty, so the mistake looks like success. And because AGC compiles a pack before
  it can be submitted, `app-submit` answers HTTP 200 with `ret.code=204144719`
  until it finishes — the script polls that code (15 s, 10 attempts) instead of
  reporting a failure.
- **The version published is pubspec's** (`version: X.Y.Z+B`), because that is what
  hvigor stamps into the pack.
- **Not run yet.** The first dispatch needs the environment filled in: the three
  `AGC_*` values, plus `OHOS_CERT_BASE64`, `OHOS_PROFILE_BASE64`,
  `OHOS_STORE_BASE64`, `OHOS_KEY_ALIAS`, `OHOS_STORE_PASSWORD`,
  `OHOS_KEY_PASSWORD` — and optionally the `OHOS_SIGN_ALG` variable, which
  defaults to `SHA256withECDSA`.

## OHOS-Specific Gotchas

- Many upstream pub packages lack OHOS platform implementations. The `dependency_overrides` in `pubspec.yaml` point to OpenHarmony-SIG forks that add OHOS MethodChannel bindings. Don't remove these overrides without testing on OHOS.
- Dart/Flutter SDK is pinned to an older version for HarmonyOS compatibility (see README warning).
- `flutter_secure_storage_ohos` is NOT a federated plugin — it's a full fork with its own `FlutterSecureStorage` class. Importing the upstream package will crash on OHOS.
- The OHOS CI image (`ci/Dockerfile.ohos-buildenv`) drops the SDK's native/C++ toolchain (`native/llvm`, `hms/native/BiSheng`), the previewer's device variant and HMS resource bundle, and the Flutter fork's web SDK to stay inside a hosted runner's disk budget — 9.7 GB of local toolchain becomes 3.3 GB to download / 5.5 GB extracted. Two things that look droppable are not: the fork's 1.9 GB `.git` (`bin/internal/shared.sh` refuses to run without it, and the framework version comes from a git tag) and `openharmony/previewer/common` (the resource compiler dlopens `hms/toolchains/lib/libimage_transcoder_shared.so`, whose RUNPATH points into it; the image build asserts that chain resolves). Adding native C/C++ (`ohos/entry/src/main/cpp/`) means restoring the `native/*` lines there, otherwise the build fails on a missing clang.

## API Pattern

All services talk to a Node.js backend. Pattern: POST JSON with auth tokens, check `{success: true}`, handle 401 with token renewal + retry. Base URL is toggled by a `useLocalhost` setting in `StorageService`.
