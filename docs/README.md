# NetStreamV2 Documentation

Documentation for the **v4.3.1 source line** and subsequent compatible changes on `main`. The bundled serializer is **Compression v2.4.2 (codec 230)**; default transport framing is **BitFrame v1**.

[← Project overview and installation](../README.md) · [Changelog](CHANGELOG.md) · [Validation status](RUNTIME_VALIDATION.md)

## Choose a guide

| If you want to… | Read |
| --- | --- |
| Install NetStream and send a typed event | [Root README](../README.md#quick-start) |
| Understand batching, remotes, and the binary protocol | [Architecture](ARCHITECTURE.md) |
| Secure client commands and server-owned gameplay state | [Security policies](SECURITY.md) |
| Issue and redeem server-owned, one-use permissions | [Action-ticket guide](ACTION_GATE_SECURITY.md) |
| Configure rate and in-flight RPC limits | [RPC concurrency](RPC_CONCURRENCY.md) |
| Inspect encoder/decoder allocations and pool lifecycles | [Memory efficiency](MEMORY_EFFICIENCY.md) |
| Review tiny-packet optimization and benchmark trade-offs | [Packer memory optimization](PACKER_MEMORY_OPTIMIZATION.md) |
| Check BitFrame field overhead | [Packet-size audit](PACKET_SIZE_AUDIT.md) |
| Run official Luau regression tests | [Runtime validation](RUNTIME_VALIDATION.md) |
| Run deterministic simulated-player load | [Server stress validation](SERVER_STRESS_VALIDATION.md) |
| Run controlled Roblox Studio CPU/RTT/heap tests | [Benchmarking](BENCHMARKING.md) |
| Review previous message-processing design decisions | [Message-processing review](MESSAGE_PROCESSING_REVIEW.md) |
| Review upcoming work and acceptance criteria | [Upgrade roadmap](NEXT_OPTIONS.md) |
| Find post-release maintenance and older release notes | [Changelog](CHANGELOG.md) |

## Documentation status

| Evidence | Available now | Not established by it |
| --- | --- | --- |
| GitHub Actions source audit | Source-level invariants and configuration checks | Live Roblox runtime correctness |
| Official Luau CLI regressions | Parser, codec, RPC, and security behavior with controlled service doubles | Real RemoteEvent serialization or scheduler timing |
| Simulated-server stress suite | Deterministic high-volume workloads across production source paths | Support for a measured number of actual connected players |
| Paired Roblox Studio scripts | Authored test scenarios ready for Play sessions | A passed Studio run, unless results are explicitly recorded |
| Packer A/B microbenchmarks | Illustrative small/structured payload CPU measurements | Whole-experience throughput, heap savings in MiB, or lower ping |

Code and documented behavior should be validated against the current [Netstream.lua](../Netstream.lua) and [Compression.lua](../Compression.lua). Client code and data are untrusted; critical decisions belong on the server.

## Maintainer workflow

Run from the repository root with Node.js and the official Luau CLI installed:

```sh
node scripts/source-audit.mjs
LUAU_BIN=/path/to/luau node scripts/runtime-tests.mjs
LUAU_BIN=/path/to/luau node scripts/runtime-tests.mjs --stress-only
LUAU_BIN=/path/to/luau node scripts/runtime-tests.mjs --profile-only
LUAU_BIN=/path/to/luau node scripts/runtime-tests.mjs --compare-only
node scripts/docs-check.mjs
```

The official CI workflow builds Luau itself and executes the suites. Use separate Studio Play sessions for server/client test pairs to avoid route and configuration conflicts.

## Historical reference

[NetStreamV2 v2.3.22 long-form README](README_LEGACY_v2.3.22.md) is preserved as an archive. It is not the current installation, security, or API compatibility guide. Version-specific performance notes elsewhere in this directory are labeled as historical when applicable.

---

**Documentation policy:** Prefer precise source-derived statements and reproducible tests over unverified speed rankings. Report Roblox Studio results separately from standalone Luau CLI measurements.
