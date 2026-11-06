# Deployment

How a change reaches `adrianpadilla.net`.

```
PR ──▶ develop ──▶ release PR ──▶ merge ──▶ tag + GitHub Release
                                                   │
                                        ONE build (release.yml)
                                 site/ + reports/ + sbom/ + SHA256SUMS
                                      + build provenance attestation
                                                   │
                                                   ▼
                                           test (automatic)
                                        test.adrianpadilla.net
                                   rebuilt + DNS repointed if torn down
                                                   ┊
                      ┉┉┉┉┉┉┉┉┉┉┉┉┉┉┉┉┉┉┉┉┉┉┉┉┉┉┉┉┉┊┉┉┉┉┉┉┉┉┉┉┉┉┉┉┉┉┉┉┉┉┉
                      ┊   no automatic path crosses this line           ┊
                      ┉┉┉┉┉┉┉┉┉┉┉┉┉┉┉┉┉┉┉┉┉┉┉┉┉┉┉┉┉┊┉┉┉┉┉┉┉┉┉┉┉┉┉┉┉┉┉┉┉┉┉
                                                   ┊
                             you dispatch, then you approve
                                                   ▼
                                             production
                                          adrianpadilla.net
```

## What triggers what

This section covers the two workflows that deploy. For every workflow, every
job, and what each one actually executes once the `make` targets are expanded,
see [`pipeline-map.md`](pipeline-map.md).

The most important thing to know: **nothing you merge can reach production.**

| Workflow           | Trigger                      | Deploys to                                                |
| ------------------ | ---------------------------- | --------------------------------------------------------- |
| `release.yml`      | `release: published`         | **test** — environment has no reviewers, so it just goes  |
| `promote-prod.yml` | **`workflow_dispatch` only** | **production** — environment requires your approval first |
| `test-env.yml`     | **`workflow_dispatch` only** | nothing — it creates or destroys the test environment     |

`promote-prod.yml` has no `push`, no `release`, no `schedule`. Production has no
automatic trigger of any kind, and reaching it takes two deliberate acts that
cannot be done by accident: you dispatch the workflow, and then you approve the
run it creates.

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

5. **It stops there.** Merging the release pull request does not deploy to
   production, and neither does anything else you merge. Production is a
   separate, manual decision — see below.

Verify an artifact came from this pipeline:

```sh
gh release download v1.1.0 --pattern 'release-*.tar.gz'
gh attestation verify --owner mxwlf release-1.1.0.tar.gz
```

## Promoting to production

Two deliberate acts, both yours:

1. **Actions → Promote to production → Run workflow**, entering a version
   without the leading `v` (e.g. `1.0.1`). The workflow validates that before
   doing anything slow, so a typo costs seconds rather than an approval.
2. The run **pauses** on the `production` environment until you approve it.
   GitHub records the result as a Deployment.

It then downloads that version's published asset, verifies the provenance
attestation and the digests, deploys, smoke-tests the live site, and — only on
success — advances `main` to the promoted commit.

**The version you promote is a separate decision from the version you
released.** That is the point of the split, and it buys two things:

- A release can sit in test as long as you like before going live.
- **Rollback is a promotion of an earlier version**, not a revert commit and a
  rebuild. `make package` is never re-run, so an older promotion ships exactly
  the bytes that were verified when it was built.

```sh
gh release list                          # what is promotable
gh workflow run promote-prod.yml -f version=1.0.1
```

Two details worth knowing:

- **`prevent_self_review` is `false`** on the `production` environment, and has
  to be: on a one-maintainer repository you are both the person dispatching and
  the only approver, so requiring a second pair of eyes would make the gate
  unsatisfiable rather than strict. It stops an _accidental_ promotion, not a
  determined one — the same honest limitation as the admin ruleset bypass.
- **The first promotion is a bigger step than later ones.** Production served
  the last Oryx-built deploy from before the old workflow was retired, so the
  first promotion is the first time it receives a hash-verified artifact, and
  the content digest changes.

## The test environment is disposable

The test environment exists to be looked at while a release is under
consideration. Between releases it does not have to exist at all, so it can be
torn down and the next release puts it back.

```sh
make test-env-status     # is it up, and where does its DNS point
make test-env-teardown   # destroy the app, park test.adrianpadilla.net
make test-env-restore    # rebuild it, point the DNS back
```

Or from GitHub: **Actions → Test environment → Run workflow**, choosing
`teardown`, `restore` or `status`. A teardown additionally requires the word
`teardown` typed into the confirm box; the dropdown alone is one click.

| What                               | Teardown                                             |
| ---------------------------------- | ---------------------------------------------------- |
| The Static Web App                 | destroyed                                            |
| Its resource group                 | **untouched**                                        |
| The OpenTofu state storage account | **untouched**                                        |
| `test.adrianpadilla.net`           | repointed at production                              |
| `vars.TEST_*`                      | unchanged — the app's name is stable across rebuilds |

**The resource group surviving is structural, not careful.** `infra/test/` reads
the group with a `data` block, so it is not in the state file and `tofu destroy`
has nothing to delete. The state storage account is not in the configuration at
all. `make test-env-teardown` asserts the first of those — it refuses to run if
a managed `azurerm_resource_group` ever appears in the state — rather than
trusting that nobody changed it.

### Restore is what a deployment does

`release.yml` runs `make test-env-restore` in its own `ensure-test` job before
`deploy-test`, so **deploying to test is what switches the DNS back.** There is
no separate step to remember and no state to get wrong: the target is idempotent,
so on a release where the environment was already up it costs one no-op apply
and one DNS read.

A restore is two applies, for the same reason the first-ever apply was:
`azurerm_static_web_app_custom_domain` validates by `cname-delegation`, so the
CNAME has to resolve to the app's Azure hostname before the binding can be
created — and that hostname is not known until the app exists. It then waits for
Azure to report the binding `Ready`, which is when the certificate has been
issued; without that wait the smoke test in `deploy-test` would hit a cold
hostname and fail the TLS handshake, which looks nothing like the cold
certificate it actually is.

Both workflows share a `test-env` concurrency group. A teardown landing between
a restore's two applies would leave the record pointing at an app that no longer
exists.

### Why DNS is automated now, and why that is still narrow

The record used to be made by hand on the grounds that it never changes. **It
changes now.** A destroyed Static Web App releases its `*.azurestaticapps.net`
hostname and a rebuilt one is assigned a new one, so the CNAME moves on every
teardown and every restore. Leaving it aimed at a released Azure hostname is the
textbook dangling-CNAME subdomain takeover: whoever next claims that hostname
serves content on our domain.

So the test deploy identity does now hold a DNS permission — at **record set
scope**, not zone scope:

Have an `az` context in **your own** tenant before running this, not a work
one. `az ad sp show` resolves against the _active_ tenant regardless of
`--subscription`, so with the wrong one selected it reports that the app does
not exist — the same trap `scripts/tf-bootstrap.sh` guards against.

```sh
DNS_SUB=42cb3155-85e5-4646-8110-a3aa3d02460d   # the connectivity subscription
az account set --subscription "$DNS_SUB"

# Derived from the published client id rather than written down, so it cannot
# go stale if the app registration is ever recreated.
TEST_SP=$(az ad sp show --id "$(gh variable get TEST_AZURE_CLIENT_ID)" --query id --output tsv)

az role assignment create \
  --assignee-object-id "$TEST_SP" \
  --assignee-principal-type ServicePrincipal \
  --role 'DNS Zone Contributor' \
  --scope "/subscriptions/$DNS_SUB/resourceGroups/dns-prod/providers/Microsoft.Network/dnsZones/adrianpadilla.net/CNAME/test"
```

That grant can write exactly one record set. It cannot read, change or delete
the apex, `www`, `git`, `id`, `ntfy`, `codenomad`, `macwolf`, `ief-replay`, the
DKIM selectors or the Tailscale challenge, and it cannot enumerate the zone. The
original objection to managing DNS here was blast radius, and at this scope the
blast radius is the one record we already intended to change. The **production**
identity is a different app registration and still holds no DNS permission of
any kind.

`scripts/test-env.sh` only ever calls `set-record`, never `delete`, so the record
set stays in existence through a teardown. It also refuses any record name that
is not a single plain label — `@` and `*` are rejected before `az` is invoked.

### "Parked" does not mean "redirected"

A teardown points `test.adrianpadilla.net` at `www.adrianpadilla.net`. That is a
**parking record**: it makes the name resolve into production and removes the
takeover risk, which is the property worth having.

**It does not produce a 301.** Production is also Free SKU, and the Free SKU
allows two custom domains — both already spent, on the apex and `www`. Nothing
in production is bound to `test.adrianpadilla.net`, so an HTTPS request to it
fails the certificate check rather than being redirected. A browser-visible
redirect needs something that terminates TLS for that name, and there are only
three ways to get one:

- **Move production to Standard** (five custom domains) and bind
  `test.adrianpadilla.net` to it. This is the obvious option and it is a trap:
  `staticwebapp.config.json` cannot match on `Host`, so the production app would
  **serve production's content** on the test hostname, with production's
  canonical URLs and without the `X-Robots-Tag: noindex` that exists precisely
  to stop that. It trades a dead name for a duplicate-content problem.
- **Keep a separate redirect host alive.** A correct 301, and no longer a
  teardown — there is always something running.
- **Leave it parked.** What this implements.

If a visible redirect is wanted later, the second option is the only one that
does not damage production's SEO, and it should be its own change.

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
make tf-bootstrap INFRA_ENV=test
```

The account is created with `--allow-shared-key-access false`, so the only way
to reach the state is an Entra identity holding a data-plane role. There is no
storage key to leak or rotate. The script grants your own identity, writes
`infra/<env>/backend.config`, and enables blob versioning plus 30-day soft delete.

**Pass `INFRA_ENV`, and have the right subscription active.** Every
environment-specific value — the `backend.config` written, the state key inside
the container, the default storage account name — is derived from it. The script
also refuses to run when your active `az` context is in a different tenant from
the target subscription, which is not a theoretical guard: `az account show
--subscription X` happily reads across tenants, but every `az ad` lookup resolves
against the _active_ one. Bootstrapping production with a work account selected
read that directory's signed-in user, tried to grant a foreign object id, and
failed into a message saying the role was probably already assigned. The state
storage came out with no data-plane role on it at all, and the script exited 0.

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

After the first one, `make test-env-restore` writes that record for you. The
hand-made pass is only needed before the record set exists at all, because the
record-set-scoped role below is granted on a path that has to be there to be
granted on.

**This record is deliberately not managed by OpenTofu**, and it is not hand-made
any more either. That zone also serves the apex records for the live site plus
`git`, `id`, `ntfy`, `codenomad`, `macwolf`, `ief-replay`, the DKIM selectors
and a Tailscale challenge. Granting the deploy identity `DNS Zone Contributor`
over the **zone** would let a bad plan delete all of it. It is granted over the
single `CNAME/test` **record set** instead, and `scripts/test-env.sh` writes it
with `az` — see
[Why DNS is automated now](#why-dns-is-automated-now-and-why-that-is-still-narrow).

The claim that "the record never changes once created" was true until the
teardown pipeline existed. It changes on every teardown and restore, because a
rebuilt Static Web App is assigned a new `*.azurestaticapps.net` hostname.

Delegating `test.adrianpadilla.net` as its own zone would avoid the manual step,
and was rejected: it makes the hostname a zone apex, which forces Azure's
`dns-txt-token` validation — documented as not waited on, so OpenTofu would
report success without confirming — and a zone apex cannot hold a CNAME.

An earlier version of this page also claimed Azure DNS cannot point an ALIAS
record at a Static Web App. **That is wrong**, and the proof is in this zone:
`adrianpadilla.net` itself is an ALIAS `A` record whose `targetResource` is the
production Static Web App, which is exactly how the apex is served. The reason
DNS stays out of OpenTofu is blast radius, not capability.

### The production environment

`infra/prod/` describes `adrianpadilla.net` and `www.adrianpadilla.net`, and is
deliberately the same shape as `infra/test/`. Every target takes the
environment, defaulting to `test`:

```sh
make tf-plan  INFRA_ENV=prod
make tf-apply INFRA_ENV=prod
```

**Why production was rebuilt rather than imported.** The original production app
was made by hand in the portal, and it stopped accepting token deploys: the
content server answered `No matching Static Web App was found or the api key was
invalid` to a freshly fetched key, in CI and from a laptop alike, while the
OpenTofu-created test app accepted the identical command. Two rounds of
diagnosis found no cause — only differences we could enumerate but not account
for: a stale GitHub source-control link, no tags, an unset
`publicNetworkAccess`. Importing would have carried whatever that was into the
new state file, so the app was rebuilt from the configuration that demonstrably
works. The replacement accepted the first deploy it was given.

The resource group was renamed in the same move, from
`adrianpadilla-net-homepage_group` to `adrianpadilla-net-homepage-prod-rg`, to
match the test environment's naming.

**What production adds over test.** One setting, and it has a scar behind it:

```hcl
preview_environments_enabled = false
```

The retired pull-based workflow's header recorded staging environments that
Azure created from branch pushes and never tore down. They filled the Free
plan's three environment slots and broke production deploys outright. Promotion
always deploys `--env production`, so the ability to create a preview
environment is pure downside here. See
[Preview environments](#preview-environments-do-not-re-enable-them-casually).

**What is not in `infra/prod/`.** No DNS, for the blast-radius reason above. And
no apex custom domain binding: an apex must validate by `dns-txt-token`, which
the provider documents as a path it does not wait on, so OpenTofu would mark it
created without confirming. Only `cname-delegation` is polled, so `www` is
managed here and the apex binding is made by hand, once.

#### Runbook: moving the live domains to a new Static Web App

A hostname can be bound to only one Static Web App at a time, so a cutover
cannot be done with a single apply, and there is no zero-downtime path on the
Free SKU. Budget a few minutes, and run it in this order.

Lower both TTLs **first**. This does nothing for resolvers that have already
cached the records — they hold the old value for up to the previous TTL, an hour
in our case — but it makes the next cutover, and any correction you need in the
following minutes, cheap:

```sh
DNS_SUB=42cb3155-85e5-4646-8110-a3aa3d02460d   # the connectivity subscription
az network dns record-set a update     --subscription $DNS_SUB -g dns-prod \
  -z adrianpadilla.net -n @   --set ttl=60
az network dns record-set cname update --subscription $DNS_SUB -g dns-prod \
  -z adrianpadilla.net -n www --set ttl=60
```

1. **Create the app only.** The `www` binding would fail on a first pass,
   because the hostname is still held by the old app:

   ```sh
   make tf-apply INFRA_ENV=prod TF_ARGS='-target=azurerm_static_web_app.prod'
   tofu -chdir=infra/prod output dns_records_to_create
   ```

2. **Deploy and verify on the Azure hostname, before touching DNS.** This is the
   step that makes the cutover safe: if the new app cannot serve the release,
   you find out while the live site is still untouched.

   ```sh
   gh release download v<version> --dir /tmp/cut/dl
   gh attestation verify /tmp/cut/dl/release-<version>.tar.gz --owner mxwlf
   tar -xzf /tmp/cut/dl/release-<version>.tar.gz -C /tmp/cut/package
   ( cd /tmp/cut/package && shasum -a 256 -c SHA256SUMS )

   TOKEN=$(az staticwebapp secrets list --subscription "$PROD_SUB" \
     --resource-group adrianpadilla-net-homepage-prod-rg \
     --name adrianpadilla-net-homepage-prod --query properties.apiKey -o tsv)

   npx @azure/static-web-apps-cli deploy /tmp/cut/package/site \
     --swa-config-location /tmp/cut/package/host-config/prod \
     --deployment-token "$TOKEN" --env production
   ```

   Then check the `*.azurestaticapps.net` hostname it prints: 200, the expected
   footer version, a canonical pointing at `adrianpadilla.net`, and **no**
   `X-Robots-Tag` (that header belongs to test alone).

3. **Release the hostnames from the old app.** Azure warns that this takes up to
   15 minutes to propagate, and the new binding will be rejected until it has.
   Wait for the old app to report zero custom domains rather than guessing:

   ```sh
   for d in adrianpadilla.net www.adrianpadilla.net; do
     az staticwebapp hostname delete --name <old app> \
       --resource-group <old rg> --hostname "$d" --yes --no-wait
   done
   ```

4. **Repoint DNS.** The apex is an ALIAS `A` record targeting the Static Web App
   _resource_; `www` is an ordinary CNAME to its Azure hostname:

   ```sh
   az network dns record-set a update --subscription $DNS_SUB -g dns-prod \
     -z adrianpadilla.net -n @ --target-resource "$NEW_SWA_RESOURCE_ID"
   az network dns record-set cname set-record --subscription $DNS_SUB -g dns-prod \
     -z adrianpadilla.net -n www --cname "$NEW_DEFAULT_HOST_NAME"
   ```

5. **Bind the hostnames on the new app.** `www` through OpenTofu, the apex by
   hand:

   ```sh
   make tf-apply INFRA_ENV=prod          # binds www by cname-delegation
   az staticwebapp hostname set --name adrianpadilla-net-homepage-prod \
     --resource-group adrianpadilla-net-homepage-prod-rg \
     --hostname adrianpadilla.net
   ```

   Both end up with `validationMethod: None`, because the ALIAS and CNAME
   records are themselves the proof of ownership — no TXT token is involved when
   the zone is in Azure DNS.

6. **Update the repository variables and the RBAC**, or the next promotion
   deploys to the app you just retired:

   ```sh
   gh variable set PROD_RESOURCE_GROUP      --body 'adrianpadilla-net-homepage-prod-rg'
   gh variable set PROD_STATIC_WEB_APP_NAME --body 'adrianpadilla-net-homepage-prod'
   ```

   The deploy identity needs `Contributor` on the new group. Leave its
   assignment on the old group until the old app is deleted, then remove both
   together.

7. **Keep the old app for a few days.** It is the rollback: rebinding the
   domains to it is the same procedure in reverse. Delete it, and its role
   assignment, once the new one has proven itself.

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
  # Nothing outside this one resource group.
  az role assignment create --assignee-object-id "$sp_id" \
    --assignee-principal-type ServicePrincipal --role Contributor \
    --scope "/subscriptions/$2/resourceGroups/$3" >/dev/null

  echo "$1: app=$app_id sp=$sp_id"
}

make_identity test       '<test subscription guid>'                '<test resource group>'
make_identity production '0af99616-1635-473a-8cbb-9ceb60f73388'    'adrianpadilla-net-homepage-prod-rg'
```

**The test identity needs one role outside that group**, and production does
not: `DNS Zone Contributor` on the `CNAME/test` record set in the
`adrianpadilla.net` zone, so teardown and restore can move
`test.adrianpadilla.net`. The grant and the reasoning are in
[Why DNS is automated now](#why-dns-is-automated-now-and-why-that-is-still-narrow).
Production holds no DNS permission of any kind, which is why the apex binding is
still done by hand.

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

The test environment's teardown and restore need five more. The first names the
state storage account, which `release.yml` and `test-env.yml` write into
`infra/test/backend.config` at run time — that file is git-ignored, so it is not
checked out:

```sh
gh variable set TEST_TFSTATE_STORAGE_ACCOUNT --body 'apnhtfstate'
gh variable set DNS_SUBSCRIPTION_ID          --body '42cb3155-85e5-4646-8110-a3aa3d02460d'
gh variable set DNS_RESOURCE_GROUP           --body 'dns-prod'
gh variable set DNS_ZONE                     --body 'adrianpadilla.net'
gh variable set TEST_DNS_RECORD_NAME         --body 'test'
gh variable set TEST_PARKED_CNAME            --body 'www.adrianpadilla.net'
```

`scripts/test-env.sh` defaults every one of those except `DNS_SUBSCRIPTION_ID`
to the value above, so a local `make test-env-status` needs only that one
exported. They are repository variables anyway, so the workflows do not depend
on the script's defaults staying correct.

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

`test` allows two refs: the `v*` tags `release.yml` deploys from, and the
`develop` branch, because `test-env.yml` is dispatched manually and so runs on a
branch ref. Without the second, a teardown fails before it starts with "Branch
is not allowed to deploy to test" — a message that reads like a permissions
problem rather than a branch policy.

### Production: variables and the `main` bypass

One-time setup only. How to actually promote is in
[Promoting to production](#promoting-to-production) above; this section covers
what has to exist before the first one works.

Production needs its own repository variables:

```sh
gh variable set PROD_SUBSCRIPTION_ID     --body '0af99616-1635-473a-8cbb-9ceb60f73388'
gh variable set PROD_RESOURCE_GROUP      --body 'adrianpadilla-net-homepage-prod-rg'
gh variable set PROD_STATIC_WEB_APP_NAME --body 'adrianpadilla-net-homepage-prod'
```

The deploy identity also needs `Contributor` on that resource group, and a
federated credential for `<sub_claim_prefix>:environment:production` (see the immutable-subject note above)
(created alongside the test one above).

**The one control this design costs.** `main` accepts only reviewed pull
requests, and the `record` job advances it by calling the merges API, which the
ruleset refuses. For it to work, the release GitHub App must be listed in
`main-protection.json`'s `bypass_actors` with `bypass_mode: "always"`:

The bypass actor's `actor_id` is the App's id -- the same number as
`vars.RELEASE_APP_ID`, 5622267 here, with `actor_type: "Integration"`. Note that
`gh api repos/OWNER/REPO/installation` cannot tell you this: that endpoint needs
a JWT signed by the App's private key, and answers 401 to a user token.

```sh
gh variable get RELEASE_APP_ID   # the id to use as actor_id
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
