# GenAI integration contract and foundation

This feature is based on the user-supplied
`shanghaitech_genai_api_reference.md`, reviewed on 2026-10-19. That document
is a third-party summary, not a verified official API specification. No live
campus request, login, generation, upload, key operation, or billing action was
used to establish this foundation. All fixtures contain synthetic identities
and content. No credential or signing constant from the summary is included.

## Implemented contract

Default base: `https://genai.shanghaitech.edu.cn/htk/`. An injected HTTPS base
can expose the same routes through a future TechPie gateway. HTTP is accepted
only for loopback fixtures. Requests never follow redirects, including profile
requests whose documented path contains a token. No request/response payloads,
URLs, or upstream error text are passed to TechPie's debug logger.

| Operation | Source-derived request | Expected response | Evidence |
| --- | --- | --- | --- |
| Profile verification | `GET user/info/{token}?_t=...`, `X-Access-Token` | Envelope containing `result.userInfo.id` and `username` | Synthetic contract tests only |
| Model discovery | `GET ai/aiModel/list`, `pageNo=1`, `pageSize=999`, `showStatusList=2,3`, `_t` | Envelope containing `result.records[]` with `aiName`, `aiType`, `rootAiType`, optional `payType` | `records` pagination shape is a Jeecg inference; requires upstream verification |
| Streaming text chat | `POST chat/start/chat`, JSON, `X-Access-Token` | `text/event-stream` containing `choices[0].delta` | Synthetic decoder tests and loopback HTTP tests |

An envelope requires `success: true` and integer `code: 0` or `200`.
HTTP/business `401` means authentication is required. Other HTTP/business
failures are rejected; invalid content types/shapes are protocol failures.
Upstream messages are never copied into exception strings.

Chat sends the current prompt as `chatInfo`, prior messages as `messages`, a
caller-owned stable `chatGroupId`, catalog-selected `aiType` and `rootAiType`,
`type: "3"`, `stream: true`, `thinking`, `netGo: false`, and optional
`maxToken`. Excluding the current prompt from `messages` follows the supplied
summary and still needs a verified multi-turn capture. The foundation does
not guess token usage, hard-code a model directory, infer vision support, or
perform a search preflight.

SSE framing follows the [HTML event-stream specification](https://html.spec.whatwg.org/multipage/server-sent-events.html#event-stream-interpretation):
incremental UTF-8, CR/LF/CRLF, multiline data, comments, and blank-line dispatch.
Events/lines are bounded to 256 KiB. The chat adapter emits separate answer and
reasoning deltas. A non-null `finish_reason` or `[DONE]` terminates once. A bare
EOF, including an unterminated last event, is interrupted. Malformed JSON and
explicit error events fail visibly. Streaming requests are never replayed or
automatically reconnected. Stop aborts the client request; server cancellation
and avoided charges are not established.

## Session integration

`TechPieApp` constructs a `GenAiRuntime` and exposes it through
`ServiceProvider.genAiRuntime`. Construction installs listeners only: there is
no startup network request or secure-store read. The runtime requires a primary
GeekPie identity and a bound campus account; the GenAI username must match the
**campus binding's student id**, not the primary account's student id.

The owner scope combines primary user id, campus student id, and binding time.
Renewing a campus token leaves that scope intact; re-binding or switching an
identity changes it. A scope change cancels work, clears displayed partial
output, rejects late results, and queues deletion of the previous credential.
Secure deletion failures are observable as `sessions.lastFailure`.

Credentials use the existing OHOS-aware secure storage under
`techpie.genai.session.v1.<owner hash>`, outside third-party account storage and
cloud sync. Secure operations are serialized so a logout deletion follows an
already-started write. Cached tokens are verified against the profile endpoint
before becoming active; local JWT claims do not establish authentication.

The module supports two explicit connection paths:

- `sessions.connect(GenAiCredential(...))` accepts a token from a trusted login
  callback, verifies its profile and identity, then persists it.
- An injected `GenAiSessionIssuer` can supply a credential from a **verified**
  CAS/gateway exchange. Concurrent consumers share one issuance/verification.

There is deliberately no production issuer, guessed backend route, automatic
password login, or refresh-token grant. Without a valid cached token or explicit
connection, the service requires login. A rejected generation invalidates its
session but is never retried. A stale rejection cannot invalidate a newer login.

`runtime.repository` exposes model discovery and typed streaming events.
`runtime.chat.send(request)` supplies UI-independent phase, answer, reasoning,
failure and finish-reason state. `stop()` preserves partial output; `clear()`
removes it. Interrupted responses are not promoted to completed history. The app-scoped workspace retains the current conversation when the user
returns to TechPie and opens GenAI again. Server history browsing, loading and deletion are now available through the workspace tools.

## Transport and validation

The existing `http` dependency now has a minimum of 1.6.0, matching the locked
version. This makes `AbortableRequest` and Fetch-backed browser streaming an
explicit dependency rather than relying on Dio's buffered XHR browser adapter.
See [package:http documentation](https://github.com/dart-lang/http/tree/master/pkgs/http).
Each request owns a client, a header timeout, an idle timeout, and cancellation;
closing one operation cannot abort another. CORS and proxy buffering on the real
campus/gateway deployment remain unverified. OHOS uses the native Dart transport
but has not been tested on a device for this feature.

Load the repository environment before validation. In a clean managed worktree,
load the configured SDK environment explicitly if `.envrc` is unavailable.

```sh
flutter pub get --enforce-lockfile
flutter test --no-pub test/genai
flutter analyze --no-pub
flutter test --no-pub
```

To exercise real browser Fetch streaming with synthetic loopback data, first run:

```sh
python3 tool/genai_stream_fixture.py --port 18765
```

Then, in another terminal:

```sh
flutter test --no-pub --platform chrome \
  --dart-define=GENAI_TEST_ORIGIN=http://127.0.0.1:18765 \
  test/genai/platform/http_genai_transport_browser_test.dart
```

The server withholds the terminal event until the test observes the first text
delta and explicitly releases it. The second case aborts the open response.
The server listens only on loopback, accepts only a synthetic token, and never
contacts upstream services. Stop it with Ctrl-C after the tests.

Validation on 2026-10-19, using upstream Flutter 3.27.4:

- `flutter pub get --enforce-lockfile`: passed with the existing lockfile.
- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub`: 683 tests passed, including 32 GenAI VM cases.
- The explicit Chrome fixture command above: both streaming/cancellation tests passed.
- `flutter build web --no-pub`: passed.
- Formatting checks on the GenAI sources/tests and service provider, plus
  `git diff --check`: passed. Existing unrelated formatting in `main.dart` was
  preserved; its new runtime wiring follows the formatter.

These results establish local protocol/lifecycle behavior and browser transport,
not campus endpoint availability, real account authentication, pricing, or billing.

## Unverified contracts before further platform features

- CAS-to-GenAI exchange, callback origins, token expiry and renewal, and whether
  a TechPie gateway is required. Its backend is not in this Flutter checkout.
- `X-Sign`: the summary's Python/JavaScript examples differ on duplicate query
  keys/path variables; numeric and nested-value serialization and timestamp
  timezone need verified vectors. Usage endpoints now support a deployment-configured signer; see the current tools section below.
- Model pagination, capability flags, limits, and current prices.
- How search results are passed into generation; file ids' lifetime, supported
  types/sizes and deletion; image-upload authorization and URL access rules.
- Synchronous image-generation timeouts, server cancellation, charging on
  interruption, and history persistence/reconciliation.
- Developer-key operations, document upload and vision-image upload remain outside the current tools.
  History, text-to-image generation and read-only usage are implemented below.


## TechPie module and full-app preview

The home feature list includes **校园 GenAI**, which pushes `GenAiPage` through
TechPie's normal navigation. It consumes the runtime from `ServiceProvider`;
there is no separate production app or login identity. Returning to Home and
opening GenAI again preserves the current conversation in memory. Logging out,
switching the primary identity or changing the campus binding clears it.

On supported mobile/macOS platforms, the login page opens the documented school
login entry in an embedded browser and captures only an exact, allowed GenAI
callback. Other platforms open the official portal externally and accept its
token or callback URL through an obscured, transient field. Both paths verify
the profile's campus student ID before saving a GenAI session. Real IDS login,
production CORS, and the upstream model/chat contract still need device/live
verification; the supplied summary alone does not establish those results.

The chat UI provides dynamic model selection, Markdown/code rendering, reasoning
output, stop, explicit retry, and a new conversation. Only completed turns enter
subsequent history. Conversation history, image generation and usage are available through the tools menu.
Documents and web-search augmentation remain separate integration work.

Run the **entire TechPie Flutter app** with the standard entry point:

```sh
source /Users/waterbucket/things/TechPie-flutter/.envrc
flutter run -d web-server --web-hostname=127.0.0.1 --web-port=18767 \
  --target=lib/main.dart --dart-define=TECHPI_DEBUG_FIXTURE=true
```

Open the local server, then use **Home → 校园 GenAI → 连接校园 GenAI →
使用演示账号连接**. The preview starts with a synthetic TechPie identity and
campus binding, but requires an explicit GenAI connection. It runs the same
profile verification, model discovery, SSE decoding, session ownership and chat
controller using a debug-only in-memory backend. A visible preview banner labels
it. The sample schedule and deadlines, preferences and secure credentials all
live in process-local stores. Automatic renewal, cloud sync, updates and campus
background work are skipped; unrelated TechPie API requests receive a local error. Only explicitly requested
IDS binding/renewal and GenAI requests use the live adapters described below. Restarting the app resets the fixture.

Without this debug flag the same module uses the real login and HTTP adapters.
`kDebugMode` prevents fixture activation in profile/release builds.


Prepared full-app integration validation (2026-10-19): Flutter analysis was
clean and all 712 VM/widget tests passed, including navigation from Home into
GenAI, synthetic connection, a streamed reply, back navigation and conversation
retention after reopening. These checks ran against a temporary copy with the
prepared patch because automatic approval review was unavailable and the managed
worktree remained read-only to the current chat. They do not establish a live
campus login, production CORS or device behavior.


## IDS reuse: existing code and resulting integration

The codebase was inspected before implementing the IDS integration:

- `ThirdPartyBindPage` already provides password and SMS binding for CpDaily/IDS.
- `ThirdPartyAuthService.cpdailyNode` is the source of the IDS cookie provider,
  including `raw.cookies` and `raw.tgc` as `CASTGC`.
- `CampusSessionHandle` prepares the account-scoped browser store and refreshes
  the session. `ElrcRecordingsPage._writeCampusSession` and `GenericWebViewPage`
  already inject this handle's cookies before opening official SSO.
- `SessionTree.withCookie` owns scheduled renewal and its bounded rejection/
  renew/retry behavior. GenAI does not implement a second renewal algorithm.

`GenAiLoginPage` and its native browser now accept the same `CampusSessionHandle`.
They prepare it, clear stale browser storage and inject its IDS-scoped cookies
before opening the documented GenAI login URL. This lets the existing school
session complete the SSO redirect. An expired IDS session can fall back to the
school portal; a resulting GenAI token must still pass profile/identity checks.
The primary GeekPie login token is never used as an IDS or GenAI credential.

The debug feature exposes **使用 TechPie IDS 登录**. With no real IDS cookie, it
opens the existing `ThirdPartyBindPage` rather than a new student-ID/password
form. The old preview-only identity page was removed. A successful binding stays
in the fixture's in-memory storage, and GenAI uses that binding's student ID.

Flutter web cannot inject a Cookie header or native browser cookies. Its local
preview therefore uses a loopback bridge: `CampusGenAiSessionIssuer` reads the
same IDS node through `SessionTree.withCookie`, and `LoopbackGenAiIdsExchange`
performs the official GenAI/IDS redirects through a fresh, memory-only cookie
jar. IDS cookies are scoped to the IDS host; `CASTGC` is never sent to GenAI.
Redirects are restricted to HTTPS on the two documented university hosts. A
login form requires IDS reauthentication through the existing TechPie binding.
The resulting JWT still goes through the normal GenAI profile check.

Run the loopback helper, then the entire TechPie app:

```sh
python3 tool/genai_preview_proxy.py --port 18768 --origin http://127.0.0.1:18767
flutter run --no-pub -d web-server --web-hostname=127.0.0.1 --web-port=18767 \
  --target=lib/main.dart --dart-define=TECHPI_DEBUG_FIXTURE=true \
  --dart-define=TECHPI_GENAI_PROXY_ORIGIN=http://127.0.0.1:18768
```

Use **Home → 校园 GenAI → 使用 TechPie IDS 登录**. Sign in using TechPie's
existing password/SMS form if needed; it then connects GenAI using that session.
There is no manual GenAI token-copy step on this preview path. Sample chat is
still available through the normal demo connection before binding a real account.

Only the existing IDS bind, send-SMS and renew routes are forwarded to TechPie's
fixed backend host in this preview; other TechPie services remain local. GenAI
profile, catalog and chat requests go to the fixed GenAI host. The helper binds
only to loopback, verifies TLS, rejects foreign browser origins, and logs no
paths, credentials or response content. It starts no upstream request merely by
starting. No reference-document signing secret is embedded. Real generations use
the school account's quota; debug credentials and cookies remain in memory.
A hosted production web build still needs a verified server-side SSO bridge;
it cannot set IDS cookies directly from browser JavaScript.

Proxy checks use only fake upstream connections:

```sh
python3 -m unittest discover -s test/tool -p '*_test.py' -v
```

Local tests cover the existing binding page entry, passing the IDS handle to
native login, cookie scoping, callback restrictions, session-tree renewal and
cancellation. These results do not establish a successful live school exchange.


IDS reuse validation: Flutter analysis is clean; all 728 Flutter tests and 14
Python proxy tests pass. Tests cover the original password/SMS binding entry,
the native campus-session handle, explicit reauthentication feedback, bounded
IDS renewal/retry, cancellation, fixed upstream hosts, cookie scoping and SSE
first-chunk delivery. Validation ran in the temporary preview copy because the
worktree apply attempt was rejected by automatic approval-review capacity.
A real university exchange has not been verified by the agent.


Worktree validation after successful apply (2026-10-19): the integration patch
has now been applied to the existing `codex/genai-foundation` worktree.
`flutter analyze --no-pub` reports no issues, all 728 Flutter tests pass, and all
14 local proxy tests pass from that worktree. The full `lib/main.dart` preview
and IDS proxy are now launched from the worktree rather than the temporary
verification copy. Live university SSO acceptance remains unverified.


## Missing school ID after IDS binding (2026-10-19)

The live preview showed a successful CpDaily/IDS binding followed by GenAI's
campus-account prompt. The binding exposed an internal CpDaily UUID, while
`cpdailyStudentId` was empty. The runtime required that school ID to create an
owner, and the previous restore action returned immediately without issuing an
SSO request when the owner was absent.

The explicit IDS connect action now permits that trusted exchange to run before
an owner is available. It resolves the school ID from the GenAI profile obtained
using the current IDS binding, then verifies the credential again through the
normal owner-matching session service before persistence. A phone number,
CpDaily UUID, arbitrary pasted token, or primary GeekPie student ID cannot fill
this missing identity. The resolved school ID stays in runtime memory, scoped
to primary user, campus account and binding timestamp; rebinding, unbinding or
switching users clears it. IDS cookie renewal preserves the resolution, while
every new GenAI credential still requires a matching profile.

The bound-but-unresolved state now offers **使用现有 IDS 会话连接**, shows
connection failures, and links to the existing campus-account management page.
The fix also checks catalog-request cancellation before attaching a session
listener, covering immediate app disposal after login. The native/manual-token
path still requires a binding with a known school ID; the missing-ID bootstrap
uses the IDS-backed issuer available in the local web preview.

Validation of this fix in the GenAI worktree: `flutter analyze --no-pub` is
clean; all 737 Flutter tests pass, including 86 GenAI tests. New regressions
cover SMS/UUID bindings, school-ID rejection rules, renewal and reconnect,
rebinding cleanup, cancellation of a late IDS response, and the visible
identity-resolution action. These are local fake-network tests; live GenAI
SSO/profile/catalog acceptance still requires retrying the user's login.


## Current platform tools and live verification (2026-10-19)

The existing full-app preview completed live IDS-to-GenAI issuance, loaded the
real free-model catalog, and returned the requested short Chinese reply through
streaming chat. Disconnecting GenAI and reusing the same IDS binding also
completed issuance and reloaded models without another password form. Evidence
contains no account identifiers or credentials. This supersedes earlier notes
that live SSO/model/chat acceptance was unverified.

**更多 GenAI 功能** in the workspace header (and buttons in the wide sidebar)
opens the integrated tools: **会话记录**, **图片创作**, and **用量统计**.
They reuse the verified runtime session and cancel outstanding operations when
its revision changes. Data is cleared on account changes; server responses
from old sessions cannot populate a new account's page.

- Conversations: server pagination and search, restore a conversation with its
  original group ID, continue using completed turns, and delete with an explicit
  irreversible-action dialog. Reasoning in saved `<think>` blocks is separated
  from answer context. Unavailable historical models require an explicit choice.
- Images: catalog status `2` identifies image models; statuses used for chat are
  kept out of the image selector. Text chat excludes image models. Generation
  uses the synchronous JSON form of `/chat/start/chat` with `aiSecType: "1"`, a
  new group ID, one image, selected size and quality, and PNG output. It is never
  retried automatically. A confirmation shows quota implications. Header waits
  allow up to three minutes; leaving the page aborts local work without claiming
  cancellation of server billing. Results and paginated image history use the
  documented university CDN, with a fallback link when inline preview fails.
- Usage: `/ai-api-gateway/my/summary` and paginated `/ai-trade-order/my/list`
  expose server-reported quotas and itemized input/output/image tokens. No token
  counts or charges are guessed locally. Developer keys in summary responses are
  discarded; the module has no key creation, reset, plaintext-key or payment UI.

The reference was cross-checked against the official publicly served frontend:
`/js/app.4143511d.js` (signer), `/js/chunk-a18ada4c.33973756.js`
(conversations/model status), `/js/chunk-752c4439.31556fc7.js` (image payload and
history), and `/js/chunk-36a235b4.019b3989.js` (usage routes). These are source
observations rather than guarantees about all accounts or future releases.

The public frontend's anti-tamper salt is supplied by deployment configuration
as `TECHPI_GENAI_SIGNING_SALT`; account passwords, tokens and developer keys must
never be used as that value. No salt or user credential is hard-coded in the
repository. The local preview uses a private temporary JSON define file holding
only that public protocol configuration. To run an equivalent preview, append
`--dart-define-from-file=/absolute/path/to/preview-config.json` to the existing
full-app command; its JSON object has `TECHPI_GENAI_SIGNING_SALT` set to the
current platform's public frontend salt. The bridge permits only the additional
history/image/usage routes and forwards signing headers; developer-key routes
remain blocked.

The synthetic backend also supports history/image/usage fixtures. Synthetic
image previews render locally and never load the university CDN. The initial
live-verification build passed all 744 Flutter tests and 15 proxy tests, with
clean Flutter analysis. Additional live tools outcomes are recorded below.

Final local validation: analysis is clean, all 745 Flutter tests pass, all 15
proxy tests pass, formatting is clean, and both running processes use the GenAI
worktree. Browser inspection of a separate synthetic fixture confirmed the
workspace tool entries, image controls and usage layout without campus calls.
The fixture tab was then closed. The live tab is left on TechPie's existing IDS
form after the refresh; live history/usage/image verification is pending a new
in-memory sign-in. Authorization covers one low-quality 1024x1024 live image,
but no image request has yet been submitted and no real records were deleted.


Live tools results after the user's next IDS sign-in:

- Server conversation listing loaded real history. Reopening the original test
  group restored its model/messages; a follow-up response correctly recalled
  the original requested phrase, verifying continuation with context.
- Signed quota summary and itemized usage loaded successfully. Image history
  loaded and rendered previously generated images from the university CDN.
- The initial approved image attempt produced a compatibility failure. The
  preview bridge had advertised streaming for image requests; it now preserves
  JSON Accept, bounds synchronous response buffering, and supports the image
  API's optional success flag. The direct client also accepts that raw response
  variant and sends null absent image inputs, matching the public frontend.
- The user authorized one retry. It returned a server JSON business failure:
  success false, code 500, no image data. No further generation was submitted.
  This establishes explicit failure handling, not successful live generation;
  billing can settle later. No real conversation or image record was deleted.

The expanded **更多功能** entry now opens a responsive feature sheet with icons,
short descriptions, current model/conversation context, and quick new-chat and
refresh-model actions. Model refresh preserves an explicitly selected model
when still available. Demo mode includes a direct IDS-login shortcut. Narrow
screens retain the compact icon entry and get a scrollable panel; wide screens
show the text label. The sheet follows dark/light colors and closes before
navigating to the existing tool pages. Runtime/session boundaries are unchanged.


Expanded-panel final validation: `flutter analyze --no-pub` is clean, all 748
Flutter tests pass, and all 16 Python proxy tests pass. Format checking covers
all GenAI sources and tests. Both preview processes run from the same managed
GenAI worktree. The full app was refreshed to show the new feature panel;
preview credentials were reset and the visible demo uses the labeled synthetic
account. Earlier live SSO/chat/history/usage results remain valid evidence,
while new image generation remains blocked by the observed platform failure.

## Live capture protocol alignment (2026-10-19 19:29)

Cross-referencing live network captures `[26-10-19 10-37-18].har` and
`[26-10-19 19-29-11].har` with the official frontend bundle revealed key protocol
details that are now aligned in the codebase:

1. **Conversation & Image Deletion**:
   - Upstream endpoints (`/htk/ai/history/delete/groupId` and `/htk/ai-image-history/delete`)
     are dispatched as HTTP **`GET`** requests via Jeecg Axios `getAction`, passing
     `id` and cache-busting timestamp `_t` as query parameters (`?id=...&_t=...`) with
     `X-Access-Token` and `tenant-id: 0`. They do not use `POST` with JSON bodies or `X-Sign`.
2. **Image Generation Wire Payload**:
   - `count` is serialized as a string (`"1"`).
   - Unused inputs (`outputCompression`, `imageBase64`, `imageBase64List`) are explicitly `null`.
   - `tenant-id: 0` is sent on all JSON requests and streaming requests.
   - Default public anti-tamper signing salt (`dd05f1c54d63749eda95f9fa6d49v442a`)
     matches the public frontend bundle `app.4143511d.js`.
3. **Image Aspect Ratios & Resolution Presets**:
   - In addition to square `1024x1024`, the platform's frontend presets (`chunk-752c4439.31556fc7.js`)
     support 1K, 2K, and 4K resolutions across 1:1, 3:2, 2:3, 4:3, 3:4, 5:4, 4:5, 16:9,
     9:16, 2:1, 1:2, 21:9, and 9:21 (e.g. `1024x768`, `768x1024`, `1136x640`, `2048x2048`, `3840x2160`).
   - `GenAiImageRequest` now validates against these supported platform presets.
4. **Validation**:
   - `flutter analyze --no-pub`: 0 issues found.
   - Full test suite: all 751 tests passed, including all 100 GenAI tests.
   - Python proxy unit test suite: all 17 tests passed.
   - Flutter web-server hot-restarted cleanly.
