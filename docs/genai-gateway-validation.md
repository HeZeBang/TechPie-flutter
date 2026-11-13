# GenAI gateway fixes and acceptance

On 2026-10-28, this branch incorporated local upstream `b517039` and its native-tool and empty-response retry updates. The handoff reference is `/proj/GenAI2OpenAI/docs/TechPie工具链问题交接.md`.

## Gateway behavior

- Consume the final text delta before processing the finish reason. Preserve `length` and `content_filter`; report an error for EOF without a finish marker or DONE.
- Parse standard tool objects, nested `function` objects, top-level arrays, trailing links, multiple JSON objects and multiple XML blocks. Preserve every call and existing ID.
- Require declared tool names and arguments that parse as JSON objects. After a normal upstream finish, complete a missing outer array or unique `tool_calls` wrapper only when all calls and arguments are complete. Reject incomplete calls, parameters, strings and values after commas. Treat ordinary `name` fields, field descriptions and empty `tool_calls` arrays as text answers. Validation covers names and JSON-object arguments; full JSON Schema validation remains outside this implementation.
- Support Responses function definitions, `function_call` / `function_call_output` history, function results and the SSE added/delta/done/completed lifecycle. Map truncation to `incomplete` and errors to `failed`.
- Prompt for actual tool calls when execution is required, enforce `required` and named-function choices, and allow ordinary summaries in `auto` mode. Retry generation once with the same history after a normal finish containing neither text nor native calls. Buffer reasoning from the first attempt. Report an error if both attempts are empty. Errors, EOF, `length`, published text and tool calls end the retry path; tool side effects are never replayed.
- Prefer `max_completion_tokens` over `max_tokens` for Chat; use `max_output_tokens` for Responses.
- Aggregate native tool-name and argument fragments by index, including `message` and legacy `function_call` fields. Validate the completed calls and reject native calls when tools are disabled.
- Send SSE heartbeats while waiting for upstream headers. Cancel the wait and close its upstream connection when the client disconnects.
- Log `genai_request` metadata: request ID, path, model, counts, tool choice, output limit, duration, finish reason, DONE, cancellation and exception type. Credentials, message text and tool results stay out of logs. `saw_done=false` means DONE was absent; a finish reason still permits normal completion.

## Token renewal

Secure storage retains the account, password, upstream token and two-hour expiry after login. The running app renews the token at expiry, restores its timer on startup and checks expiry before requests after resume. The new token updates storage and the live gateway while preserving its port, local API token and existing streams.

Concurrent requests share one refresh. Automatic login failures retry after one minute. Sign-out clears the credentials and cancels renewal. Older records require one new login to populate credentials and expiry.

Local validation for this branch: 13 renewal/HTTP-service tests, 62 gateway tests, 728 full Flutter tests and static analysis passed.

## Validation before the PR split

The following evidence belongs to the local installation and combined PR #135 build, which also contained Linux DDL and watch modules. This PR contains the GenAI gateway, feature page and their tests.

| Check | Recorded result |
| --- | --- |
| `flutter test test/genai_gateway_test.dart --no-pub` | 62 passed |
| `flutter test --no-pub` | 740 passed; updated deadline empty-state assertions and settings-log scrolling |
| Targeted `flutter analyze --no-pub` | No issues |
| `flutter build linux --release --no-pub` | Succeeded |
| `tool/genai_gateway_smoke.dart` | Real ChatGLM streaming tool request, fixture result and non-streaming summary through both Chat Completions and Responses, in development and installed gateways |

The smoke check exposed only `fixture_read` with fixed IDs. It exercised fixture tool round trips; file/Git execution and GPT models await separate acceptance.

- Installation: `/home/jdz/.local/opt/techpie-linux-widgets-v1/bundle`.
- Recorded process: PID 404337 owned `127.0.0.1:5000`; its loaded `libapp.so` matched the build.
- `libapp.so` SHA-256: `41666b4dfccc439d6d1622a0f084f4d8816766d204fa11f061cb06e068b7510d`.
- Previous bundle: `/home/jdz/.local/opt/techpie-linux-widgets-v1/bundle-backup-20261028-194654`.
- `techpie --genai-api` restored the API service for this run. The GenAI API page remains the normal entry point.

Logs:

- `/tmp/techpie-all-sync-tests-final.log`
- `/tmp/techpie-genai-sync-tests.log`
- `/tmp/techpie-genai-sync-analyze.log`
- `/tmp/techpie-linux-build-sync.log`
- `/tmp/techpie-real-chatglm-sync.log`
- `/tmp/techpie-installed-chatglm-sync.log`
- `/tmp/techpie-installed-genai-sync.log`

## Original VS Code client

File reading and editing in the original client await acceptance. The session has no local client-tool execution record, and the screenshot's API path and stop reason remain unresolved. Match request IDs, paths and finish reasons to client tool records when retesting. Those execution records are the acceptance evidence for actual file operations.
