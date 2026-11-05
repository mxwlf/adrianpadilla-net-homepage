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

### The test environment

`infra/test/` describes `test.adrianpadilla.net` in OpenTofu. Install it with
`brew install opentofu`; it is a separate toolchain and `make setup` does not
provide it.

**1. A resource group, created by hand.** In its own subscription, separate from
production. OpenTofu references the group rather than creating it, so it never
holds delete authority over the group itself.

**2. State storage.** This is the one thing OpenTofu cannot create, because it is
where OpenTofu keeps its state:

```sh
SUBSCRIPTION_ID=<test subscription guid> \
RESOURCE_GROUP=<the group from step 1> \
make tf-bootstrap
```

The account is created with `--allow-shared-key-access false`, so the only way
to reach the state is an Entra identity holding a data-plane role. There is no
storage key to leak or rotate. The script grants your own identity, writes
`infra/test/backend.config`, and enables blob versioning plus 30-day soft delete.

**3. Variables.**

```sh
cp infra/test/terraform.tfvars.example infra/test/terraform.tfvars
# fill in subscription_id and resource_group_name
make tf-plan
```

**4. Apply, then the one DNS record.** The first apply happens in two passes,
because the CNAME cannot be created until the Static Web App exists and its
Azure hostname is known:

```sh
make tf-apply                 # creates the Static Web App; custom domain fails
tofu -chdir=infra/test output cname_record_to_create
```

Create that CNAME in the `adrianpadilla.net` zone — which lives in the
`connectivity` subscription, resource group `dns-prod` — then `make tf-apply`
again to bind the custom domain.

**This record is deliberately not managed by OpenTofu.** That zone also serves
the apex records for the live site plus `git`, `id`, `ntfy`, `codenomad`,
`macwolf`, `ief-replay`, the DKIM selectors and a Tailscale challenge. Granting
the deploy identity `DNS Zone Contributor` there would let a bad plan delete all
of it, so it holds no DNS permissions at all. The record never changes once
created.

Delegating `test.adrianpadilla.net` as its own zone would avoid the manual step,
and was rejected: it makes the hostname a zone apex, which forces Azure's
`dns-txt-token` validation — documented as not waited on, so OpenTofu would
report success without confirming — and a zone apex cannot hold a CNAME, while
Azure DNS cannot point an ALIAS record at a Static Web App.

### A note on `infra.yml`

It carries `paths:` filters, so it does not run on every pull request. It must
therefore **never** be made a required status check: a required check that is
not reported leaves every unrelated pull request waiting on it forever.
