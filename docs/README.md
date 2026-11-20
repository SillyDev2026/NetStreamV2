# NetStreamV2 Documentation

**Technical documentation for the v4.3.1 source line and the experimental v4.4 owner-replication preview.**

[Project overview](../README.md) · [Getting started](../README.md#installation) · [Contributing](../CONTRIBUTING.md) · [Changelog](CHANGELOG.md)

NetStreamV2 is a Roblox Luau networking framework. This documentation separates implemented APIs, repeatable Luau tests, and historical engineering notes from features that still require live Roblox Studio validation.

## Start here

| Your goal | Primary guide | Next step |
| --- | --- | --- |
| Install and send your first event | [Project README](../README.md) | Run the paired Studio examples |
| Understand packet layout and queues | [Architecture](ARCHITECTURE.md) | Review the [packet-size audit](PACKET_SIZE_AUDIT.md) |
| Authorize client-origin commands | [Security](SECURITY.md) | Add [action tickets](ACTION_GATE_SECURITY.md) where appropriate |
| Replicate server-owned player data | [Authoritative replication](AUTHORITATIVE_REPLICATION.md) | Validate the experimental API in a two-player Studio session |
| Bound in-flight remote requests | [RPC concurrency](RPC_CONCURRENCY.md) | Inspect the runtime counters |
| Tune serialization allocations | [Memory retention](MEMORY_EFFICIENCY.md) | Reproduce [packer benchmarks](PACKER_MEMORY_OPTIMIZATION.md) |
| Investigate throughput or RTT | [Benchmarking](BENCHMARKING.md) | Run realistic Studio workloads |
| Validate a proposed change | [Runtime verification](RUNTIME_VALIDATION.md) | Run [simulated-server stress](SERVER_STRESS_VALIDATION.md) |
| Review release history and priorities | [Changelog](CHANGELOG.md) | Review the [roadmap](NEXT_OPTIONS.md) |

## Reference catalog

| Document | Scope |
| --- | --- |
| [Architecture](ARCHITECTURE.md) | Remote and packet lifecycle, encoding, scheduling, state and observability |
| [Security policies](SECURITY.md) | Default-deny admission, validation, authorization, idempotency and trust boundaries |
| [Action-ticket security](ACTION_GATE_SECURITY.md) | Server-issued one-use tickets, replay limits and authoritative purchase examples |
| [Authoritative replication](AUTHORITATIVE_REPLICATION.md) | Experimental owner-only snapshots, ACKs, resync and server-approved commands |
| [RPC concurrency](RPC_CONCURRENCY.md) | Admission budgets, yielded callbacks, error privacy and diagnostics |
| [Memory efficiency](MEMORY_EFFICIENCY.md) | Bounded pools and heap-retention diagnostics |
| [Packer optimization](PACKER_MEMORY_OPTIMIZATION.md) | Native Codec fast paths, allocation reuse and benchmark limitations |
| [Packet-size audit](PACKET_SIZE_AUDIT.md) | Source-derived byte counts and framing boundaries |
| [Benchmarking](BENCHMARKING.md) | Comparable Studio workload methodology and release criteria |
| [Runtime validation](RUNTIME_VALIDATION.md) | CLI regressions, mocks and known coverage gaps |
| [Simulated-server stress](SERVER_STRESS_VALIDATION.md) | High-volume deterministic Luau workloads, not live server capacity |
| [Message-processing review](MESSAGE_PROCESSING_REVIEW.md) | Historical design assessment, trade-offs and remaining opportunities |
| [Roadmap](NEXT_OPTIONS.md) | Current priorities separated from historical iteration notes |
| [Changelog](CHANGELOG.md) | Version history and unreleased source changes |
| [Archived v2.3.22 manual](README_LEGACY_v2.3.22.md) | Historical document, not current installation guidance |
| [Documentation style guide](STYLE_GUIDE.md) | Formatting, accuracy, links and review expectations |

## Current status

| Capability or evidence | Status |
| --- | --- |
| Reliable/unreliable routes, RPC, BitFrame v1 and codec 230 | Implemented |
| Server-side policies, one-use tickets and local idempotency | Implemented; policies and tickets must be adopted correctly |
| Owner-authoritative replication with revision ACK/resync | Experimental v4.4 preview; still identifies as v4.3.1 |
| Standalone Luau regression and mock-peer stress | Automated in GitHub Actions |
| Live Roblox Studio multiplayer and measured heap/RTT | Not certified by the standalone test suite |
| Cross-server durable transactions and exactly-once purchases | Application responsibility; not provided by NetStreamV2 |

## Maintainer checks

From the repository root, with Node.js and the official Luau CLI installed:

```bash
node scripts/source-audit.mjs
node scripts/docs-audit.mjs
node scripts/runtime-tests.mjs
node scripts/runtime-tests.mjs --stress-only
node scripts/runtime-tests.mjs --profile-only
node scripts/runtime-tests.mjs --compare-only
```

If the Luau interpreter is not on `PATH`, provide its absolute path through `LUAU_BIN`. These checks are not a substitute for testing the supplied `tests/*.server.lua` and `tests/*.client.lua` scripts in an actual Roblox Studio session.

## Documentation conventions

- **Implemented** means the API exists in the current source; it does not imply a production security certification.
- **Experimental** means the API is available but requires additional Studio and application-level validation.
- **Measured** values must identify their workload, environment and comparison baseline.
- **Historical** sections preserve past decisions; the current source and newest changelog supersede outdated plans.
- Client-supplied values are never authoritative. See [security](SECURITY.md) before using replicated data for economy or inventory.

Read [STYLE_GUIDE.md](STYLE_GUIDE.md) before contributing documentation.
