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
| `application/genai_agent_runner.dart` | Bounded sequential loop, validation, confirmation and duplicate prevention |
| `application/genai_repository.dart` | Authenticated requests, context preparation and read-back confirmation |
| `application/genai_context_compactor.dart` | Source-attributed memory, budgets and reusable prefix boundaries |
| `domain/genai_agent_protocol.dart`, `genai_remote_record.dart` | Live decision framing and portable records |
| `application/techpie_genai_tools.dart` | Adapters to existing TechPie services |

## Agent protocol

The school endpoint has no native tool calling. The leading system message contains
identity and available tool schemas. A concise system guide is the last `messages`
entry, immediately before the gateway appends the current `chatInfo` input. The
active task (on continuation), image references and rejected candidate are transient
step data. Both guide and data count toward the budget but are never archived or
summarized. The original request is not duplicated on the first step.

Version 4 uses one current-nonce frame. Tool arguments remain JSON; final answers
are ordinary Markdown and stream without JSON escaping:

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

The host derives new call IDs from the step nonce. Version 3 calls/finals remain
readable. The decoder accepts harmless whitespace, attribute order/quote variation
and one outer Markdown fence, but never extracts calls from prose, accepts stale
nonces, repairs argument values or executes foreign harness syntax. Schema checks
and confirmation remain mandatory.

Malformed output receives a specific validation error and a bounded repair request
with the active task and completed results. Foreign tokenizer control delimiters
are neutralized only in the rejected candidate. Repair omits images and can request
`inspect_image` again when needed. Consecutive errors reset after a valid decision;
repair does not consume the valid-decision budget. The overall deadline still bounds
the run. Truncated/failed streams never authorize tools. Rejected previews are cleared.

Model history contains user input, final answers and compact inert call/result pairs
in `techpie-history`; it excludes reasoning, rejected candidates and protocol-repair
feedback. Tool arguments, results, attachments and original user evidence remain
available for compaction and recall. Server records keep recovery metadata separately;
reconstructed turn boundaries prevent resuming old interrupted tasks.

Normal chat accepts ordinary streamed answers. Both modes share attachments,
context preparation and history recovery. Both disable upstream web search.

## Server records and recovery

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
last open. Renames persist with the next real message. Account/chat changes
invalidate late reads and execution callbacks.

## Tools and side effects

Campus adapters expose time, semesters, weekly timetable, assignments, court
reservation and image generation. `inspect_image` is runner-owned and read-only.
The catalog is rebuilt each step: image generation requires an available model,
and inspection requires an image in the conversation. Thinking is a provider setting,
not a separate behavioral prompt. Both chat and agent use the context policy's
output reserve (4096 tokens by default), unless the request explicitly overrides it.
Timetable tools reuse `ScheduleService` data verified for the current campus
account and selected semester. Unverified caches or explicit refresh requests use
the normal service first. Late responses from another account/selection cannot
establish ownership. Network failure and unverified ownership remain distinct.

Reservations and paid image generation require a host-prepared proposal and
explicit confirmation. Validation, identity checks, reservation limits and
pre-dispatch availability checks run in code. Prompts and historical approvals
cannot grant permission. Court/time-slot identity survives later messages, with
one reservation confirmation per logical request. Image identity combines a
host-created task scope and normalized generation parameters: retries retain the
scope; new user messages and explicit edit-and-resend start a fresh approval scope.
Edits carry completed and uncertain external outcomes into the replacement record;
old denials do not block new confirmation. Deleting text does not undo external actions.
Declining an image blocks further proposals until the next user message.

Before dispatch, a GET read-back barrier verifies that the proposal is saved.
Missing proposals fail closed. Unknown outcomes are not automatically repeated;
check the underlying service. They warn on subsequent image confirmations without
blocking unrelated actions. Completed/denied receipts suppress scoped duplicates.
Exactly-once execution and cross-device locking require upstream support and are
not guaranteed. Model rounds, repairs, outputs, tool deadlines and total runtime
are bounded. Cancellation and identity are checked across asynchronous boundaries.

## Images and context

Uploaded images and successful generation receipts build a recoverable catalog.
Each run starts with the newest image; `inspect_image` selects an earlier entry.
The school endpoint does not reliably honor historical/multiple visual inputs,
so selection sends one known URL in both current-image fields. Comparison notes
remain assistant observations, never tool facts. Inspection uses ordinary steps
in the same conversation, without auxiliary chats. See the [API contract](genai-api-contract.md)
for upload validation and trusted image URLs.

The default context profile is 256k with output/safety reserves; there is no assumed
16k latest-input ceiling. Estimates include attachments and wire metadata, and are
not billing counts. Compaction uses a trigger/target gap (200k/136k), whole exchanges
and source-validated prefix boundaries. Boundaries are reused until effective
context grows again. Recall of user records and action outcomes uses original user
messages and tool results rather than assistant recollections; user assertions do
not thereby become objective facts. These interpretation rules are injected once,
not repeated in every memory item. Failed extraction falls back to bounded original excerpts. Original
server records remain intact and fresh instances recover the same boundaries.

## Verification

Keep deterministic coverage for parsing, streaming, ownership, mutation approval,
and recovery. Evaluate model adherence separately on the school service: multi-step
tools, image comparison, and corrected-record recall after compaction and reopening.
Mocked tests do not establish model behavior or service availability.

Design references: [Pi's message transformation pipeline](https://github.com/badlogic/pi-mono/blob/main/packages/agent/README.md#message-flow),
[Anthropic context engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)
and [long-context prompting](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices#long-context-prompting).
These guide the design; live school-model checks are still needed to evaluate adherence.
