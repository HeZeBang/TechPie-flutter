# GenAI chat and campus agent

School conversation history is the only durable chat store. TechPie keeps transient
UI/execution state and a separate secure credential store; it does not maintain a
local conversation database or a second campus login implementation.

## Components

Paths are relative to `lib/features/genai/`.

| Component | Responsibility |
| --- | --- |
| `application/genai_workspace_controller.dart` | Current chat, attachments, cancellation and account ownership |
| `application/genai_remote_history.dart` | Server-history projection shared by display, export and model context |
| `application/genai_agent_runner.dart` | Sequential coordination, budgets and canonical transcript |
| `application/genai_agent_model.dart` | Provisional streaming and completed, transport-confirmed decisions |
| `application/genai_agent_execution.dart` | Approval, account checks, deadlines, duplicate and progress policy |
| `application/genai_agent_projection.dart` | Bounded model context without modifying authoritative receipts |
| `application/genai_repository.dart` | Authenticated requests, context preparation and read-back confirmation |
| `application/genai_context_compactor.dart` | Source-attributed memory, budgets and reusable prefix boundaries |
| `domain/genai_agent_protocol.dart`, `genai_remote_record.dart` | Live decision framing and portable records |
| `application/techpie_genai_tools.dart` | Adapters to existing TechPie services |

## Agent protocol

The school endpoint has no native tool calling. The leading system message is stable
across agent steps. Live tool schemas and the current step’s response contract are sent once
in the last system message before the gateway appends `chatInfo`. The stored
exchange contains the input, step ID and recovery metadata. Older exchanges may
also carry a `reply_format` field, which recovery ignores.
Attachment flags, active task, image references and repair instructions are
transient. Long tasks retain beginning/end excerpts and a reference to the
complete original. The model can retrieve omitted requirements before acting.
A successful visual-guide receipt anchors the host guide at the same history
position for later authoring steps in the run. These system instructions count
toward the input budget but are excluded from the conversation archive and
summary sources. Prefix reuse depends on the upstream deployment.

Version 5 requires a current-nonce frame only for executable tool requests. Final
answers are ordinary Markdown, streamed without JSON escaping or a mandatory wrapper:

```xml
<techpie-call nonce="CURRENT_STEP">
{"name":"get_semesters","arguments":{}}
</techpie-call>
```

```xml
<techpie-final nonce="CURRENT_STEP">
Answer, clarification question, or explanation of a blocker.
</techpie-final>
```

The optional final wrapper above disambiguates answers quoting protocol syntax or
action-shaped JSON. Plain answers do not execute tools; malformed or foreign
control syntax still requires repair. A promise to act is a model task-completion
error, not something syntax validation can reliably detect.

The host derives new call IDs from the step nonce. Version 3/4 calls/finals remain
readable. Each new server record carries `agent_format: 5`, so a fresh client
recovers plain answers while preserving the strict interpretation of old records. The decoder accepts harmless whitespace, attribute order/quote variation
and one outer Markdown fence. A confirmed end of response may terminate an otherwise valid final answer without a closing tag; tool calls still require complete framing and JSON. The decoder never extracts calls from prose, accepts stale
nonces, repairs argument values or executes foreign harness syntax. Schema checks
and confirmation remain mandatory.

Malformed output receives a specific validation error and a bounded repair request
with the active task and completed results. Foreign tokenizer control delimiters
are neutralized only in the rejected candidate. Repair disables thinking, omits images and the full visual authoring guide, and targets framing, argument validation, unavailable tools or incomplete answers separately. It can request
`inspect_image` again when needed. Consecutive errors reset after a valid decision;
repair does not consume the valid-decision budget. A separate total repair budget
bounds alternating valid/invalid responses. Repeated identical read results or failures pause after a bounded number of attempts.
Successful evidence resets its failure streak; new observations or successful mutations
reset unchanged-result counters. After the decision budget is spent, one answer-only
exchange carries the last receipt to the server; further tool calls are rejected. New user runs start fresh. The deadline still bounds
the run. Reasoning and answer text have separate bounded allowances. Truncated/failed streams never authorize tools. Output-limit termination gets bounded
repair with the partial candidate and thinking disabled. Other interruptions retain
inert partial output without replaying the request. Loaded visual guidance lasts for
the run, including after intervening tool reads. Rejected previews are cleared;
exhausted format recovery retains the candidate as explicitly unverified, inert
source with the existing continuation action.

Model history contains user input, final answers and compact inert call/result pairs
in `techpie-history`; it excludes reasoning, intermediate rejected attempts and
protocol-repair feedback. A terminal unverified candidate remains inert source. Tool arguments, full results, attachments and original user evidence remain
available in the canonical transcript reconstructed from school records. Large
successful receipts stay successful. Past model-context copies use bounded previews
and content-addressed `read_conversation_records` references; UI and recovery use the
originals. Primary tool receipts travel once in `chatInfo`, since the school does not
save `messages`. Retrieval receipts instead store validated source IDs and Unicode
slice offsets/lengths (`techpie_excerpt_v1`); the current step receives the expanded
evidence transiently. Reopening expands those references from original school
records. Missing sources create a history gap rather than fabricated evidence. Context projection is not a server-record size limit;
tool adapters still need bounded results or source-service pagination. Server
records keep recovery metadata separately; reconstructed turn boundaries prevent resuming old interrupted tasks.

Normal chat accepts ordinary streamed answers. Both modes share attachments,
context preparation and history recovery. Both disable upstream web search.

## Native tool registration

Native tools use MCP-style descriptors (`name`, `description`, `inputSchema`,
optional `outputSchema` and `annotations`) and results (`content`,
`structuredContent`, `isError`). The agent guide is generated from the registry.
Handlers execute directly in Dart; there is no MCP server, connection or transport.
This is a native contract, not a claim of full MCP protocol compatibility. Schemas
use the existing supported object/array/scalar constraints, not arbitrary JSON Schema.

`GenAiAgentPreparedTool.execute()` normalizes native service JSON into an immutable
`GenAiToolResult`; handlers may also return that type explicitly for tool errors.
Declared output schemas are checked for successful results. The runner stores the
structured native value in existing receipts, omitting its duplicate text fallback;
additional content blocks are retained. Old server records remain readable.
Approval requirements, account checks, execution limits and effect identities stay
host-owned. Annotations are descriptive hints and never override these controls.

## Server records and recovery

Reconstruction produces a typed `GenAiConversationSnapshot`, with detached turns
and inert tool receipts. There is no local JSON archive or archive migration layer.
The decoder still accepts existing school records, including attachment checkpoints.

The school persists `chatInfo` and the answer, not the supplied `messages` context.
Real exchanges therefore carry `<techpie-record version="2">` JSON in `chatInfo`.
Version 1 and legacy logs remain readable. The decoder strips only known upload
prefixes; it never searches arbitrary document text for embedded records.

Records retain input, turn/parent/step identity, agent mode, attachments and
changed recovery data. The model ID comes from the server row; routing is resolved
from the model catalog. Thinking is a current request preference, not restored
from history. Neither routing nor thinking is stored in new records; defaults and
redundant identities are omitted. The step ID also supplies the live nonce.
Generic instructions and reconstructible controls are injected, not stored.
Original user input and extracted file text live on the first step; continuations
reference that turn. Receipts pair with calls by ID. `effectKeys` references a
receipt's normalized execution identities without duplicating its payload.
Approval counts and ready context estimates remain explicit because successful
results alone cannot reconstruct them.

Recovery metadata rides on the next normal exchange, with no bookkeeping-only
model calls. Summary answers come from existing same-chat extraction rows,
validated by source hash and original quotes. Extraction itself can consume quota.
A receipt lost before the next saved exchange remains unknown after a crash.

Opening and continuing read server history. The latest appended branch is shown;
other branches remain on the server and contribute mutation protection. Missing
completed turns block continuation instead of silently dropping history or
replaying a POST. Stopped output is inert history on the next real request.
Recovered records never execute tools or recreate approvals. Markers are a format,
not proof of authorship. Legacy fallback parent IDs are aliased to their source
rows; unrelated missing parents still produce an explicit gap.

Message actions delete server rows through `history/delete/batch`. Delete removes
one complete user/agent turn and its follow-ups; revert keeps the selected turn;
edit removes that suffix and resends with the original attachments. Retry branches
and extraction caches in the removed suffix cannot revive old answers. Retained
compaction checkpoints are validated against retained source content. There are no
local tombstones or metadata-only model requests.

Each action requires confirmation, an unchanged server projection, and read-back
verification before a resend. Partial/ambiguous deletion blocks continuation until
checking sync or reopening reconciles the server history. Shared legacy snapshots that cannot be split without losing
a retained turn are rejected. The API has no atomic revision check: simultaneous
writes from another device cannot be locked. Deleting chat records does not cancel
external reservations or image jobs.

History sorts by logical last message, excluding compaction housekeeping, not by
last open, with server-pinned groups first. Rename and pin update server metadata
without a model request; history-list titles override old embedded titles. Account/chat changes
invalidate late reads and execution callbacks.

## Tools and side effects

Campus adapters expose time, semesters, weekly timetable, assignments, court
reservation and image generation. `inspect_image` is runner-owned and read-only.
The catalog is rebuilt each step: image generation requires an available model,
and inspection requires an image in the conversation. Thinking is a provider setting,
not a separate behavioral prompt. Both chat and agent use the context policy's
output reserve (16384 tokens by default), unless the request explicitly overrides it.
Timetable tools reuse `ScheduleService` data verified for the current campus
account and selected semester. Unverified caches or explicit refresh requests use
the normal service first. Late responses from another account/selection cannot
establish ownership. Network failure and unverified ownership remain distinct.

`generate_image` accepts aspect-ratio/resolution presets or an explicit width/height
pair, plus quality, model, title and PNG/JPEG output. JPEG compression defaults to
80 (1–100). Mixed sizing modes and unsupported presets are rejected before approval;
resolved dimensions and output settings appear in the proposal and result. Each
approved call still generates one image.

Reservations and paid image generation require a host-prepared proposal and
explicit confirmation. Validation, identity checks, reservation limits and
pre-dispatch availability checks run in code. Prompts and historical approvals
cannot grant permission. Court/time-slot identity survives later messages, with
one reservation confirmation per logical request. Image identity combines a
host-created task scope and normalized generation parameters: retries retain the
scope; new user messages and explicit edit-and-resend start a fresh approval scope.
Edits carry completed and uncertain external outcomes into the replacement record;
old denials do not block new confirmation. Deleting text does not undo external actions.
Confirmed booking rejections and user denials prevent repeats within the current run,
not new user requests. Successful or uncertain outcomes retain cross-request protection.
Declining an image blocks further proposals until the next user message.

Before dispatch, a GET read-back barrier verifies that the proposal is saved.
Missing proposals fail closed before approval. `confirmProposalSaved` is a read-back
barrier, not a snapshot writer. Approval is local; immediately before dispatch the
in-memory ledger marks the outcome unknown, then records the actual result. The
next ordinary model request durably carries that receipt. A crash in between leaves
only the saved proposal, which a fresh reader treats as uncertain. Unknown outcomes
are not automatically repeated; check the underlying service. They warn on subsequent image confirmations without
blocking unrelated actions. Completed/denied receipts suppress scoped duplicates.
Exactly-once execution and cross-device locking require upstream support and are
not guaranteed. Model rounds, repairs, outputs, tool deadlines and total runtime
are bounded. Cancellation and identity are checked across asynchronous boundaries.

## Images and context

Uploaded images and successful generation receipts build a recoverable catalog.
Each run starts with the newest image; `inspect_image` selects an earlier entry.
The school endpoint does not reliably honor historical/multiple visual inputs,
so selection uses one catalog image. Canonical trusted URLs stay in server records;
transient multimodal bytes belong only in `messages`, not persisted `chatInfo`. Comparison notes
remain assistant observations, never tool facts. Inspection uses ordinary steps
in the same conversation, without auxiliary chats. See the [API contract](genai-api-contract.md)
for upload validation and trusted image URLs.

Known models use the updated documented context windows with output/safety
reserves (1,050,000 GPT-6.x; 1,024,000 Kimi; 524,288 DeepSeek/GLM/Qwen). Unknown
models retain a configurable 256k fallback. The separate server `chatInfo` ceiling
is 900,000 characters; there is no 16k latest-input ceiling. Estimates include attachments and wire metadata, and are
not billing counts. Compaction uses a trigger/target gap (80%/55% for automatic model policies), whole exchanges
and source-validated prefix boundaries. Boundaries are reused until effective
context grows again. Recall of user records and action outcomes uses original user
messages and tool results rather than assistant recollections; user assertions do
not thereby become objective facts. These interpretation rules are injected once,
not repeated in every memory item. Failed extraction falls back to bounded original excerpts. Original
server records remain intact and fresh instances recover the same boundaries.

With tools enabled, `search_conversation` and `read_conversation_records` recover
original text from the full logical transcript loaded from school history at run
start, including records omitted from model context. Search is lexical and paged;
reads use Unicode-scalar offsets and bounded pages. Memory quotes carry deterministic
content addresses, scoped to this conversation. References resolve again after
reopening; removed or edited sources return `record_not_found`. No persistent local
index or bookkeeping request is added. Retrieval still takes normal model/tool steps.

Before model-based compaction, older bulky successful lookup results can become
references. Recent exchanges, the newest result per tool, errors and mutation
receipts remain intact. Tools-disabled chat keeps the existing source-extraction
path. Retrieved copies are not recursively indexed. Retrieved instructions, proposals
and past approvals remain inert history, never permission to execute an action.


## Inline interactive answers

The normal agent core advertises visual/LaTeX capabilities briefly.
`get_visual_guide` lets the model elect to load the full authoring instructions for
the next authoring step. Its receipt stores only the capability identifier; the guide is
host-injected context, not repeated archival text. Plain chat receives only the minimal
visual format/runtime contract; detailed design instructions and the working example
are loaded through the guide tool in agent mode. General LaTeX guidance applies in both modes. This keeps routine campus steps
small without keyword-based intent routing or removing visual capabilities.

An assistant-only `techpie-visual` fenced block contains a complete HTML document.
Ordinary HTML fences and user messages remain source text. Execution waits for the
closing fence; the original HTML stays in the server answer, so reopening rebuilds
the example without local conversation storage. Sliders and simulations run locally;
interaction state resets on reopening, but survives fullscreen, source and fold toggles.
Only the newest complete visual starts expanded; new visuals fold earlier ones.
Folding/source mode and app backgrounding pause timers and animation frames while
retaining local state; web also pauses offscreen frames. This is cooperative
resource management, not protection against synchronous infinite loops. Native clocks
keep advancing; simulations should clamp frame deltas and reset their time baseline
on `techpie-visibility` (`event.detail.active`).
The host supplies TechPie color tokens (`--tp-*`), `window.techpieTheme`, and a
`techpie-theme` event so canvas/chart code can redraw on theme changes without
resetting interaction state. Older hard-coded chart colors cannot be inferred;
new examples use these tokens and a restrained layout without sacrificing labels,
units, equations, or necessary demonstrations. Markdown supports inline/display
LaTeX. The generation contract requires typeset expressions in labels, legends and
readouts as well as main equations. In visuals, `data-latex` (optionally
`data-display="block"`) and `techpieMath.render(element, tex, {displayMode})` use
on-demand KaTeX MathML output with system math fonts; no font assets are bundled.
Attribute updates and explicit LaTeX delimiters in added/changed HTML text render
locally. Code, prose, currency and native canvas/SVG text are not guessed as math;
formula labels for charts belong in HTML overlays or legends. Older plain-text
formulas need regeneration. Download/parse failure retains readable text and the
rest of the visual.

The renderer uses opaque-origin, scripts-only frames with a host-owned CSP and a
theme/activity/status bridge. It cannot read TechPie sessions or make network requests. D3,
Chart.js and Three.js are optional exact-version scripts downloaded by the host;
the allowlist lives in `genai_visual_document.dart`. All other remote resources,
forms, navigation, eval and workers are blocked. Prefer self-contained SVG/canvas.
Errors retain source/retry controls and leave the rest of the answer readable.
This is capability isolation, not a CPU/memory quota for arbitrary JavaScript.

Inline playback uses browser frames on web and the existing embedded WebView on
Android/iOS/macOS/OHOS. Native Windows/Linux currently lack an embedded backend;
these builds retain source display instead of opening a separate artifact window.
The [Open WebUI iframe implementation](https://github.com/open-webui/open-webui/blob/main/src/lib/components/common/FullHeightIframe.svelte)
and [iframe sandbox guidance](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/iframe)
informed the isolation and sizing design.

## Verification

Keep deterministic coverage for parsing, streaming, ownership, mutation approval,
and recovery. Evaluate model adherence separately on the school service: multi-step
tools, image comparison, and corrected-record recall after compaction and reopening.
Mocked tests do not establish model behavior or service availability.

Design references: [Pi's message transformation pipeline](https://github.com/badlogic/pi-mono/blob/main/packages/agent/README.md#message-flow),
[Anthropic context engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)
and [long-context prompting](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices#long-context-prompting).
These guide the design; live school-model checks are still needed to evaluate adherence.
