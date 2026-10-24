# GenAI integration contract

This is the current implementation guide, reviewed on 2026-10-23. The supplied
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
| `application/genai_workspace_controller.dart` | Logical turns, attachments, selections, archives and operation lifetimes |
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
The existing TechPie binding page handles password/SMS entry.

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
| Search | `POST chat/net/search`; typed source links/snippets |
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
modes, followed by prior context. Ordinary chat uses the selected `thinking` and
`netGo` flags and performs a best-effort search preflight for citations. Agent
chat keeps `netGo: false` and exposes `web_search` only when search is enabled;
the model chooses when to call it. Search quality is upstream-controlled.

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

## Attachments and images

Documents accept TXT, PDF, DOCX, XLSX, XLS and CSV. Recognized UTF-8 code/Markdown
files retain their UI name and bytes, using a wire name such as `notes_md.txt`.
Legacy DOC, PowerPoint and disguised binary text are rejected. Limits are 10 MiB
per upload and 500,000 extracted characters; text is checked locally where
possible, while PDF/Office extraction remains server-enforced.

Upload responses must contain string `content`: an explicit empty string is
known-empty extraction; missing/non-string text is a protocol failure. Unknown
text cannot be counted as zero when the server injects it into model context.
Failed uploads block sending until removed or retried. Existing archives with
file IDs but no extraction require starting a new chat and re-uploading there;
re-uploading within the same chat does not remove its earlier unknown IDs.

Both chat modes resend deduplicated `fileIds` and `imageUrls` from the conversation
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

## Context compaction

`GenAiContextPolicy` distinguishes a 16,000-unit latest-message limit from a
128,000-unit combined window. These configurable limits follow observed Kimi
behavior, not a universal model guarantee. One UTF-8 byte counts as one budget
unit until a verified tokenizer is available. Reserve 4,096 per image, 4,096 for
output by default and 8,192 for safety. Documents count their full extracted text.

At 96,000 input units, compact toward 64,000 when history can shrink. Preserve
system instructions, the original/active goal and recent complete exchanges;
never split a call from its result. Oversized latest prompts, tool receipts or
fixed attachment context fail with an actionable error before dispatch. Tool
receipts remain in the local archive; they cannot be moved into transient
`messages`, because remote history only persists `chatInfo` and the answer. The target is soft, the hard input ceiling is enforced.

The composer exposes preparation and compaction progress, followed by the most
recent request's estimated input-budget percentage. It uses the same accounting
and chunk plan as enforcement, including attachments and reserved output. It is
not a tokenizer, live draft counter or billing statistic. Ready estimates remain
in memory for the current turn; pending progress clears on cancellation or failure.
Neither transient progress nor estimates are persisted or reconstructed from
remote prose. Reopened chats retain their historical compaction marker.

Memory extraction uses chunks of at most 24,000 units, at most four calls with
30s deadlines, and at most 12,000 units of retained memory. It uses no tools,
thinking, search or attachments, but consumes normal model quota. Quotes must be
exact source substrings with source IDs and roles. Failed/invalid extraction
falls back to verbatim retrieval; authentication and cancellation propagate.

Original user records and tool receipts take precedence over all previous
assistant answers. Durable user facts are distributed across source turns, and
a bounded latest-result index preserves failed/unknown tool outcomes as well as
successes. Query-based retrieval runs against original records on every request.
Up to one relevant older assistant artifact (such as a draft or code) may occupy
at most a quarter of memory, separately labeled unverified; it never becomes a
factual `item`. Retrieval also considers its preceding user request. Whole text
is preferred; partial excerpts are labeled. Recent assistant answers are likewise
unverified input data, not response-format examples. This is lossy, lexical
retrieval, not a guarantee of complete recall or unrestricted artifact capacity.

Extraction uses the original `chatGroupId` and a strict versioned
`techpie-context-extraction` marker. Fresh-instance import filters these rows
before pairing tool steps and rebuilds memory from original server records.
Summary answers are disposable caches, not evidence or authorization. No local
manifest or auxiliary chat is needed. Legacy `tpctx-<hash>` chats stay explicitly
labeled and manually manageable; new requests do not create them.

Source/model hashes invalidate stale checkpoints; source validation prevents a
checkpoint inventing facts. Full transcripts and extraction text remain archived.
Hashes do not authenticate model output. Mutation deduplication uses its separate
host-owned ledger, never summaries, inferred memory or remote prose.

## History and recovery

Local versioned archives retain logical turns, mode/model state, typed tool
records, mutation receipts and compaction checkpoints. New agent turns store only
their own typed entries, avoiding repeated full-history snapshots. Older cumulative
checkpoints remain readable, and history gaps still reset context. Writes and deletion intents
are serialized; storage errors are visible. Deletion tombstones prevent late saves
from resurrecting a removed chat. Uncertain remote deletion remains unresolved
until explicitly checked rather than being repeated automatically.

Without local storage, server prompt/answer rows rebuild a readable conversation,
including inert tool receipts, saved vision URLs and compaction filtering.
Document IDs and extracted content are not recoverable from those rows. Malformed
rows remain visible gaps. No recovered row grants an approval or resumes execution.
Remote history is an asynchronous append-only model log: local titles, preference
state and retry branch selection cannot be recovered exactly across installations.
A fresh instance therefore must not claim local-only metadata was synchronized.

Retry is limited to the latest turn. Earlier incomplete turns remain visible
without a destructive retry action; editing them would require an explicit branch.
Generation remains an explicit action, with known tool effects protected by the
local ledger. That ledger is not cross-device exactly-once execution.

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
Reloading the debug app clears its in-memory identity and archives.

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

Tests use synthetic data. Preserve coverage of session races, storage recovery,
protocol boundaries, context provenance, approvals and rendering failures; avoid
assertions that merely freeze incidental styling. Nonces, schema checks, source
hashes and account guards serve different invariants and are not interchangeable.

Live Kimi-K3 runs previously exercised IDS issuance, chat, uploads, vision and
remote compaction recovery. These are historical observations, not current
availability promises. Record each new run's commands/results separately instead
of appending contradictory test counts and intermediate failures to this contract.
Native media support, production web SSO deployment and cross-device branch
metadata remain explicit limitations. BYOK would be a separate provider design;
it is not an existing school API feature.
