# Changelog

Maintained by [release-please](https://github.com/googleapis/release-please) from
[Conventional Commits](https://www.conventionalcommits.org/). Do not edit by hand —
a release pull request rewrites the sections below it.

## [1.0.1](https://github.com/mxwlf/adrianpadilla-net-homepage/compare/v1.0.0...v1.0.1) (2026-11-05)


### Fixes

* **ci:** deploy with the Static Web Apps CLI instead of the action ([1cb77ef](https://github.com/mxwlf/adrianpadilla-net-homepage/commit/1cb77ef6e8e8498703b503e34f17b0333ce7bc9c))
* **ci:** deploy with the Static Web Apps CLI instead of the action ([9b4af2f](https://github.com/mxwlf/adrianpadilla-net-homepage/commit/9b4af2f04a061d185c00bbf98bda80f152818eb5))
* **ci:** stop linting CHANGELOG.md, which release-please owns ([76e5813](https://github.com/mxwlf/adrianpadilla-net-homepage/commit/76e5813cb10d718d41fbd1772f93999c3cd3fa81))
* **deps:** override the vulnerable transitives the SWA CLI pulls in ([3827751](https://github.com/mxwlf/adrianpadilla-net-homepage/commit/38277511c47927dea499f52894bb6cab8cdc960c))
* empty dist/ before building so the release digest is stable ([3e7eb09](https://github.com/mxwlf/adrianpadilla-net-homepage/commit/3e7eb09a2ffa825fb2407288b69bedcc408fd1e5))
* stabilise the release digest, and correct the header docs ([d2934a8](https://github.com/mxwlf/adrianpadilla-net-homepage/commit/d2934a8ed86323651712a303f650df8e340d8e56))


### Build and CI

* stop lychee failing on release-please's own compare link ([bda2b6d](https://github.com/mxwlf/adrianpadilla-net-homepage/commit/bda2b6d4ab95504f3456753cdf8994bbb62dabd8))
* stop lychee failing on release-please's own compare link ([4172a2a](https://github.com/mxwlf/adrianpadilla-net-homepage/commit/4172a2a85e446ac8635f58120079aaff0f777cd6))

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
