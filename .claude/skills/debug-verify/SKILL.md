---
name: debug-verify
description: Launch the debug server and verify runtime state by dynamically discovering endpoints from source code. Use after implementing features or fixing bugs that touch SwiftData models (accounts, positions, assets, snapshots), TCA state (sync, prices), network calls, or any runtime behavior. Also use when the user says "debug-verify", "test the debug server", "check runtime state", "verify the app state", or "curl the debug endpoints". Trigger proactively after writing code that changes sync logic, price fetching, account handling, or data persistence — don't wait for the user to ask.
---

Verify the running app's runtime state using the embedded debug server on `localhost:9999`.

The debug server's endpoint surface evolves as the app grows — new routes get added across PRs without centralized documentation. Reading the source is the only way to know the full, current API. Static endpoint lists drift within days. This skill exists to prevent that.

## Step 1: Discover all current endpoints from source

Read these two files and find every `addRoute` call to build the complete endpoint map:

- `Sources/Portu/Debug/DebugServer.swift` — health endpoint, TCA state routes, and action routes
- `Sources/Portu/Debug/DebugEndpoints.swift` — SwiftData state routes, snapshot routes, and network log

For each route, note the HTTP method, path, query parameters (with defaults and clamping), and response shape from the handler closure. This is the authoritative API surface — do not rely on any other source for endpoint information.

## Step 2: Build and launch

Check if the debug server is already running:

```
curl -s http://localhost:9999/health
```

If it responds, skip to Step 3. Otherwise, run `just debug-run` to build the app and launch with the debug server. The recipe waits until `/health` responds before returning.

## Step 3: Query relevant endpoints

Using the endpoints discovered in Step 1, select and curl the ones relevant to whatever was just implemented or changed. Use `jq` for readable output. Always start with `GET /health` to confirm the server is alive.

Choose endpoints based on what the recent code change touched — match the data domain (models, sync, prices, network) to the endpoint categories you discovered. If unsure which endpoints are relevant, query broadly rather than narrowly.

Report what each endpoint returned and whether the runtime state reflects the expected changes.

## Step 4: Clean up

Run `just debug-stop` to kill the debug app — unless the user wants to keep it running for manual inspection.
