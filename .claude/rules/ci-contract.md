---
paths:
  - "src/**"
  - ".github/**"
  - "Makefile"
  - "package.json"
---

# CI contract rules

- Run `make ci` locally before opening any PR; it must pass cleanly.
- Do not disable, skip, or weaken CI quality gates without explicit team approval.
- All required checks (lint, test, build, security scans) must be green before merge.
- Do not add `--no-verify`, `continue-on-error: true`, or `if: always()` to bypass failing steps.
- Workflow permissions must follow least-privilege: `contents: read` by default, escalate per-job only as needed.
- New CI jobs should use the same `make` targets to keep local and CI behavior identical.
