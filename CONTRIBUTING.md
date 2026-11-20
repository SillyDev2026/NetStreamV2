# Contributing to NetStreamV2

Thanks for helping improve NetStreamV2. Changes should prioritize **correctness, compatibility, server authority, measurable efficiency, and reproducible verification**.

[Project README](README.md) · [Documentation index](docs/README.md) · [Documentation style](docs/STYLE_GUIDE.md) · [Release history](docs/CHANGELOG.md)

## Before making changes

1. Read the [architecture](docs/ARCHITECTURE.md), [security model](docs/SECURITY.md), and [runtime validation](docs/RUNTIME_VALIDATION.md) relevant to your change.
2. Identify the actual behavior of `Netstream.lua`, `Compression.lua`, or the optional `AuthoritativeState.lua`. Avoid implementing against historical documentation.
3. State the compatibility impact. BitFrame v1 and codec 230 changes require explicit review and versioning; never silently alter valid packet bytes.
4. Prefer small, separately testable patches that retain the existing public API.

## Code and security expectations

- Keep sensitive game state on the server. Treat every client-origin payload as untrusted regardless of handshake, serialization, or ticket use.
- Limit memory, nesting, string lengths, message rates, and in-flight work before executing gameplay callbacks.
- Preserve nil/false values, error recovery, FIFO ordering where promised, and robust teardown/disconnect handling.
- Avoid doing trusted writes inside client-controlled reducers or relying on in-memory deduplication for durable purchases.
- Use Luau type checks where practical; keep allocation-sensitive paths benchmarkable and covered by regressions.
- Never commit tokens, secrets, credentials, or private user information.

## Test the change

Run the source, documentation, and complete Luau regression suites:

```bash
node scripts/source-audit.mjs
node scripts/docs-audit.mjs
node scripts/runtime-tests.mjs
node scripts/runtime-tests.mjs --stress-only
node scripts/runtime-tests.mjs --profile-only
node scripts/runtime-tests.mjs --compare-only
```

The runtime checks require the official Luau interpreter; set `LUAU_BIN` if needed. Verify changed networking behavior with isolated paired Roblox Studio test scripts from `tests/`. Do not equate simulated peers or Luau CPU timings with real client capacity or RTT.

## Pull request checklist

- [ ] Behavior and expected failure modes are described.
- [ ] Security and resource boundaries were reviewed.
- [ ] New behavior has a focused regression (including malformed or adversarial inputs where relevant).
- [ ] Source audit, Markdown audit, and Luau suites pass.
- [ ] Wire compatibility is preserved or a deliberate migration/versioning plan is included.
- [ ] Relevant API reference, examples, and changelog sections are updated.
- [ ] Performance claims include comparable workloads, test environment, and limitations.
- [ ] Roblox Studio verification is reported as **performed**, **pending**, or **not applicable**, never assumed.

## Documentation changes

Follow the [style guide](docs/STYLE_GUIDE.md). Keep the [documentation index](docs/README.md) in sync when adding, renaming, or retiring guides. Historical release notes remain archival; use the top of the [changelog](docs/CHANGELOG.md) for unreleased changes.

## Reporting bugs or security issues

Provide a minimal reproduction, source commit, environment, expected result, observed result, and relevant sanitized logs. For potential vulnerabilities, do **not** publish exploit instructions, credentials, or sensitive account data in a public issue. Use a private maintainer communication channel when one is available.

A successful build or static source audit is not a substitute for runtime reproduction.
