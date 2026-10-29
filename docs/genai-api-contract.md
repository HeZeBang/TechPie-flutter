# GenAI integration contract

The school API is not versioned by this client. These contracts reflect the
implementation and observed server behavior; model availability, pricing and
limits can change independently. The [agent guide](genai-agent-harness.md) covers
framing, tools, context and server-only recovery.

## Integration and identity

`GenAiRuntime` is wired lazily through `ServiceProvider`. Reuse existing TechPie
services for authentication, timetable, assignments and booking. Leaving the page
cancels active agent work while retaining the transient workspace.

GenAI requires the primary TechPie identity and a campus binding. The verified
profile username must match the binding's student ID, not the primary GeekPie ID.
Ownership includes primary user ID, campus ID and binding time; renewal preserves
it, while rebinding/account changes invalidate it. Async requests, uploads, pickers,
audio and history reads must not apply results to a different owner or chat.

`CampusGenAiSessionIssuer` reuses CpDaily/IDS and `SessionTree.withCookie`. Native
SSO uses an isolated cookie jar; CASTGC stays on IDS and redirects require allowed
university HTTPS origins. Profile verification precedes token persistence. Trusted
IDS exchange may resolve an initially unknown SMS-binding ID; pasted tokens cannot
bootstrap identity. TechPie's existing binding UI handles credentials.

Credentials use the OHOS-aware secure store, outside cloud sync. Cached tokens are
reverified; concurrent issuance is shared and store operations serialized. Logout
clears memory immediately and queues deletion, surfacing failures. A stale rejected
request cannot invalidate a newer login. Authentication errors never automatically
replay a generation.

## Requests and streaming

Base: `https://genai.shanghaitech.edu.cn/htk/`. Injected bases require HTTPS except
loopback fixtures. API calls do not follow redirects. Exclude payloads, credential
URLs and raw upstream errors from logs.

| Operation | Wire contract |
| --- | --- |
| Profile | `GET user/info/{token}`, `X-Access-Token`; verify `userInfo.id` and `username` |
| Models | `GET ai/aiModel/list`; paged `aiType`, `rootAiType`, status and optional prices |
| Chat | `POST chat/start/chat`; stable `chatGroupId`, latest input in `chatInfo`, context in `messages`, `type: "3"`, `stream: true` |
| Document | `POST chat/upload/chat/file?chatGroupId=...&aiType=...`; multipart `biz=temp`, `file` |
| Vision upload | Image host `/sys/common/upload`; canonical campus CDN URL |
| Generation | JSON `chat/start/chat`, `aiSecType: "1"`, `count: "1"`, PNG, size/quality and optional references |
| Usage | Signed `ai-api-gateway/my/summary` and `ai-trade-order/my/list` |
| Message deletion | `GET ai/history/delete/batch?ids=...`; comma-separated server row `id` values, not logical turn IDs |
| Deletion | `GET ai/history/delete/groupId?id=...` or `DELETE ai-image-history/delete?id=...`; explicit confirmation |

JSON envelopes require successful status/code; image generation also accepts its
raw response variant. Authentication expiry, rejection, transport, protocol and
storage failures remain distinguishable and sanitized. The signing salt is public
protocol configuration (`TECHPI_GENAI_SIGNING_SALT` override), never an account secret.

Host instructions precede prior context; agent requests also append a concise
protocol guide immediately before the current input. Both modes use the catalog's
`enableDeepThink` capability and selected thinking flag, and force `netGo: false`.
There is no search preflight/tool; historical citations remain readable.

SSE supports incremental UTF-8, CR/LF/CRLF, comments and multiline data with bounded
event sizes. Reasoning and answer deltas stay separate. A terminal finish reason
or `[DONE]` completes the stream; bare EOF is interruption. Malformed events fail
visibly. Cancellation aborts local work without promising server rollback or
avoided billing. No automatic generation POST retry or stream reconnection occurs.

## Documents and images

Documents accept TXT, PDF, DOCX, XLSX, XLS and CSV. Recognized UTF-8 code/Markdown
keeps its display name and bytes but uses a `.txt` wire name. Legacy DOC,
PowerPoint and disguised binary text are rejected. Upload limits are 10 MiB and
500,000 extracted characters. Native `file_selector` checks size before and during
reading; web uses the same filename/content validation. Cancellation returns no
attachment. macOS requires the user-selected read-only entitlement.

Upload responses require string `content`: empty means known-empty extraction;
missing/non-string means protocol failure. Failed uploads block sending until
removed/retried. Recovered file IDs without extraction require a new chat and
re-upload: re-uploading into the same group cannot remove unknown earlier IDs.
Both modes carry deduplicated references through follow-ups, retries and reopening.
Extraction counts in full toward context, without duplicate instruction copies.
Archived IDs do not guarantee server availability; expired files need re-upload.

Vision history accepts URL arrays and legacy comma-separated `imageUrl`. Store
canonical validated CDN URLs. Chat,
reasoning and tool images share the trusted-URL policy; external/data/file images
do not load automatically. Chat, gallery and viewer share long-press/right-click
and accessible image actions. Copy/share capability varies by platform; Android
uses a non-exported cache FileProvider and iPad sharing needs source bounds.

Image dimensions must be positive integers totaling 655,360–8,294,400 pixels;
width above 2560 or height above 1440 carries the experimental-size notice.
References remain local until generation: validated PNG/JPEG/WebP, at most four,
10 MiB each and 25 MiB combined. One uses `imageBase64`, several use
`imageBase64List`; unused fields are null. Confirmation includes parameters and
quota implications. Ambiguous outcomes are never automatically regenerated.

## Platform boundaries and verification

Native and web implement chat, history, images, usage and agents. Native document
selection is implemented; native audio capture/playback remains unavailable.
Web audio depends on browser capability and permission. Production web SSO needs
a bridge: browser JavaScript cannot inject IDS cookies. No development login
proxy or seeded academic data is bundled.

Run `flutter analyze --no-pub` and `flutter test --no-pub` with the repository SDK.
Keep regression coverage for framing/stream boundaries, ownership races,
confirmations, unknown mutations, document extraction, server-only recovery and
compaction provenance. Keep one-off screenshots, demo fixtures, diagnostics and
live-run reports outside production changes.

The browser transport test needs an explicit local fixture: run
`python3 test/genai/support/stream_fixture.py --port 18765`, then
`flutter test --no-pub --platform chrome --dart-define=GENAI_TEST_ORIGIN=http://127.0.0.1:18765 test/genai/platform/http_genai_transport_browser_test.dart`.
Synthetic tests do not establish current school-service availability.

The vision upload gateway token can be overridden at build time with
`--dart-define=TECHPI_GENAI_VISION_TOKEN=...`; existing installations require an update.
