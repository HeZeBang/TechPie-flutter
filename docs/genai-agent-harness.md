# GenAI chat and campus agent

The workspace uses the school GenAI conversation API as its durable history.
TechPie retains only transient UI/execution state; there is no local conversation
database, archive migration, background save queue, or competing server-copy view.
Credentials still use the existing secure session store. Campus services continue
to obtain IDS/CpDaily identity through TechPie's existing binding services.

## Components

| Component | Responsibility |
| --- | --- |
| `genai_workspace_controller.dart` | Current chat, attachments, modes, cancellation and account ownership |
| `genai_remote_history.dart` | One server-history projection for display, export and model evidence |
| `genai_agent_runner.dart` | Bounded sequential tool loop, validation, confirmation and duplicate prevention |
| `genai_repository.dart` | Authenticated API operations, context preparation and read-back confirmation |
| `genai_context_compactor.dart` | Source-attributed memory, context budgets and reusable boundaries |
| `genai_agent_protocol.dart`, `genai_remote_record.dart` | Live decision framing and portable history records |
| `techpie_genai_tools.dart` | Adapters to existing TechPie services; no parallel campus login implementation |

Application paths are under `lib/features/genai/application`; protocols are in
`domain`. `GenAiConversationArchive` is an immutable export/view DTO, not a store.

## Live agent protocol

Native `tools` are unavailable on this school endpoint. Each agent request puts
current mode instructions, the enabled tool catalog and a fresh nonce in the first
system message. A complete response must be one of:

```xml
<techpie-agent-call version="3" nonce="CURRENT_REQUEST_NONCE">
{"call_id":"unique_call","name":"get_semesters","arguments":{}}
</techpie-agent-call>
```

```xml
<techpie-agent-final version="3" nonce="CURRENT_REQUEST_NONCE">
{"text":"The answer, clarification question, or explanation of a blocker."}
</techpie-agent-final>
```

Only a complete current-nonce call passing schema validation can reach execution.
Partial/truncated responses, native tool syntax, copied historical calls, mixed
prose and unmarked answers enter bounded correction; they never execute tools.
There is no phrase detector for “I'll check”. A final is an explicit termination,
not a semantic guarantee that the model answered correctly. Current campus facts
must be grounded in tool observations. Thinking is display data, never executable. Final JSON text is decoded incrementally
for display, with no tool execution before whole-frame validation. Invalid previews
are cleared before a bounded repair. Invalid framing is corrected in a text-only
step containing the rejected output as labelled, untrusted candidate data. The
candidate never executes directly; the same current-nonce parser and tool-schema
checks still apply. This avoids repeatedly invoking a vision route just to fix
syntax. Each request injects the protocol and `CURRENT_REQUEST` (active task,
image catalog and any rejected candidate) in its system message. These controls
are reconstructed for inference, not persisted. The saved `step_id` is also the
current call nonce. Repair continues the active task using completed results.

Normal chat accepts ordinary streamed answers. Both modes share the repository,
context builder, attachments and reconstructed source history. Web search is disabled in both modes; old saved citations remain readable.

## Portable records and quota

The school persists `chatInfo` and the answer, not the supplied `messages` context.
The decoder strips only the known school upload-label prefix before parsing records;
it never scans arbitrary document text for embedded records.
Actual exchanges therefore put a versioned `<techpie-record version="2">` JSON
record in `chatInfo`. The record contains the current input, step ID, turn identity,
mode, model routing and changed recovery data. The model ID comes from the
server row; its root routing ID is retained because the server does not return it.
Default values and duplicate identities are omitted. Version 1 records remain
readable; older clients need updating to interpret version 2. The original request
and file text are recorded on the first step; continuations refer to its turn ID. Parent IDs
make retries explicit. The latest appended path is displayed; other branches stay
on the server and still contribute conservative mutation protection.

Calls and results are paired by ID, not inferred merely from adjacent prose.
Original user records and tool receipts become model evidence. Attachments retain
remote identifiers, names, extracted text and image URLs. Successful image-tool
results join the visual catalog immediately. Each run starts with the newest image;
`inspect_image` selects an earlier catalog entry as the primary visual attachment.
The school endpoint may ignore both multi-image arrays and historical attachments,
so the runner sends the selected URL in both current-image fields. Before switching,
the model records labelled observations in its assistant call arguments. Those notes
are not promoted to tool facts; the tool receipt confirms selection only. This uses
ordinary agent steps in the same conversation, with no auxiliary chats or hidden
model calls. Reopened chats reconstruct the catalog from source attachments and
successful image receipts. New generated images become the selected image. The decoder constructs
ordered thinking/tool activity and the final answer. Version 2 and legacy server
logs remain readable through a separate compatibility decoder. Recovered records
never recreate approval dialogs or execute tools. Markers indicate structure,
not cryptographic proof of authorship.

There are no extra model calls just to save a receipt or checkpoint. Recovery
metadata rides on the next normal exchange. Compaction sends only a small prefix
boundary marker: summary answers are recovered directly from their existing
extraction rows by source hash, then validated against original quotes. Mutation
receipts are stored once as the next input. `effectKeys` associates that receipt
with normalized execution identities that cannot be inferred from raw tool
arguments; any other changed receipts use ledger deltas. Approval counts remain
explicit because declined or interrupted confirmations cannot be inferred from
successful results. Context estimates are small ready snapshots, allowing the
usage ring to recover without replaying a model request. Memory extraction
itself can use bounded model calls in the same group.
Renaming is draft metadata until the next real message, which the UI explains.

Opening and continuing always read server history. An absent completed turn
blocks automatic continuation instead of silently dropping it or replaying the
POST. Explicitly stopped or interrupted output is carried as inert history on the
next real request, preserving partial output without replaying the old generation. Checking synchronization is read-only. History labels and ordering are
derived from logical exchanges, excluding compaction housekeeping. Export uses
the same projection as reopening. Account or conversation changes invalidate late
reads and execution callbacks.

## Tools and safety

Available campus adapters: `get_current_time`, `get_semesters`,
`get_week_schedule`, `get_assignments`, `reserve_court`, `generate_image`,
and the runner-owned read-only `inspect_image`.
Documents, uploaded images, and successful generated-image receipts supply context
across tool calls, follow-ups, and server-only recovery. Service failures return typed
results; private service exceptions and credentials never enter model output.

Reservations and paid image generation require a concrete host-prepared proposal
and explicit user confirmation. Reservation limits, argument validation, identity
checks and pre-dispatch availability checks remain enforced in code. No model
prompt or historical approval grants permission. Reservation proposals remain limited to one confirmation per logical
user request and retain physical court/time-slot identity across messages.
Image operations use a host-created task scope plus normalized prompt, model,
resolution, and quality. Retry branches preserve that scope; new user messages
start a new scope. Within a task, a different image revision gets its own explicit
confirmation, while an identical request reuses the earlier result. Declining
an image stops further image proposals until a new user message, including after
recovery. Earlier unknown outcomes are shown as warnings on new confirmations;
they do not lock the entire image tool. The bounded agent loop still limits work.


Before an irreversible effect, the repository verifies that its model proposal
is visible in remote history. This barrier uses GET requests, never a repeated
model POST. If the proposal is not visible, execution fails closed. A result that
has not reached the next saved exchange remains unknown after a crash. Unknown
mutations are not automatically repeated; verify the underlying service status.
Completed and denied receipts suppress duplicates within that action scope.
An unknown outcome must never be copied onto unrelated actions or treated as
evidence of an upstream task lock. Old reused receipts are not new dispatches.
Exactly-once execution and cross-device mutual exclusion require upstream support and are not claimed here.

Limits bound model rounds, correction attempts, output size, tool deadlines and
whole-run duration. Account changes and cancellation are checked after every
asynchronous boundary. A late result cannot populate a different account/chat.

## Context

The default model profile is 256k, with reserved output and safety headroom. There
is no assumed 16k latest-message ceiling. Counts are conservative estimates, not
provider billing tokens: ASCII is estimated at two characters per token and
non-ASCII scalars individually. Gateway/body limits and model-specific tokenizers
remain distinct from this policy. All metadata sent on the wire is budgeted too.

Compaction uses a trigger/target gap (200k / 136k by default), keeps whole exchanges
and preserves original server records. A checkpoint identifies a covered prefix
and validates it against source/model identity. Subsequent requests retrieve
relevant evidence and reuse the boundary until effective context grows again.
User records and tool observations outrank assistant answers. Failed extraction
falls back to bounded original excerpts. The saved checkpoint is piggybacked onto
the normal request, so a fresh installation can reuse it without local storage.

## Verification

Tests use synthetic transports and data. Keep coverage for strict framing,
truncated streams, approval/cancellation races, unknown mutations, account changes,
fresh-instance recovery, attachments across modes, branching and checkpoint reuse.
Storage batching/migration tests were removed with the obsolete store.

Load the repository environment with the upstream Flutter SDK, then run:

```sh
flutter analyze --no-pub
flutter test --no-pub test/genai
flutter test --no-pub
```

The full debug fixture (`lib/main.dart`, `TECHPI_DEBUG_FIXTURE=true`) uses the same
runtime against an in-memory fake server. It exercises UI and wire recovery
without campus calls. Reloading that demo resets the fake server and login; real
cross-device persistence must additionally be checked against school history.

Older clients could assign fallback IDs to document-prefixed records. Recovery
reconstructs those IDs from the original server row sequence and aliases them to
the canonical exchanges, ignoring stale interrupted snapshots of those same rows.
Unrelated missing parents still produce an explicit history gap.
