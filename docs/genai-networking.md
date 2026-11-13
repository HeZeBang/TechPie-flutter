# GenAI networking

The GenAI branch uses Flutter 3.41.9 / Dart 3.11.5 in CI. The Apple
networking dependencies require Dart 3.10 or newer.

On iOS and macOS, `createGenAiTransport` selects an ephemeral URLSession
through the official `cupertino_http` bindings. The IDS exchange and GenAI API
use the same transport factory. Other native platforms keep IOClient; web
keeps BrowserClient.

Each operation owns its native task/session. Response headers and data chunks
are delivered as they arrive; cancellation stops the native task even before
headers. Separate metadata, chat-prefill and stream-idle timers retain the
existing budgets. Sessions are invalidated after completion or cancellation.

Automatic redirects and cookie injection are disabled. The IDS exchange
validates every hop, maintains a per-exchange cookie jar, scopes CASTGC to IDS,
and intercepts the GenAI token callback before requesting it. Apple networking
uses the operating system proxy/VPN configuration and standard TLS verification.

Machine-specific launch files, proxy endpoints, native probes, live-test entry
points, credentials and recordings belong outside the repository. They must
not be staged or committed. Production regression tests use fakes or loopback
servers, never real credentials or campus API calls.
