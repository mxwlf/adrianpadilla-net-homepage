# Changelog

Maintained by [release-please](https://github.com/googleapis/release-please) from
[Conventional Commits](https://www.conventionalcommits.org/). Do not edit by hand —
a release pull request rewrites the sections below it.

## [1.4.2](https://github.com/mxwlf/adrianpadilla-net-homepage/compare/v1.4.1...v1.4.2) (2026-11-09)


### Fixes

* **ci:** make the production header check able to fail ([69f8aad](https://github.com/mxwlf/adrianpadilla-net-homepage/commit/69f8aad98178855e11b1f09ab214ebcfee547a33))

## [1.4.1](https://github.com/mxwlf/adrianpadilla-net-homepage/compare/v1.4.0...v1.4.1) (2026-11-09)


### Fixes

* **ci:** upload the Lighthouse reports that were being filtered out ([37a688f](https://github.com/mxwlf/adrianpadilla-net-homepage/commit/37a688f498a2a7c3deaf04d1bda4eb6ff0a9561f))
* **ci:** upload the Lighthouse reports that were being filtered out ([a29d43f](https://github.com/mxwlf/adrianpadilla-net-homepage/commit/a29d43f18bfc464ee138e2beecc9326fa4b01507))
* **security:** restore base-uri 'self' to the CSP ([784ca97](https://github.com/mxwlf/adrianpadilla-net-homepage/commit/784ca971fb44280680ff3c8387b6643ad69389c0))
* **security:** restore base-uri 'self' to the CSP ([f441c1e](https://github.com/mxwlf/adrianpadilla-net-homepage/commit/f441c1e9b83f93731e4bf094ea0b18d0044af811))
* **security:** serve X-Frame-Options: DENY ([835e6bf](https://github.com/mxwlf/adrianpadilla-net-homepage/commit/835e6bf7c24a4e6b210afcda204f03422328ff52))
* **security:** serve X-Frame-Options: DENY ([0162f4b](https://github.com/mxwlf/adrianpadilla-net-homepage/commit/0162f4bc04f8f212f228d52b003b69078fc25144))

## [1.4.0](https://github.com/mxwlf/adrianpadilla-net-homepage/compare/v1.3.5...v1.4.0) (2026-11-08)


### Features

* **ci:** let the production monitor be run on demand ([b6bf7e3](https://github.com/mxwlf/adrianpadilla-net-homepage/commit/b6bf7e34a761dac610403563b9f4a4d0ae76625b))


### Fixes

* **ci:** audit production instead of a port nothing listens on ([1922fb1](https://github.com/mxwlf/adrianpadilla-net-homepage/commit/1922fb11096ce7e8c0be461d39f25e85182f483a))
* **ci:** audit production instead of a port nothing listens on ([79cd0c4](https://github.com/mxwlf/adrianpadilla-net-homepage/commit/79cd0c46f812a88490aecd9f933416689f0f34ce))

## [1.3.5](https://github.com/mxwlf/adrianpadilla-net-homepage/compare/v1.3.4...v1.3.5) (2026-11-08)


### Fixes

* **ci:** fast-forward main instead of merging into it ([48d2011](https://github.com/mxwlf/adrianpadilla-net-homepage/commit/48d20118064b3a964d82ca5f7014a3adccb16fd0))
* **ci:** fast-forward main instead of merging into it ([baaa251](https://github.com/mxwlf/adrianpadilla-net-homepage/commit/baaa251681fddba794f5c8f4ad5b39c5e363a1ac))
* **rulesets:** commit the release App's bypass on main ([67e8683](https://github.com/mxwlf/adrianpadilla-net-homepage/commit/67e8683a20656323b21d5c48a9689140275e1050))
* **rulesets:** commit the release App's bypass on main ([b413f8d](https://github.com/mxwlf/adrianpadilla-net-homepage/commit/b413f8d2caacae93bfeefceb80345ab6fc2b4573))

## [1.3.4](https://github.com/mxwlf/adrianpadilla-net-homepage/compare/v1.3.3...v1.3.4) (2026-11-07)


### Fixes

* **ci:** wait for the host config to go live before asserting on it ([720c364](https://github.com/mxwlf/adrianpadilla-net-homepage/commit/720c3647511f883a57c0e7b0b3e7b1c7523e2d1e))
* **ci:** wait for the host config to go live before asserting on it ([702d453](https://github.com/mxwlf/adrianpadilla-net-homepage/commit/702d453d77b1e975e476403f36b204b9f7c92e62))

## [1.3.3](https://github.com/mxwlf/adrianpadilla-net-homepage/compare/v1.3.2...v1.3.3) (2026-11-07)


### Fixes

* **infra:** bind the test hostname with az instead of OpenTofu ([8dfb4b1](https://github.com/mxwlf/adrianpadilla-net-homepage/commit/8dfb4b1d13c83352b81cd64d4523d5249affb783))
* **infra:** bind the test hostname with az instead of OpenTofu ([f2f6318](https://github.com/mxwlf/adrianpadilla-net-homepage/commit/f2f6318140f1b6ba642799ad94ae8765f2788561))

## [1.3.2](https://github.com/mxwlf/adrianpadilla-net-homepage/compare/v1.3.1...v1.3.2) (2026-11-07)


### Build and CI

* stop re-running the gate on trees it has already cleared ([609a07c](https://github.com/mxwlf/adrianpadilla-net-homepage/commit/609a07c5f11a6485b4f0836f7840816d2ccb79f3))
* stop re-running the gate on trees it has already cleared ([119978f](https://github.com/mxwlf/adrianpadilla-net-homepage/commit/119978f363f1f968e2e43f5b85f70d651053102a))

## [1.3.1](https://github.com/mxwlf/adrianpadilla-net-homepage/compare/v1.3.0...v1.3.1) (2026-11-06)


### Fixes

* **infra:** read the DNS record through both az output casings ([6f6e6ba](https://github.com/mxwlf/adrianpadilla-net-homepage/commit/6f6e6babfe9e738469d02d09d37cc085a61bc714))
* **infra:** read the DNS record through both az output casings ([8e16b77](https://github.com/mxwlf/adrianpadilla-net-homepage/commit/8e16b77bf0f35edb4315af2e97cd372190bfe8e8))

## [1.3.0](https://github.com/mxwlf/adrianpadilla-net-homepage/compare/v1.2.3...v1.3.0) (2026-11-06)


### Features

* **infra:** add test environment teardown and DNS restore pipeline ([385317b](https://github.com/mxwlf/adrianpadilla-net-homepage/commit/385317be65c0f6f586b8ffca4353805b2bff01f6))
* **infra:** add test environment teardown and DNS restore pipeline ([ad7cf1b](https://github.com/mxwlf/adrianpadilla-net-homepage/commit/ad7cf1b96fee9ba3847e8a71616c7b475a311235))

## [1.2.3](https://github.com/mxwlf/adrianpadilla-net-homepage/compare/v1.2.2...v1.2.3) (2026-11-06)


### Performance

* **build:** minify CSS so comments stop gating the Lighthouse job ([bb2eaaf](https://github.com/mxwlf/adrianpadilla-net-homepage/commit/bb2eaaf3dcd2f706e144a48ffe4f815f9bb24512))
* **build:** minify CSS so comments stop gating the Lighthouse job ([188fe76](https://github.com/mxwlf/adrianpadilla-net-homepage/commit/188fe76d3962f8fe2ac45d648ab96f3550bfe05a))

## [1.2.2](https://github.com/mxwlf/adrianpadilla-net-homepage/compare/v1.2.1...v1.2.2) (2026-11-06)


### Fixes

* **footer:** make the version line less prominent ([616f0a9](https://github.com/mxwlf/adrianpadilla-net-homepage/commit/616f0a9cfb32d8f3c27c19fe88d310a3dd4ff2a0))
* **footer:** make the version line less prominent ([b6f5a06](https://github.com/mxwlf/adrianpadilla-net-homepage/commit/b6f5a067286a76163170da5b6c0fb87a06abe61d))

## [1.2.1](https://github.com/mxwlf/adrianpadilla-net-homepage/compare/v1.2.0...v1.2.1) (2026-11-05)


### Fixes

* **ci:** drop a stray action input from the production deploy step ([15fb719](https://github.com/mxwlf/adrianpadilla-net-homepage/commit/15fb719ed6850cd5c6d58491d449f8c39e821ec8))
* **ci:** drop a stray action input from the production deploy step ([1466155](https://github.com/mxwlf/adrianpadilla-net-homepage/commit/146615503f94675787cac12a67ffb621d790f756))

## [1.2.0](https://github.com/mxwlf/adrianpadilla-net-homepage/compare/v1.1.0...v1.2.0) (2026-11-05)


### Features

* describe production in OpenTofu and rebuild it from scratch ([8713514](https://github.com/mxwlf/adrianpadilla-net-homepage/commit/8713514e468062ac8ab52c05dc59b136e4db98d0))
* describe production in OpenTofu and rebuild it from scratch ([7a8ba42](https://github.com/mxwlf/adrianpadilla-net-homepage/commit/7a8ba4277ee3f1731fa8c11a04a46ed1203a6f68))

## [1.1.0](https://github.com/mxwlf/adrianpadilla-net-homepage/compare/v1.0.1...v1.1.0) (2026-11-05)


### Features

* link the footer version to its release notes ([492e5c9](https://github.com/mxwlf/adrianpadilla-net-homepage/commit/492e5c99d3cca2f285b6c4dea8aa035c89f36dc9))
* show the released version in the site footer ([f3c8955](https://github.com/mxwlf/adrianpadilla-net-homepage/commit/f3c8955b71b690eb91a4aa0de8753fe0ce901c13))
* show the released version in the site footer ([ba3bead](https://github.com/mxwlf/adrianpadilla-net-homepage/commit/ba3bead682b9a2e7c7620fed93909d135106629a))

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
