# TechPie campus agent

The GenAI workspace has an **校园工具** toggle beside **深度思考** in the main chat
composer. Enable it to use campus tools in the same conversation, with the selected
model, shared draft and existing transcript. In narrow layouts, inactive controls
collapse into the + menu, with campus tools collapsing before thinking. Tool progress, results and approval
cards appear inline. Successfully generated images appear directly beneath the
tool result; tap an image to enlarge it. The harness shares the verified GenAI
session and TechPie's existing service instances; it never takes a token from model output.

Campus tools, deep thinking, web search and document/image attachments can be used
together. Turning agent mode off preserves attachments and the transcript and allows
ordinary chat to continue. A completed agent answer remains available
as context for ordinary chat, and switching back preserves the tool exchanges for
agent follow-ups. Changing modes invalidates late picker and media callbacks.

The chat follows streamed output while the reader is near the latest message.
Scrolling back pauses that behavior; **回到最新** resumes it. The stop button or
Escape cancels the active generation and preserves any draft already in the
composer. A stopped answer remains visibly incomplete. Stopping does not prove a
remote tool side effect was cancelled; existing unknown-outcome warnings and
mutation receipts still govern retries.

A compact context indicator sits beside the microphone. It shows a conservative
budget ring after preparation and a spinner while preparing or compacting.
The tooltip and details dialog provide numerical estimates.
Hover or focus reveals its full status, including compaction chunk progress;
tapping opens the estimate explanation. This is separate from account usage and
billing. These transient estimates are not stored as conversation evidence.

## Platform boundary

The supplied ShanghaiTech reference, sections 9–11, reports that
`/htk/chat/start/chat` strips or rejects native `tools` definitions. The harness
therefore uses a system prompt and a strict text protocol over the existing SSE
transport. Requests use only `system`, `user`, and `assistant` roles, string content,
`messages: []` when empty, and `stream: true`. Every model turn in a task uses the
same `chatGroupId`; the client supplies its own bounded history.

Every generation request begins `messages` with exactly one `role: "system"`
message. It is rebuilt from the current campus-tools, thinking, web-search, and
attachment capabilities. Agent requests append the current nonce protocol and
only the currently enabled tool catalog to that same system message. Ordinary
chat explicitly disables campus tools. These instructions are not stored as
conversation turns or copied from remote logs, so toggles, retries, and reopened
chats cannot preserve stale capability grants. The separate `thinking` and
`netGo` flags still control backend behavior; prompt text does not replace them.

Section 9 describes the server history endpoint as an asynchronous, append-only
log of model request/response pairs. It is not the model context or a canonical
conversation tree: retries can leave duplicate branches and the server cannot
edit individual turns. TechPie therefore owns logical chat turns, tool receipts
and active branches in a versioned local archive. Reopening a locally saved
conversation uses that archive before consulting server logs. Titles can be
renamed locally. The readable Markdown export includes visible prompts, answers,
attachments and tool outcomes; it omits system instructions, execution nonces and
internal bookkeeping. Synthetic images are labeled as local test images instead
of being exported as misleading external image URLs.

The reference's early 16k-context claim conflicts with its later DeepSeek and Kimi
stress tests. These observations are not advertised as universal model guarantees.
The current catalog supplies model identifiers; the UI preserves an explicitly
selected model, labels paid/unknown-price models, and does not assume an unavailable
alias exists. Thinking, when selected and supported by the existing model metadata,
stays enabled for every model step. Streamed reasoning is displayed in the chronological activity view
and archived, never parsed as an action or fed back as assistant context.

When web search is enabled, the host injects a run-scoped `web_search(query)`
capability into both the advertised catalog and the execution registry. The model
may skip it, search once, or refine a query after inspecting results. All agent
model requests use `netGo: false`; the search tool alone calls `/net/search` with
an explicit query and empty history, without attachment fields. A bounded set of
source URLs/snippets returns as untrusted typed tool data. Failures are structured
tool results, allowing the model to recover or explain the limitation. The same
run/tool time limits, cancellation and account guards apply. Disabling search
removes execution permission, not merely its button.

Document and image uploads also work in agent mode through the existing school
RAG and vision fields (`fileIds`, `imageUrls`). These are supplied on every model
step and later agent turns within the same logical conversation, including restored
chats. Ordinary chat uses the same attachment context. New chats and history gaps
clear it; retries are limited to the latest turn. Reading capability
still depends on the selected school model and backend; enabling tools cannot add
vision to a text-only model. Uploaded content is untrusted reference material,
never permission to execute actions. The search tool does not automatically receive
attachments or conversation history; models are instructed to use public queries.

Agent reasoning (the provider's `reasoning_content`, never fabricated), tool states,
and searches are recorded in chronological order in a collapsible process view.
Contiguous reasoning chunks are coalesced by model step, and tool states update in
place. These display records are separate from the nonce-aware executable transcript.
Approvals remain visible outside the collapsed view. Saved chats preserve the
ordered records; older archives without this information explicitly show that the
original step order is unavailable instead of inventing one.

Live Kimi-K3 verification on 2026-10-23 exposed two format deviations: native
`tools/call` special tokens, and a copied `techpie-agent-history` call record.
Neither is executable. The live response decoder now requests a bounded protocol
repair instead of treating these as a successful final answer. Quoted examples
remain inert, as do all archived records; only a fresh, validated current-nonce
call can reach the tool registry. Search relevance is controlled by the upstream
service: successful responses may contain unrelated pages, so the model must
inspect sources and avoid claiming an answer the returned evidence cannot support.

## Components and extension points

- `domain/genai_agent_contract.dart`: immutable calls and results, closed tool
  registry, argument schemas, prepared actions and approval details.
- `domain/genai_agent_protocol.dart`: exact versioned frames, current-request
  nonce validation, typed inert transcript entries and read-only legacy decoding.
- `application/genai_agent_runner.dart`: model/tool feedback loop, bounded history,
  cancellation, error recovery, approvals and mutation ledger.
- `application/techpie_genai_tools.dart`: adapters for existing TechPie services.
- `application/genai_conversation_turn.dart` and `genai_conversation_store.dart`:
  versioned logical turns, tool cards, model/mode state and mutation receipts.
- `data/secure_genai_conversation_store.dart`: account-scoped local storage,
  serialized writes, interrupted-index recovery and durable deletion intents/tombstones.
- `application/genai_transcript_export.dart`: readable user/task/tool summaries
  with canonical image links, excluding execution frames and internal identifiers.
- `application/genai_legacy_conversation_import.dart`: display-only reconstruction
  of old server model-step logs; it cannot restore execution authority.
- `application/genai_workspace_controller.dart`: shared chat/agent transcript, mode
  selection, account scope, pending approvals and runner lifecycle.
- `presentation/genai_workspace.dart`: main chat toggle, composer and inline agent
  transcript, using the same model selector and stop/new-conversation controls.
- `presentation/genai_agent_widgets.dart`: expandable tool results and explicit
  approval/rejection cards.

A live assistant call must occupy the complete response and carry the random
nonce supplied for that model request. For example:

```xml
<techpie-agent-call version="2" nonce="HOST_GENERATED_NONCE">
{"call_id":"schedule_1","name":"get_week_schedule","arguments":{"week":4}}
</techpie-agent-call>
```

Each model step gets a fresh nonce. The host validates the completed response,
nonce, tool name and argument schema before dispatch. Ordinary JSON, Markdown
`tool_call` examples and quoted frames do not execute. A stale or malformed live
frame is rejected; interrupted, truncated or filtered responses never execute.
This framing distinguishes protocol records from ordinary text, but is not a
security boundary against a model that sees the system prompt: closed tools,
argument validation, account guards and explicit mutation approvals remain
required.

Tool feedback uses a matching `techpie-agent-result` frame in a normal user
message. Prior tool calls/results are stored as typed records and serialized as
inert `techpie-agent-history` context without an execution nonce. Final answers
remain ordinary text. Read-only legacy decoding is separate from the live parser;
reading an old record can never authorize a call or recreate a pending approval.

To add a tool, register a `GenAiAgentTool` with a closed object schema and a
`prepare` callback. Preparation may read and validate but must not mutate. Return a
`GenAiAgentPreparedTool` containing an execution closure. Mutations set
`requiresApproval`, a human-readable summary/details and a normalized `effectKey`.
Call `context.checkActive()` after awaits and immediately before dispatch; propagate
`context.cancellation` into cancellable network calls. Give model feedback only
sanitized, bounded data and application-authored errors, never exception dumps,
cookies, credentials or contacts.

## Initial tools

| Tool | Existing implementation | Behavior |
| --- | --- | --- |
| `get_current_time` | Device clock | UTC, device time and Shanghai campus time; no network. |
| `get_semesters` | `ScheduleService` | Lists academic terms and selected term with freshness/provenance information. |
| `get_week_schedule` | `ScheduleService`, custom courses | Teaching-week schedule; validates semester/week and does not silently switch the app's selected semester. |
| `get_assignments` | `AssignmentService` | Visible assignments/exams, due-date and completion filters; respects hidden/completed overrides. |
| `reserve_court` | `OaGymService` | Read availability, then prepare one concrete slot/court booking. Rechecks availability and saved booking profile after approval. |
| `generate_image` | Existing GenAI repository | One PNG using discovered image models; defaults to low quality at 1024×1024, supports validated custom dimensions and shows quota implications. Successful images appear directly in chat with tap-to-enlarge and are also available in normal image history. |

The tool schemas are the authoritative argument reference. Academic reads fail
closed when ownership/freshness cannot be established. Missing bindings, missing
booking contact details, unsupported refreshes and unavailable court services are
reported as errors with a next step; they are never represented as empty success.
A booking uses the contact profile already saved in TechPie, without sending those
contact fields to the model. The school availability API does not provide a price;
approval explicitly says the price is unavailable instead of inventing one.

## Lifecycle, limits and side effects

Default limits are 12 model turns, two recoverable protocol errors,
32,768 output characters and 6,000 tool-result characters. The run has a
10-minute deadline; ordinary tool work has a 60-second deadline. A host-owned prepared
action may request a longer execution timeout, bounded at six minutes, for image
generation. These are configurable client resource limits, not model token claims.
The repository now shares budgeted context compaction with ordinary chat. It
separates the latest-message budget from the full context window, preserving
the task goal, recent complete tool exchanges and source-checked memory while
retaining the full archive. User records and tool receipts take factual precedence;
one relevant older assistant artifact may be retained separately as unverified
material for revision. See [context compaction](genai-api-contract.md#context-compaction)
for accounting, checkpoint persistence, failure behavior and estimator limits.

Account/session changes cancel active work, clear the visible private transcript
and dismiss pending approvals. Archives remain isolated under their captured
account scope. The run also captures connected third-party identities, so changing
an assignment provider cannot mix accounts mid-task. Leaving the main chat cancels
active execution while retaining the saved conversation. The shared stop button
interrupts the run and keeps known tool outcomes, including uncertain outcomes
that must be checked before retrying. New conversation starts a fresh logical
conversation without deleting older archives.

Reopening a local archive restores tool cards, generated images, selected model,
mode and typed context. Previously active or awaiting-approval turns become
interrupted; no request, approval or tool executes automatically. The archive is
local to this installation and account scope; it is not a cross-device sync
service. Storage errors must remain visible instead of silently replacing a local
branch with the server's logging rows. A small write-ahead marker lets the next
operation complete an interrupted record/index update without discarding deletion
tombstones. Store instances share serialization within the running isolate; this
is not cross-process or cross-device locking. Malformed authoritative records or
indexes still report a storage error and preserve their original data.

Generated-image results and image history now retain canonical campus CDN URLs;
only the renderer resolves the active preview proxy. Answer and reasoning Markdown
share the same trusted-image policy; arbitrary external images never load automatically. Older local archives migrate
structured loopback/static image URLs in attachments, tool results and mutation
receipts, leaving literal user/assistant text unchanged.

When no local archive exists, adjacent matching call/result rows from older server
logs are grouped into inert historical tasks. Versioned same-chat compaction
rows are skipped before pairing, and protocol-repair feedback stays within its
original task. Recorded tool receipts remain source evidence for later questions
in both ordinary and agent modes, ahead of prior assistant answers. V1 code examples remain ordinary text
unless a matching receipt establishes a tool chain. Namespaced V2 records are
recognized explicitly. Missing/orphan results produce recovery notices and unknown
outcomes; typed inert records never authorize execution. Imported
server logs cannot recreate approvals or authoritative mutation receipts.
Unreadable server rows remain explicit gaps in their original positions. A gap
breaks tool-chain reconstruction, cannot be retried as a user request, and is
exported as a missing-history notice rather than fabricated message content.

A session deletion records durable intent before the remote request. While the
remote outcome is unresolved, that session stays hidden and unwritable even after
restart. A confirmed remote rejection can restore the retained local archive;
a confirmed deletion finalizes a tombstone. An ambiguous outcome is reported for
manual verification and never causes an automatic repeat of the remote DELETE.

Approved mutations are durably recorded as an uncertain outcome before dispatch,
using a normalized host-owned identity. A failed checkpoint prevents dispatch.
Completed, denied and unknown receipts are retained and restored with that local
conversation so retries do not repeat the same effect. A checkpoint after success
records its result. Deletion tombstones prevent queued saves from resurrecting a
removed conversation. Timeout/cancellation cannot prove that a server action was
rolled back; users must check records before trying again. OA booking POSTs are not
automatically replayed after authentication failure. This is duplicate protection
within a retained local conversation, not durable exactly-once delivery across
new conversations, deleted storage or devices. Remote services remain authoritative.

Tool data is untrusted input for the model. The harness has no arbitrary code,
shell, file-system or browser execution tool. UI approvals are generated from
validated prepared actions, not from text supplied by the model. User tasks and
relevant tool results are sent to the selected school model using the existing
GenAI service; the composer explains this data flow when agent mode is selected.

## Verification and demo

The full `lib/main.dart` app supports the existing debug fixture. The local demo
recognizes the harness system marker and provides deterministic tool calls through
the real runner and adapters. It is explicitly labeled local demo, not a live model
benchmark. Image checks use the bundled `assets/genai/demo-campus.png` scene
(a campus library, pond and red bicycle), labelled “本地测试图片”. Use this decoded
picture in chat, zoom and image-history checks; an icon or empty panel is not a
successful image-rendering check. The fixture's source prompt is recorded in
`assets/genai/README.md`.

Example manual checks:

1. Connect the local demo account, enable **校园工具** beside **深度思考**, and ask
   `整理本周课表和作业`. Verify four inline read-tool results and the final response.
   Disable the toggle, send an ordinary chat message, and enable it again to
   confirm the same conversation remains visible.
2. Ask `生成一张校园图片`. Reject once and verify no image appears. Start a new conversation,
   ask again, approve, and verify the image appears directly in chat. Tap it to
   enlarge, then inspect the normal image history.
3. Ask `预约羽毛球场`. The local demo must explain that real court availability is
   unavailable and must not submit a reservation.
4. Stop while awaiting approval, change an account, start a new conversation, or
   leave the page. Confirm no pending action executes later.
5. Enable search and thinking with campus tools; verify citations, reasoning and tool results. Keep campus tools enabled, add a document and image, and verify
   both remain attached when sending an agent request. Check the toggle and composer
   at a narrow phone width.
6. Reopen a completed tool conversation and verify its original prompt, tool cards,
   image previews and final answer remain in order. The debug demo deliberately
   uses in-memory storage, so full reload clears its conversations; automatic
   shared-store/secure-storage tests cover process restart. The normal runtime
   persists through secure storage and needs a separate device restart check.
   Reopen an interrupted task and confirm no pending approval or network action
   resumes.
7. Ask for a Markdown `tool_call` example or quote a stale V2 frame. Confirm it is
   displayed as ordinary text and never invokes a tool.

The preview environment's real-login mode still has seeded campus services. Its
academic tools refuse to present seeded coursework as real-account data. Real
service calls require the ordinary TechPie service configuration and bindings.
Unit/widget tests use synthetic data for protocol errors, bounded loops, approvals,
duplicate actions, account races, timeout and late dispatch; no tests spend school
quota or reserve real courts.

Run the automated regressions with `flutter test --no-pub test/genai` and the
loopback contract checks with
`python3 -m unittest discover -s test/tool -p genai_preview_proxy_test.py`.
