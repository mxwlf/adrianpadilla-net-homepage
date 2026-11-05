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
   with a provenance attestation, and then -- in a second job that `needs:` the
   first -- deploys it to the test environment. The two are one workflow on
   purpose: as separate workflows both fired on `release: published` and the
   deploy raced the build whose asset it downloads.

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

- **Repository permissions:** Contents `read & write`, Issues `read & write`,
  Pull requests `read & write`, Workflows `read & write`.
  - **Issues is not optional and is easy to miss.** release-please moves the
    release pull request's label from `autorelease: pending` to
    `autorelease: tagged`, and labels go through the issues API. Without it the
    action fails at "Creating 1 releases" with an _empty_ error message, having
    created no tag and no Release — which is as unhelpful as it sounds.
  - Workflows is for the `record` job: its `develop` → `main` merges carry
    changes under `.github/workflows/`, which a GitHub App cannot push without
    that permission.
- **Adding a permission after installing requires approving it.** GitHub keeps
  issuing tokens with the old permission set until the installation itself
  accepts the change (Install App → the installation's settings → review the
  request).
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

### The deploy identity, with no stored credentials

Deployments authenticate to Azure by **workload identity federation**: GitHub
mints a short-lived OIDC token, Azure trusts it for a specific subject, and no
client secret or storage key exists anywhere.

**One app registration per environment.** This matters, and the obvious shortcut
is wrong: a federated credential's `subject` claim gates only the **token
exchange**. Once exchanged, the access token belongs to the service principal,
whose RBAC is the same no matter which credential matched. A single app trusted
for both `environment:test` and `environment:production`, holding `Contributor`
on both resource groups, would let the `test` job — which needs **no approval**
— read production's deployment token and deploy to the live site. The approval
gate would be decorative.

So: two apps, each trusted for exactly one environment and granted rights in
exactly one subscription.

**Do not hand-write the subject.** This repository has GitHub's **immutable
subject claims** enabled, so the token does not present
`repo:OWNER/REPO:environment:test` — it embeds the numeric owner and repository
ids:

```console
$ gh api repos/mxwlf/adrianpadilla-net-homepage/actions/oidc/customization/sub
{"use_default":true,"use_immutable_subject":true,
 "sub_claim_prefix":"repo:mxwlf@2484521/adrianpadilla-net-homepage@1314357660"}
```

A credential written in the documented `repo:OWNER/REPO:...` form is simply
never matched, and Entra says so in the only place you will see it — the deploy
job:

> AADSTS700213: No matching federated identity record found for presented
> assertion subject `repo:mxwlf@2484521/adrianpadilla-net-homepage@1314357660:environment:test`

That is worth matching rather than turning off: embedding the ids is what stops
a deleted-and-recreated repository of the same name inheriting this trust. Read
the prefix from the API below rather than typing it, so a rename or a transfer
cannot silently invalidate it.

```sh
TENANT=6dbf3e28-8c7c-41fe-b397-a347b389a329
REPO=mxwlf/adrianpadilla-net-homepage

# The prefix GitHub will actually present. Never hand-written.
SUB_PREFIX=$(gh api "repos/${REPO}/actions/oidc/customization/sub" --jq .sub_claim_prefix)

# $1 = environment name, $2 = subscription guid, $3 = resource group
make_identity() {
  app_id=$(az ad app create --display-name "github-apnh-$1" \
    --query appId --output tsv)
  az ad sp create --id "$app_id" >/dev/null

  az ad app federated-credential create --id "$app_id" --parameters "{
    \"name\": \"github-env-$1\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"${SUB_PREFIX}:environment:$1\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }" >/dev/null

  sp_id=$(az ad sp show --id "$app_id" --query id --output tsv)

  # Manage that environment's Static Web App and read its deployment token.
  # Nothing outside this one resource group, and no DNS role anywhere.
  az role assignment create --assignee-object-id "$sp_id" \
    --assignee-principal-type ServicePrincipal --role Contributor \
    --scope "/subscriptions/$2/resourceGroups/$3" >/dev/null

  echo "$1: app=$app_id sp=$sp_id"
}

make_identity test       '<test subscription guid>'                '<test resource group>'
make_identity production '0af99616-1635-473a-8cbb-9ceb60f73388'    'adrianpadilla-net-homepage_group'
```

The two client ids are published as separate variables
(`TEST_AZURE_CLIENT_ID`, `PROD_AZURE_CLIENT_ID`), so the separation is visible in
the workflow rather than resting on a claim in this document.

What the environment approval actually buys you, stated precisely: it prevents a
job from **running** in the `production` environment without a human, and only a
job running there can exchange a token for the production principal. The
isolation comes from the disjoint RBAC above; the approval is what stops the
exchange happening at all.

For OpenTofu state, pass the **test** principal's object id as
`CI_PRINCIPAL_ID` to `make tf-bootstrap`, which scopes
`Storage Blob Data Contributor` to the state container alone.

### Repository variables

Set once, after `make tf-apply` (the values come from `tofu output`):

```sh
gh variable set AZURE_TENANT_ID           --body "$TENANT"
gh variable set TEST_AZURE_CLIENT_ID    --body "<test app id>"
gh variable set PROD_AZURE_CLIENT_ID    --body "<production app id>"
gh variable set TEST_SUBSCRIPTION_ID      --body "$TEST_SUB"
gh variable set TEST_RESOURCE_GROUP       --body "$(tofu -chdir=infra/test output -raw resource_group_name)"
gh variable set TEST_STATIC_WEB_APP_NAME  --body "$(tofu -chdir=infra/test output -raw static_web_app_name)"
gh variable set TEST_HOSTNAME             --body 'test.adrianpadilla.net'
```

These are **variables, not secrets**. None of them is confidential — a client id
and a subscription id are identifiers, not credentials, and the thing that
actually authorises a deployment is the federated subject plus the environment's
approval rule.

### The deployment environments

```sh
make environments-apply   # create them from .github/environments/
make environments-diff    # fail if GitHub has drifted
make environments-show    # print the live configuration
```

`production` carries a required reviewer; `test` deliberately carries none.
Reviewers are committed as **logins** and resolved to numeric ids at apply time,
because user ids are account-scoped — the same portability rule
`scripts/github-rulesets.sh` documents.

### Production promotion, and the `main` bypass

Promote with **Actions → Promote to production → Run workflow**, giving a
version. The run pauses for the `production` environment's required reviewer;
approving it is the explicit OK, and GitHub records the result as a Deployment.

Any published version can be promoted, so **a rollback is a promotion of an
earlier version** — not a revert commit and a rebuild.

Production needs its own repository variables:

```sh
gh variable set PROD_SUBSCRIPTION_ID     --body '0af99616-1635-473a-8cbb-9ceb60f73388'
gh variable set PROD_RESOURCE_GROUP      --body 'adrianpadilla-net-homepage_group'
gh variable set PROD_STATIC_WEB_APP_NAME --body 'adrianpadilla-net-homepage'
```

The deploy identity also needs `Contributor` on that resource group, and a
federated credential for `<sub_claim_prefix>:environment:production` (see the immutable-subject note above)
(created alongside the test one above).

**The one control this design costs.** `main` accepts only reviewed pull
requests, and the `record` job advances it by calling the merges API, which the
ruleset refuses. For it to work, the release GitHub App must be listed in
`main-protection.json`'s `bypass_actors` with `bypass_mode: "always"`:

```sh
# APP_ID here is the App's *installation* integration id, not the app id used
# by create-github-app-token. Find it with:
gh api "repos/mxwlf/adrianpadilla-net-homepage/installation" --jq '.app_id'
```

Add it through **Settings → Rules → main-protection → Bypass list**, then run
`make rulesets-export` to bring the change back into the repository — otherwise
the next `make rulesets-apply` silently reverts it.

This genuinely weakens `main`, in two ways rather than one. An identity gains
the ability to write to it outside a pull request, which nothing could do
before — and because ruleset bypass is per-ruleset rather than per-rule, that
same entry also skips `required_signatures`. `required_signatures` checks every
commit a push introduces, so the `record` merge brings release-please's unsigned
commits onto `main` as ancestors; it succeeds by bypassing the rule, not by
satisfying it. `main` is therefore not fully signed once this job is installed.
What stays true is that **no human reaches `main` except through a reviewed pull
request whose own commits are signed.** An App rather than a
personal access token is the mitigation — scoped to this repository, visible in
the audit log, and revocable in one click. If that trade is not worth it, drop
the `record` job: the release tag and the Deployment record already state what
is live, and `main` simply stops tracking it.

Until the bypass is in place the `record` job fails with a 403 while `promote`
stays green. That is intentional: production _is_ updated at that point, and a
stale `main` should not look like a failed deploy.

### Preview environments: do not re-enable them casually

The retired `azure-static-web-apps-*.yml` workflow carried this history, which
is worth keeping:

> Previews were removed because Azure could create them but never tear them
> down. The close action authenticated (it printed a DeploymentId) and then the
> content server answered "No matching static site found", on this app, every
> time. The deployment token was valid, `repositoryUrl`, `provider` and `branch`
> all matched the repo, and passing the `repo_token` the action's container
> expects changed nothing. The environments for merged PRs 7, 13, 14, 29 and 30
> all had to be deleted by hand.
>
> With a Free plan's 3 staging slots, that leak filled the quota and then failed
> every deploy with "This Static Web App already has the maximum number of
> staging environments" — so a broken preview teardown was taking production
> deploys down with it.

If previews are ever wanted back, the teardown cannot rely on that action:
delete environments with `az staticwebapp environment delete` from a scheduled
job authenticated by OIDC.

Both deploy workflows now end by asserting that no non-default environment
exists, and the promotion passes `production_branch` explicitly — the action
classifies a deploy as a _preview_ when it believes the current branch is not
the production one, and a dispatched workflow runs on whatever ref it was
started from.

### A note on `infra.yml`

It carries `paths:` filters, so it does not run on every pull request. It must
therefore **never** be made a required status check: a required check that is
not reported leaves every unrelated pull request waiting on it forever.
