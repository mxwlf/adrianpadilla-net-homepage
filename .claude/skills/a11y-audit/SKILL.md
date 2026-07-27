---
name: a11y-audit
description: Run accessibility tests and report WCAG violations with remediation steps.
disable-model-invocation: true
allowed-tools: Bash, Read, Grep
---

1. Run: `make build` and `make a11y`.
2. Parse the Playwright + axe output for violations.
3. For each violation, report: rule ID, impact level, affected element(s), and a concrete fix with file path and line number.
4. Summarize pass/fail counts and overall accessibility score.
