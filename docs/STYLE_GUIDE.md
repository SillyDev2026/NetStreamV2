# Documentation Style Guide

**Applies to:** All active Markdown guides in this repository. The archived v2.3.22 manual remains intentionally preserved and is marked historical.

[← Documentation index](README.md) · [Contributing](../CONTRIBUTING.md)

## Editorial standard

Write for developers integrating NetStreamV2 into a Roblox game. Prefer **exact API names**, concise explanations, safe working examples, and independently verifiable claims.

| Principle | Practice |
| --- | --- |
| Accuracy | Confirm API signatures and limits against current source before publishing |
| Security | Explain server/client trust boundaries and any required application validation |
| Compatibility | State the source version, packet protocol, and migration impact where relevant |
| Performance | Distinguish Luau CLI microbenchmarks from Roblox Studio CPU, RTT, heap and throughput |
| Scope | Distinguish implemented, experimental, historical and planned behavior |
| Navigation | Link to the project README, documentation index, related guides and tests |
| Maintainability | Prefer short, titled sections and small tables over long disconnected patch notes |

## Recommended guide outline

A current guide should normally include a single `#` heading, short scope/status statement, prerequisites if any, an actionable explanation, runnable examples or procedures, verification steps, limitations, and related documentation. Use `##` and `###` headings in a consistent hierarchy.

Historical design documents may preserve their original content, but an archive notice must clearly identify their version and direct readers to current instructions.

## Code examples

- Label Luau code blocks `luau`, terminal commands `bash`, and directory diagrams `text`.
- Show where server Scripts and client LocalScripts belong. Do not mix trusted and untrusted responsibilities.
- Keep route identifiers and schemas consistent across server/client snippets.
- Call out example-only data and placeholder state explicitly. Do not imply sample purchases are durable.
- Follow the preferred Luau style: `local result = expression` on one line when practical, and avoid splitting an assignment after `=`.
- Do not silently change API behavior for formatting; re-run source-derived examples when possible.

## Technical claims

Use the exact evidence level:

- **Source-derived:** Code or configuration inspected directly.
- **Standalone verified:** An official Luau CLI regression with mock services passed.
- **Studio verified:** The named real Roblox Studio test was executed and its result recorded.
- **Measured:** The workload, sample count, hardware/runtime, baseline and units are specified.
- **Unverified:** Proposed behavior or an unexecuted test script, clearly labeled.

A 96-peer simulation is not proof that 96 real clients can connect at the same latency. A successful ACK is not proof of a durable transaction. Client-visible tickets are not secret authentication material.

## Links, tables, and release terminology

Use relative Markdown links for local files, keep internal anchors synchronized with their headings, and avoid duplicated or malformed table cells. Prefer an explicit `Status` or `Scope` column when comparing implemented and proposed features.

The module reports **v4.3.1** on the current source line. The owner-authoritative replica implementation is an **experimental v4.4 preview** until the code is deliberately versioned and its release gates are satisfied.

## Validation before review

```bash
node scripts/docs-audit.mjs
node scripts/source-audit.mjs
```

The docs audit checks Markdown titles, fenced blocks, tables and local links. Follow the project [contribution checklist](../CONTRIBUTING.md) for the full runtime and Studio validation requirements.
