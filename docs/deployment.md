# Deployment

How a change reaches `adrianpadilla.net`.

```
PR ──▶ develop ──▶ release PR ──▶ merge ──▶ tag + GitHub Release
                                                   │
                                        ONE build (release.yml)
                                 site/ + reports/ + sbom/ + SHA256SUMS
                                      + build provenance attestation
                                                   │
                                     ┌─────────────┴──────────────┐
                                     ▼                            ▼
                             test (automatic)          production (you approve)
                         test.adrianpadilla.net          adrianpadilla.net
```

The pipeline **builds once and promotes the result**. Production serves the same
bytes the test environment served, verified by digest, never a rebuild. This
matters because it is not how the repository used to work: the Static Web Apps
action was handed `app_location: "/"` with no `skip_app_build`, so Azure's Oryx
container rebuilt the site server-side, and what shipped had never been through
`make ci`.

## The branches

| Branch    | Role                                                             |
| --------- | ---------------------------------------------------------------- |
| `develop` | Integration. Pull requests land here. Default branch.            |
| `main`    | The record of what is in production. Advanced after a promotion. |

Both are protected and accept only merge commits. `develop` does not require
signed commits, because release-please's automated commits are unsigned; `main`
does. See [`.github/rulesets/README.md`](../.github/rulesets/README.md).

## Cutting a release

1. Merge work into `develop` with [Conventional Commits](https://www.conventionalcommits.org/).
2. release-please keeps a release pull request open against `develop`, holding
   the next version, `CHANGELOG.md` and `version.txt`. Review and merge it.
3. Merging it tags the commit and publishes a GitHub Release.
4. `release.yml` builds the package from that tag, attaches it to the Release
   with a provenance attestation, and the test environment deploys it.

Verify an artifact came from this pipeline:

```sh
gh release download v1.1.0 --pattern 'release-*.tar.gz'
gh attestation verify --owner mxwlf release-1.1.0.tar.gz
```

## What a release package contains

```
site/                     the built site, byte-identical in every environment
host-config/{prod,test}/  staticwebapp.config.json, one per environment
reports/                  lighthouse, html-validate, playwright, axe
sbom/bom.cdx.json         CycloneDX SBOM of the dependency tree
manifest.json             version, commit, build time, node, lockfile digest
SHA256SUMS                over site/ and sbom/, `sha256sum -c` compatible
```

`manifest.json`'s **`siteSha256`** is the cross-environment identity: one digest
over the whole `site/` tree. Compare it between environments to prove they serve
the same bytes. The archive's own digest is not that value — a `tar` records
modification times, so it differs between runs even when the contents do not.

`site/` deliberately holds no `staticwebapp.config.json`. Host configuration is
infrastructure, not content, and is chosen at deploy time with the action's
`config_file_location` input. Both variants derive from the one committed
`staticwebapp.config.json`, so a CSP or HSTS change cannot reach one environment
and not the other; the test variant differs by exactly one header,
`X-Robots-Tag: noindex, nofollow`.

Build the package locally with `make package RELEASE_VERSION=0.0.0-dev`.

## One-time setup

### The release GitHub App

release-please needs a token that is **not** `secrets.GITHUB_TOKEN`. Events
raised by the default token do not start other workflows, so the release pull
request would never have `ci`, `lighthouse`, `dependency-review`, `osv-scan` or
`gitleaks` reported against it — and `develop-protection` requires all five, so
it could never be merged.

Create a GitHub App owned by your account:

- **Repository permissions:** Contents `read & write`, Pull requests
  `read & write`, Workflows `read & write`.
- Install it on this repository only.
- Generate a private key.

Then record it:

```sh
gh variable set RELEASE_APP_ID --body '<the app id>'
gh secret   set RELEASE_APP_PRIVATE_KEY < private-key.pem
```

An app is preferred over a personal access token: the installation token is
short-lived, scoped to this repository, and revocable without touching your
account.

### The 1.0.0 baseline tag

`.release-please-manifest.json` is seeded at `1.0.0`, so release-please needs a
matching tag to measure from. Without it, it would walk the entire history and
propose a changelog covering every commit since the template was bootstrapped.

```sh
git tag -s v1.0.0 -m 'baseline: the site as it stood before versioned releases'
git push origin v1.0.0
```

Sign the tag if you can — `main` requires signed commits, and a signed baseline
keeps the chain consistent.
