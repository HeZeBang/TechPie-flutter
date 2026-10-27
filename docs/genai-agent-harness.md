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

The school endpoint has no native tool calling. Each agent request injects the
mode instructions, enabled tool catalog and `CURRENT_REQUEST` into one system
message. A response must contain one complete frame with the current nonce:

```xml
<techpie-agent-call version="3" nonce="CURRENT_REQUEST_NONCE">
{"call_id":"unique_call","name":"get_semesters","arguments":{}}
</techpie-agent-call>
```

```xml
<techpie-agent-final version="3" nonce="CURRENT_REQUEST_NONCE">
{"text":"Answer, clarification question, or explanation of a blocker."}
</techpie-agent-final>
```

Only a complete current-nonce call passing schema validation executes. Partial
frames, copied historical calls and mixed/unmarked prose enter bounded correction.
Repair treats rejected output as untrusted data and uses a text-only request;
it must pass the same validation. Final text streams incrementally, but invalid
previews are cleared before repair. Provider reasoning is display data, never a
call. A valid final frame does not prove that the answer is factually correct.

Normal chat accepts ordinary streamed answers. Both modes share attachments,
context preparation and history recovery. Both disable upstream web search.

## Server records and recovery

The school persists `chatInfo` and the answer, not the supplied `messages` context.
Real exchanges therefore carry `<techpie-record version="2">` JSON in `chatInfo`.
Version 1 and legacy logs remain readable. The decoder strips only known upload
prefixes; it never searches arbitrary document text for embedded records.

Records retain input, turn/parent/step identity, mode, routing, attachments and
changed recovery data. The model ID comes from the server row; defaults and
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

History sorts by logical last message, excluding compaction housekeeping, not by
last open. Renames persist with the next real message. Account/chat changes
invalidate late reads and execution callbacks.

## Tools and side effects

Campus adapters expose time, semesters, weekly timetable, assignments, court
reservation and image generation. `inspect_image` is runner-owned and read-only.
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
scope, new user messages start another, and revisions need fresh confirmation.
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
context grows again. Original user records and tool results outrank assistant
answers. Failed extraction falls back to bounded original excerpts. Original
server records remain intact and fresh instances recover the same boundaries.
