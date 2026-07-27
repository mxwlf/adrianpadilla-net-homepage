---
name: perf-audit
description: Run Lighthouse CI locally and summarize findings with concrete fixes.
disable-model-invocation: true
allowed-tools: Bash, Read, Grep
---

1. Run: `make build` and `make lighthouse`.
2. Summarize any failed assertions, list the failing audits, and propose fixes with file-level pointers.
3. If changes are required, open a PR-ready patch plan (do not apply changes unless asked).
