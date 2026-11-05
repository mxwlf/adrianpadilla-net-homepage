# Changelog

Maintained by [release-please](https://github.com/googleapis/release-please) from
[Conventional Commits](https://www.conventionalcommits.org/). Do not edit by hand —
a release pull request rewrites the sections below it.

## 1.0.0

The baseline. `adrianpadilla.net` had been live for some time before it had
versions at all: it published straight from `main`, with no tags, no release
artifacts and nothing to roll back to. Rather than reconstruct a changelog from
the whole history, the site as it stood at this point is recorded as 1.0.0, and
every release after it is derived from commits.

What `1.0.0` is: an Eleventy static site on Azure Static Web Apps, gated by
`make ci` — pre-commit hygiene, Prettier/ESLint/Stylelint, html-validate,
Lighthouse budgets, Playwright end-to-end tests and an axe-core accessibility
suite — with branch protection kept in the repository as code.
