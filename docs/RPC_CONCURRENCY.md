# v4.3.0 RPC Concurrency & Call Lifecycle

## Problem addressed

NetStream previously enforced incoming call **rate** (calls per second) but not the number of asynchronous callbacks remaining alive at once. A callback that yields for several seconds can allow thousands of outstanding Luau tasks across a server, even when every call was rate-compliant.

This patch adds **in-flight RPC admission limits** to protect the server's task count and callback-owned memory:

```luau
NetStream.Configure({
    MaxConcurrentIncomingCalls = 512,
    MaxConcurrentIncomingCallsPerPlayer = 64,
})
```

Both are server-side limits. `0` disables a specific limit (for apps that intentionally manage their own callback concurrency); the existing per-second call budgets still apply. The concurrency limits check admitted active RPC callbacks, not queued outgoing events, and do **not** cancel callbacks already running.

The request admission path now checks existing per-second limits **and** concurrency limits before reserving one in-flight slot. All four received RPC wire paths call the same guarded runner. That runner executes the registered function callback and releases the global and player slot after it finishes, even if the callback raises an exception. If callback processing raises an unexpected internal error, `IncomingCallExecutionErrors` records it; normal application exceptions are already returned by the existing RPC error transport.

**Overload behavior:** Rejected RPC calls are silently dropped using the library's existing rate-rejection convention, so the invoking peer will generally observe its configured `CallTimeout`. Do not use fire-and-forget RPCs for non-idempotent critical actions without idempotency keys, acknowledgments, and an application-level retry policy. Legitimately yielding RPC callbacks may need a higher cap. There is no promise to terminate a long-running/hung callback automatically.

## Diagnostics

```luau
local rpc = NetStream.GetRPCStats() -- server-wide
print(rpc.Active, rpc.PeakActive, rpc.ConcurrencyDrops, rpc.ExecutionErrors)
-- On the server, optionally inspect a single player:
local one = NetStream.GetRPCStats(player)
print(one.Active, one.PerPlayerLimit)
```

`GetStats().ActiveIncomingCalls` and `GetMemoryDiagnostics().ActiveIncomingCalls` expose the same global active gauge; the memory diagnostics also include the peak, rejection and execution-error counters. `NetStream.ResetStats()` resets cumulative counters but retains the current active count as the new peak baseline.

## Vararg-copy hot paths

The argument-array copier and packed-run value copier now use a single positional vararg assignment for common **4–8** and **12** field payloads. This removes repeated `select(i, ...)` scans in those common shapes without creating a temporary `table.pack` array. All other cardinalities continue using the established fallback, preserving nil positions, field arity, and packet content.

An improvement in CPU/allocations is a hypothesis pending Roblox Studio benchmarks, especially at the 12-field mixed and homogeneous schema hot paths. The library does not claim a speed or GC percentage increase without measured results.

## Regression matrix

The new paired `tests/RPCConcurrencyRegression.server.lua` / `*.client.lua` test creates a two-concurrent-calls-per-player limit and requests 16 simultaneous calls. The server holds accepted callbacks, checks the active gauge cannot exceed limits, and verifies that at least one call is throttled and one is accepted. The client then invokes an intentionally faulty callback to test exception-to-RPC-error handling, followed by a successful fresh request to verify that capacity recovers.

Source audit checks all four `task.spawn` sites use the guarded runner, validates configuration fragments, models multi-player caps and slot reclamation, and checks direct-copy paths. CI Luau syntax validation and source tests are **not** a substitute for a Studio test; network timing may make the burst-based assertions sensitive to runtime conditions. Run this pair in a fresh Play session without unrelated scripts; repeat with 1 and 4 players and with long callback durations.

## Remaining review items

- No automated Studio multiplayer runtime yet; use the 94 authored Studio scripts for isolated tests.
- Per-second and in-flight controls complement, rather than replace, authentication, domain validation, anti-exploit logic, or server-authoritative game state.
- Compare p95/p99 callback turnaround time, active task count, heap after GC, total RPC success/error/timeouts, and CPU scheduling under 1/10/25-player workload. Measure with concurrency caps on and off in otherwise identical sessions.
- **Do not** claim all bugs are fixed or that the new hot paths outperform Zap, BlinkBlox, ByteNet, or Satset without matched results.
