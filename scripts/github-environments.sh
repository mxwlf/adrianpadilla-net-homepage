#!/usr/bin/env sh
# ---------------------------------------------------------------------------
# GitHub deployment environments as code
# ---------------------------------------------------------------------------
# Stores this repository's deployment environments as committed JSON in
# .github/environments/, and rebuilds them on any repo with the GitHub CLI.
# Same idea, and the same portability rules, as scripts/github-rulesets.sh.
#
#   apply   create/update the environments from .github/environments/
#   diff    report drift between the committed files and the live environments
#           (exits non-zero when they differ)
#   show    print the live configuration of each committed environment
#
# WHY THE APPROVAL GATE LIVES HERE: a `production` environment with a required
# reviewer is what makes a promotion pause for a human, and what makes GitHub
# record the result as a Deployment. Both are free on a public repository.
#
# WHAT IS PORTABLE, AND SO SAFE TO COMMIT: nothing account-scoped. Reviewers are
# committed as LOGINS under `_reviewer_logins` and resolved to numeric ids at
# apply time, because user ids are account-scoped — the same reason
# github-rulesets.sh refuses to commit `actor_type: Team` or user ids.
#
# Keys beginning with "_" are not sent to the API. That covers `_comment` (JSON
# has no comments), `_reviewer_logins`, and `_branch_policies` — the last
# because branch and tag policies are a separate collection endpoint rather than
# fields on the environment itself.
#
# WHY THIS IS NOT PART OF `make ci`: writing environments needs repo admin
# rights, which a workflow's default GITHUB_TOKEN does not have and cannot be
# granted via `permissions:`. Wiring `diff` into CI would fail for reasons
# unrelated to the code under test.
#
# Requires: `gh` (authenticated), python3, and a POSIX shell.
# Override the target repo with REPO=owner/name; it defaults to the checkout's.
# ---------------------------------------------------------------------------
set -eu

ENV_DIR=".github/environments"
PYTHON="${PYTHON:-python3}"

die() {
	printf 'Error: %s\n' "$*" >&2
	exit 1
}

command -v gh >/dev/null 2>&1 || die 'the GitHub CLI (gh) is required.'
command -v "$PYTHON" >/dev/null 2>&1 || die "$PYTHON is required."
[ -d "$ENV_DIR" ] || die "$ENV_DIR does not exist."

REPO="${REPO:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"
[ -n "$REPO" ] || die 'could not determine the repository. Set REPO=owner/name.'

# Reshapes a live environment into the same flat form the committed files use,
# so the two can be compared as text.
#
# The API does NOT echo back the fields you PUT. A PUT takes `wait_timer`,
# `prevent_self_review` and `reviewers` as top-level fields, but a GET returns
# them inside a `protection_rules` array, each as its own rule object, with
# reviewers expanded into full user objects. Reading the request shape back off
# the response finds nothing and silently reports every environment as empty.
NORMALIZE_PY='
import json, sys
d = json.load(sys.stdin)
out = {"wait_timer": 0, "prevent_self_review": False, "reviewers": []}
for rule in d.get("protection_rules") or []:
    kind = rule.get("type")
    if kind == "wait_timer":
        out["wait_timer"] = rule.get("wait_timer", 0)
    elif kind == "required_reviewers":
        out["prevent_self_review"] = rule.get("prevent_self_review", False)
        out["reviewers"] = sorted(
            ((r.get("reviewer") or {}).get("login") or "")
            for r in rule.get("reviewers") or []
        )
if d.get("deployment_branch_policy"):
    out["deployment_branch_policy"] = d["deployment_branch_policy"]
json.dump(out, sys.stdout, indent=2, sort_keys=True)
print()
'

# Renders a committed file into the body the API expects, resolving logins.
desired_body() {
	file="$1"
	logins=$("$PYTHON" -c '
import json, sys
print("\n".join(json.load(open(sys.argv[1])).get("_reviewer_logins") or []))
' "$file")

	ids=""
	for login in $logins; do
		id=$(gh api "users/$login" --jq .id) || die "could not resolve GitHub user '$login'."
		ids="$ids $id"
	done

	"$PYTHON" -c '
import json, sys
file, raw_ids = sys.argv[1], sys.argv[2].split()
d = json.load(open(file))
body = {k: v for k, v in d.items() if not k.startswith("_")}
body["reviewers"] = [{"type": "User", "id": int(i)} for i in raw_ids]
json.dump(body, sys.stdout)
' "$file" "$ids"
}

# The same body, but shaped like the API response so `diff` compares like with
# like: reviewers as logins rather than ids.
desired_normalized() {
	"$PYTHON" -c '
import json, sys
d = json.load(open(sys.argv[1]))
out = {
    "wait_timer": d.get("wait_timer", 0),
    "prevent_self_review": d.get("prevent_self_review", False),
    "reviewers": sorted(d.get("_reviewer_logins") or []),
}
if d.get("deployment_branch_policy"):
    out["deployment_branch_policy"] = d["deployment_branch_policy"]
json.dump(out, sys.stdout, indent=2, sort_keys=True)
print()
' "$1"
}

env_names() {
	for file in "$ENV_DIR"/*.json; do
		[ -e "$file" ] || continue
		basename "$file" .json
	done
}

apply_branch_policies() {
	name="$1" file="$2"

	# The collection is replaced wholesale: delete what is there, add what the
	# file asks for. Policies have server-assigned ids, so there is nothing
	# stable to update in place.
	existing=$(gh api "repos/$REPO/environments/$name/deployment-branch-policies" \
		--jq '.branch_policies[].id' 2>/dev/null || true)
	for id in $existing; do
		gh api --method DELETE \
			"repos/$REPO/environments/$name/deployment-branch-policies/$id" >/dev/null
	done

	# Plain concatenation rather than an f-string: this source is inside a
	# single-quoted shell string, so the escaped quotes an f-string would need
	# reach Python as literal backslashes and fail to parse.
	"$PYTHON" -c '
import json, sys
for p in json.load(open(sys.argv[1])).get("_branch_policies") or []:
    sys.stdout.write(p["name"] + "\t" + p.get("type", "branch") + "\n")
' "$file" | while IFS="$(printf '\t')" read -r pattern type; do
		[ -n "$pattern" ] || continue
		gh api --method POST \
			"repos/$REPO/environments/$name/deployment-branch-policies" \
			-f "name=$pattern" -f "type=$type" >/dev/null
		printf '    policy: %s (%s)\n' "$pattern" "$type"
	done
}

cmd_apply() {
	for name in $(env_names); do
		file="$ENV_DIR/$name.json"
		printf 'apply %s\n' "$name"
		desired_body "$file" |
			gh api --method PUT "repos/$REPO/environments/$name" --input - >/dev/null
		apply_branch_policies "$name" "$file"
	done
}

cmd_show() {
	for name in $(env_names); do
		printf '=== %s\n' "$name"
		gh api "repos/$REPO/environments/$name" | "$PYTHON" -c "$NORMALIZE_PY"
		gh api "repos/$REPO/environments/$name/deployment-branch-policies" \
			--jq '.branch_policies[] | "    policy: \(.name) (\(.type))"' 2>/dev/null || true
	done
}

cmd_diff() {
	status=0
	work=$(mktemp -d)
	# shellcheck disable=SC2064 # expand $work now, not at exit
	trap "rm -rf '$work'" EXIT

	for name in $(env_names); do
		file="$ENV_DIR/$name.json"

		# A missing environment normalizes to {}, which diffs against the
		# committed file and reports as drift rather than crashing.
		if ! gh api "repos/$REPO/environments/$name" >"$work/live.raw" 2>/dev/null; then
			printf '{}' >"$work/live.raw"
		fi
		"$PYTHON" -c "$NORMALIZE_PY" <"$work/live.raw" >"$work/live"
		desired_normalized "$file" >"$work/desired"

		if diff -u --label "live: $name" "$work/live" --label "$file" "$work/desired"; then
			printf 'ok %s\n' "$name"
		else
			status=1
		fi
	done

	return "$status"
}

case "${1:-}" in
apply) cmd_apply ;;
diff) cmd_diff ;;
show) cmd_show ;;
*) die 'usage: github-environments.sh apply|diff|show' ;;
esac
