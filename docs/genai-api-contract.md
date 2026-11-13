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
| Models | Merge `GET ai/aiModel/list` with `ai/aiModel/list/V2`; keep routes/status and refreshed thinking/pricing metadata |
| Chat | `POST chat/start/chat`; stable `chatGroupId`, latest input in `chatInfo`, context in `messages`, `type: "3"`, `stream: true` |
| Document | `POST chat/upload/chat/file?chatGroupId=...&aiType=...`; multipart `biz=temp`, `file` |
| Vision upload | Image host `/sys/common/upload`; canonical campus CDN URL |
| Generation | JSON `chat/start/chat`, `aiSecType: "1"`, `count: "1"`, PNG, size/quality and optional references |
| Usage | Signed `ai-api-gateway/my/summary` and `ai-trade-order/my/list` |
| Session metadata | `POST ai/history/group/rename` (`chatGroupId`, `title`), `group/pin` (`chatGroupIds`, `pinned`), `group/delete` (`chatGroupIds`) |
| Message deletion | `GET ai/history/delete/batch?ids=...`; comma-separated server row `id` values, not logical turn IDs |
| Deletion | `GET ai/history/delete/groupId?id=...` or `DELETE ai-image-history/delete?id=...`; explicit confirmation |

Catalog V2 may return the full registry rather than a curated subset. Skip rows
without explicit routing identifiers, retain valid legacy metadata when optional
V2 fields are null, and admit new V2 routes only for chat/image statuses 3/2.
Utility models do not belong in the chat picker; never infer a missing provider.

JSON envelopes require successful status/code; image generation also accepts its
raw response variant. Authentication expiry, rejection, transport, protocol and
storage failures remain distinguishable and sanitized. The signing salt is public
protocol configuration (`TECHPI_GENAI_SIGNING_SALT` override), never an account secret.

An HTTP 404 HTML response displaying `该服务暂不开放外网访问，仅支持校内访问`
means the campus ingress blocked the request: preserve the login and ask the user
to connect to the campus network or university VPN. Ordinary 404s remain request
failures; HTTP 401 remains authentication expiry. Never replay a generation POST.

Host instructions precede prior context; agent requests also append a concise
protocol guide immediately before the current input. Both modes use the catalog's
`enableDeepThink` capability and selected thinking flag, and force `netGo: false`.
There is no search preflight/tool; historical citations remain readable.

SSE supports incremental UTF-8, CR/LF/CRLF, comments and multiline data with bounded
event sizes. Reasoning and answer deltas stay separate. A model finish reason is
confirmed by `[DONE]`, a school `other` receipt, `isEnd`/`is_end`, or a finish reason at EOF for non-Azure providers. Azure accepts moderation-only
events and waits beyond `[DONE]` for the school `other` receipt with `answerGroupId`.
EOF before that receipt is interruption; an intervening save-error envelope fails
the turn. Non-Azure EOF without a finish reason is interruption. Malformed events fail visibly. Cancellation aborts local work without promising server rollback or
avoided billing. No automatic generation POST retry or stream reconnection occurs.

The server's `chatInfo` ceiling is 900,000 UTF-16 characters, including the recovery
envelope; it does not limit `messages`. Attachment-only prompts use `请分析所附内容。`.
The official frontend's `messageRound` window is not applied. Known model windows
follow the updated reference: GPT-6.x 1,050,000, Kimi 1,024,000, DeepSeek/GLM/Qwen
524,288 tokens. Unknown deployments retain the configurable 256k fallback.
Compaction keeps original records on the server. A V2 `longContextTokenThreshold`
is a billing threshold, never an input cap. History JSON reads retain a 64 MiB
resource bound rather than the previous 2 MiB ceiling.

The external `genaiapi.shanghaitech.edu.cn` gateway is a separate, API-key-authenticated
contract. IDS credentials and `isWeb: 1` keys must not be reused there; model aliases
and native tool protocols also differ. TechPie's IDS-backed conversations continue
through `/htk/` and the school's history API. No silent gateway migration occurs.

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
canonical validated CDN URLs in the turn record and tool receipts. For inference,
fetch the active image selection without credentials and put base64 image content
blocks only in `messages`, before the tool guide. Do not put bytes in `chatInfo`
or the top-level image fields: those fields can fail server persistence after
inference succeeds. Historical image-field extensions are not reliable vision
input. Downloads are cancellable and bounded to 30 seconds, 10 MiB per image and
25 MiB per request; failure stops before the chat POST. Reopening rebuilds this
request from server records without local image storage.

Chat, reasoning and tool images share the trusted-URL policy; external/data/file images
do not load automatically. Chat, gallery and viewer share explicit image actions and desktop right-click
menus; long-press does not open a menu. Copy/share capability varies by platform; Android
uses a non-exported cache FileProvider and iPad sharing needs source bounds.

Image dimensions must be positive integers. Presets are conveniences; the school
frontend's pixel range, experimental-size warning, four-reference count and
reference-byte ceilings are not imposed on generation. The selected service
validates model-specific constraints. References remain local until generation:
validated PNG/JPEG/WebP. One uses `imageBase64`, several use
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
