# GenAI integration contract

This is the current implementation guide, reviewed on 2026-10-26. The supplied
ShanghaiTech API reference is observational documentation, not a versioned school
API guarantee. Route and payload decisions also reflect public frontend captures.
Model availability, prices, expiry and server behavior can change independently
of this client. See [the agent guide](genai-agent-harness.md) for tools and approvals.

## Ownership and entry points

`TechPieApp` wires `GenAiRuntime` through `ServiceProvider`; Home → 校园 GenAI opens
`GenAiPage`. Runtime construction is lazy. The app retains the current workspace
when navigating away; leaving the page cancels active agent work.

| Layer | Responsibility |
| --- | --- |
| `app/genai_runtime.dart` | Existing TechPie services, identity binding and platform adapters |
| `application/genai_workspace_controller.dart` | Transient turns, attachments, selections and operation lifetimes |
| `application/genai_repository.dart` | Verified session use, context preparation and typed API operations |
| `application/genai_context_compactor.dart` | Bounded source-based context and disposable summary checkpoints |
| `data/genai_api_client.dart`, `platform/` | HTTP, JSON/multipart contracts, streaming and cancellation |
| `domain/` | Validated records, failures, protocol framing and attachment constraints |
| `presentation/genai_workspace.dart` | Page navigation, transcript, dialogs and draft/scroll orchestration |
| `presentation/genai_composer.dart` | Responsive input controls and immutable callbacks |
| `presentation/genai_history_controller.dart`, `genai_history_sidebar.dart` | Account-scoped history queries and sidebar rendering |
| `presentation/audio/genai_workspace_media.dart` | Picker, microphone and playback lifetimes |
| Remaining `presentation/` | Process view, images, account/usage and platform media UI |

Paths above are relative to `lib/features/genai/`. Reuse existing services rather
than adding parallel login, timetable, assignment or booking implementations.

## Authentication and sessions

GenAI requires the primary TechPie identity and a bound campus identity. Its
verified profile username must match the **campus binding's student ID**, not the
primary GeekPie student ID. Owner scope includes primary user ID, campus ID and
binding time. Token renewal preserves ownership; rebinding or changing accounts
invalidates it. Requests, uploads, pickers, audio and history selections carry
scope/revision checks so late work cannot populate another chat or identity.

`CampusGenAiSessionIssuer` reuses the CpDaily/IDS node and `SessionTree.withCookie`.
Native builds perform the official SSO redirects in an isolated cookie jar. The
web preview uses the loopback bridge because browser JavaScript cannot inject
IDS cookies. CASTGC is restricted to IDS; redirects require the allowed university
HTTPS origins. Tokens are intercepted at the callback and verified by the profile
API before persistence. A trusted IDS exchange can resolve SMS bindings whose
school ID is initially unknown; arbitrary pasted tokens cannot bootstrap identity.
The existing TechPie binding page handles password/SMS entry. The native login
panel has one primary connect action using saved IDS; campus binding management
remains in the account menu. Debug-demo switching stays in that menu as well.

GenAI credentials use the OHOS-aware secure store under
`techpie.genai.session.v1.<owner hash>`, outside cloud sync and third-party token
storage. Cached tokens are reverified before activation. Issuance is shared by
concurrent callers and secure-store operations are serialized. Logout clears
memory immediately and queues credential deletion; failures remain observable.
A stale rejected request cannot invalidate a newer login. Generation requests
are never automatically replayed after authentication failure.

## HTTP and streaming contract

Default base: `https://genai.shanghaitech.edu.cn/htk/`. Injected bases require HTTPS
except loopback fixtures. API requests do not follow redirects. GenAI payloads,
credential-bearing URLs and raw upstream errors are excluded from debug logs.

| Operation | Request / response |
| --- | --- |
| Profile | `GET user/info/{token}`, `X-Access-Token`; verified `userInfo.id` and `username` |
| Models | `GET ai/aiModel/list`; paged records with `aiType`, `rootAiType`, status and optional pricing |
| Chat | `POST chat/start/chat`; `chatInfo` is the latest prompt, `messages` is supplied context, stable `chatGroupId`, `type: "3"`, `stream: true` |
| Search | Disabled; historical source links remain readable |
| Documents | `POST chat/upload/chat/file?chatGroupId=...&aiType=...`; multipart `biz=temp`, `file` |
| Vision upload | Image host `/sys/common/upload`; canonical campus CDN URL returned |
| Images | JSON `chat/start/chat`, `aiSecType: "1"`, `count: "1"`, PNG, size/quality and optional reference data |
| Usage | Signed `ai-api-gateway/my/summary` and `ai-trade-order/my/list`; server-reported quantities |
| Deletion | `GET ai/history/delete/groupId?id=...` for conversations, `DELETE ai-image-history/delete?id=...` for images; explicit UI confirmation |

General JSON envelopes require successful code/status; the image endpoint also
accepts its documented raw response variant. HTTP or business authentication
errors invalidate only the session that made the request. Other rejection,
transport, protocol and storage failures remain distinguishable and sanitized.

Every generation has exactly one host-built system message reflecting current
modes, followed by prior context. Both chat modes use the selected `thinking` flag and
force `netGo: false`; neither dispatches a search preflight or exposes a search tool.
Agent requests inject the active task, current image catalog and protocol-repair
candidate into that system message as `CURRENT_REQUEST`. Generic instructions and
reconstructible controls are not persisted in `chatInfo`; its `step_id` also serves
as the current call nonce.

The request signer includes the public frontend's protocol salt by default;
`TECHPI_GENAI_SIGNING_SALT` can override it. It is public protocol configuration,
not an account secret. Do not substitute passwords, tokens or developer keys.
Developer-key/payment operations are not exposed by this module.

SSE decoding handles incremental UTF-8, CR/LF/CRLF, comments and multiline data;
lines/events are capped at 256 KiB. Answer and provider reasoning deltas stay
separate. A terminal finish reason or `[DONE]` completes the stream; bare EOF is
interrupted, never successful. Malformed events fail visibly. Headers use 20s
normally and 90s for chat; SSE idle timeout is 60s. Image generation permits a
longer synchronous wait. Stop aborts local work without claiming server rollback
or avoided billing. No automatic generation retry or stream reconnection occurs.

The catalog's `enableDeepThink` flag, not model-name heuristics, controls whether
thinking can be enabled. Ordinary chat, tools and the composer use the same flag.

## Attachments and images

Documents accept TXT, PDF, DOCX, XLSX, XLS and CSV. Recognized UTF-8 code/Markdown
files retain their UI name and bytes, using a wire name such as `notes_md.txt`.
Legacy DOC, PowerPoint and disguised binary text are rejected. Limits are 10 MiB
per upload and 500,000 extracted characters; text is checked locally where
possible, while PDF/Office extraction remains server-enforced.

Native builds use the OHOS-compatible `file_selector` fork for documents, with
size checks before and during reading and the same filename/content validation as
web uploads. macOS has the user-selected read-only entitlement. Cancelling a
picker returns no attachment; unsupported/oversized files surface an error.
HTTP 401 from image upload follows the shared authentication-expiry path.

Upload responses must contain string `content`: an explicit empty string is
known-empty extraction; missing/non-string text is a protocol failure. Unknown
text cannot be counted as zero when the server injects it into model context.
Failed uploads block sending until removed or retried. Existing archives with
file IDs but no extraction require starting a new chat and re-uploading there;
re-uploading within the same chat does not remove its earlier unknown IDs.

Both chat modes recover deduplicated document and image references from the conversation
on follow-ups and latest-turn retry, including reopened chats. A new chat, account
change or missing-history gap clears earlier references. Original attachment
metadata remains on its source turn. Document extraction is counted in full but
not duplicated into system instructions or history. Archived IDs do not prove
continued server availability; re-upload expired documents.

Saved vision records accept URL arrays and the legacy comma-separated `imageUrl`.
Validated canonical CDN URLs are stored; only rendering resolves the preview
proxy. Model Markdown in replies and reasoning, and tool image results, share a
trusted-image policy: arbitrary external/data/file URLs do not load automatically.
Blocked images show a placeholder. The debug campus image is a bundled real scene.
Chat images, gallery tiles and viewers share long-press/right-click actions and an
accessible menu button. Copy/share uses the displayed image provider; copied links
use canonical campus URLs. Unsupported platform actions are hidden: Linux copies
an image file, OHOS retains save/link actions, and web clipboard/share depends on
browser support and permissions. Android clipboard URIs use a non-exported cache
FileProvider; iPad sharing supplies the visible image bounds as its popover origin.
Invalid chart numbers, overflowing/underflowing ranges and magnitudes above 1e15
fall back to source text; this keeps the chart library's integer-based axis
rounding bounded instead of hanging or substituting false zeros.

Image creation groups its 13 aspect ratios by square, landscape and portrait,
then offers the matching 1K/2K/4K presets. Switching landscape/portrait keeps
the ratio family and supported resolution tier; custom dimensions remain available.
Positive integer dimensions must total 655,360–8,294,400 pixels. Width above 2560
or height above 1440 shows the platform's experimental-size notice. Reference
images stay local until generation: PNG/JPEG/WebP, decoded/signature checked,
at most four files, 10 MiB each and 25 MiB combined. One reference uses
`imageBase64`; several use `imageBase64List`. Unused image fields are null.
The confirmation includes size, quality and quota implications. Ambiguous outcomes
are reported for manual checking, never automatically regenerated.

## Context and server recovery

The default context profile is 256k, with output/safety reserves and no assumed
16k latest-input limit. Text is conservatively estimated rather than counted as
UTF-8 bytes. Attachments and host metadata consume the same budget. Compaction
retains original records and source-validated boundaries; it does not repeatedly
summarize an unchanged prefix on every follow-up.

GenAI's history API is the sole durable conversation store. Normal exchanges put
version 2 host records in `chatInfo` (with version 1 read compatibility), including
turn/parent/step identifiers,
attachment metadata and changed compaction/operation recovery state. `messages`
remains the inference context, never a persistence mechanism. Changed operation receipts and compacted-prefix markers
are piggybacked on real requests, not saved through extra bookkeeping generations.
`effectKeys` references the current input receipt instead of duplicating its
payload. Defaults and duplicate identifiers are omitted, and the model ID is read
from the server row. Original document text, retry ancestry, approval budgets,
normalized operation identities and request context estimates remain portable.
Summary answers are recovered from existing same-chat extraction rows by source
hash and revalidated against the original messages.
Fresh instances decode the same server records for UI, export and model evidence.
The prior encrypted local conversation store and background save machinery have
been removed. Authentication still uses its separate secure credential store.

History is append-only: retry appends a new identified branch. Opening does not
change logical last-message ordering. Renamed titles sync with the next actual
message; the UI labels this behavior. Cancellation never promises server rollback.
Missing receipts retain unknown outcomes and never authorize replay. Before a
mutation, a read-back barrier confirms that the proposed call is saved. Ambiguous
generation POSTs are never replayed automatically. Concurrent devices may append
different paths; the API offers no atomic cross-device execution lock.

See [the agent guide](genai-agent-harness.md) for the portable record format,
version 3 live call/final protocol, safety invariants and recovery tests.

## Platform support and preview

| Capability | Flutter web | Native adapters in this branch |
| --- | --- | --- |
| Chat, history, images, usage, agent | Implemented; needs permitted network/SSO deployment | Implemented; device behavior needs platform verification |
| IDS issuance | Loopback bridge for debug; hosted deployment needs a server bridge | Native isolated SSO exchange |
| Image picker | Browser picker | Existing `image_picker` integration |
| Document/audio file picker | Implemented | Unavailable; controls hidden, calls fail explicitly |
| Microphone and audio playback | Browser capability/permission dependent | Unavailable; no simulated success |

The debug fixture seeds campus data in memory. Real IDS/GenAI can be connected
explicitly, but seeded timetable/assignment services are not real-account access.
Academic tools refuse to present that seeded data as live data. The test-only IDS
academic integration is excluded; production tools use normal TechPie bindings.
Reloading the debug app clears its in-memory identity and fake server history.

Run the **full** app from the worktree with Flutter 3.41.9, the SDK verified for
this branch and its locked dependencies. Set `FLUTTER_SDK` to that
installation before loading `.envrc` **in each terminal**; the older local default
SDK does not satisfy this branch.

```sh
export FLUTTER_SDK=/path/to/compatible/flutter
source /Users/waterbucket/things/TechPie-flutter/.envrc
python3 tool/genai_preview_proxy.py --port 18768 --origin http://127.0.0.1:18767
# In another terminal, from the same worktree:
export FLUTTER_SDK=/path/to/compatible/flutter
source /Users/waterbucket/things/TechPie-flutter/.envrc
flutter run --no-pub -d web-server --web-hostname=127.0.0.1 --web-port=18767 \
  --target=lib/main.dart --dart-define=TECHPI_DEBUG_FIXTURE=true \
  --dart-define=TECHPI_GENAI_PROXY_ORIGIN=http://127.0.0.1:18768
```

Choose the labeled demo connection for offline fixtures or explicitly use the
existing IDS binding form for school access. The proxy binds only to loopback,
checks origin/TLS, restricts upstream hosts/routes and keeps cookies in memory.
It is a development helper, not a production deployment. Real calls use quota.

## Verification and maintenance

```sh
flutter analyze --no-pub
flutter test --no-pub
python3 -m unittest discover -s test/tool -p genai_preview_proxy_test.py
```

For actual browser Fetch streaming/cancellation, run
`python3 tool/genai_stream_fixture.py --port 18765`, then:

```sh
flutter test --no-pub --platform chrome \
  --dart-define=GENAI_TEST_ORIGIN=http://127.0.0.1:18765 \
  test/genai/platform/http_genai_transport_browser_test.dart
```

Tests use synthetic data. Preserve coverage of session races, server-history recovery,
protocol boundaries, context provenance, approvals and rendering failures; avoid
assertions that merely freeze incidental styling. Nonces, schema checks, source
hashes and account guards serve different invariants and are not interchangeable.

Live Kimi-K3 runs previously exercised IDS issuance, chat, uploads, vision and
remote compaction recovery. These are historical observations, not current
availability promises. Record each new run's commands/results separately instead
of appending contradictory test counts and intermediate failures to this contract.
Native audio support, production web SSO deployment and concurrent cross-device
branch resolution remain explicit limitations. BYOK would be a separate provider design;
it is not an existing school API feature.

### Agent image inspection

The school web client includes `imageUrl`/`imageUrls` on historical messages, but
Kimi-K3 live checks showed only the primary request image was reliably visible.
The agent therefore exposes an `inspect_image` selection tool over the recovered
conversation catalog. Selection sets both current-image fields to one known URL;
it never accepts arbitrary URLs or generates images. Model-authored comparison
notes remain assistant call arguments, distinct from the host selection receipt.
The selected image is run-local; a new request defaults to the latest image.
