---
paths:
  - "src/**"
  - ".github/**"
  - "Makefile"
  - "package.json"
---

# CI contract rules

- Run `make setup` once per clone/worktree before anything else; `make ci` depends
  on the `.venv/` it creates, and it activates the committed `.githooks/`.
- Run `make ci` locally before opening any PR; it must pass cleanly.
- `make ci` is the only entrypoint CI invokes. Keep workflow YAML a thin wrapper
  (checkout, toolchains, `make ci`) and put check logic in the `Makefile`,
  `package.json` or `.pre-commit-config.yaml`.
- A required status check's `context` in `.github/rulesets/main-protection.json`
  is a workflow job id. Never rename one without the other: an unreported
  required check leaves pull requests waiting indefinitely.
- Do not make a job required if its own `if:` excludes pull requests — GitHub
  reports such a job as successful, producing a check that is always green.
- Do not disable, skip, or weaken CI quality gates without explicit team approval.
- All required checks (lint, test, build, security scans) must be green before merge.
- Do not add `--no-verify`, `continue-on-error: true`, or `if: always()` to bypass failing steps.
- Workflow permissions must follow least-privilege: `contents: read` by default, escalate per-job only as needed.
- New CI jobs should use the same `make` targets to keep local and CI behavior identical.
