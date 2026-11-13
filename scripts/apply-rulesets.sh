#!/usr/bin/env bash
#
# Apply the branch rulesets in .github/rulesets/ to this repository.
#
# These are server-side GitHub state, not files: committing them does nothing on
# its own. Run this after editing, or after creating the repository fresh.
#
#   nix shell nixpkgs#gh -c scripts/apply-rulesets.sh          # apply
#   nix shell nixpkgs#gh -c scripts/apply-rulesets.sh --dry-run # show only
#
# Idempotent: a ruleset with the same name is updated in place, otherwise created.
set -euo pipefail

REPO="${REPO:-Leoguy77/nixos-config}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.github/rulesets" && pwd)"
DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

command -v gh >/dev/null || {
	echo "gh not found — run inside: nix shell nixpkgs#gh -c $0" >&2
	exit 1
}

shopt -s nullglob
files=("$DIR"/*.json)
[ ${#files[@]} -gt 0 ] || {
	echo "no rulesets in $DIR" >&2
	exit 1
}

for f in "${files[@]}"; do
	name=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["name"])' "$f")

	# Match on name; ids are per-repository and change on recreate.
	existing_id=$(
		gh api "repos/$REPO/rulesets" \
			--jq ".[] | select(.name == \"$name\") | .id" 2>/dev/null | head -n1
	)

	if [ -n "$existing_id" ]; then
		echo "→ updating ruleset '$name' (id $existing_id)"
		[ "$DRY_RUN" = 1 ] && { echo "  (dry run) would PUT $(basename "$f")"; continue; }
		gh api --method PUT "repos/$REPO/rulesets/$existing_id" --input "$f" >/dev/null
	else
		echo "→ creating ruleset '$name'"
		[ "$DRY_RUN" = 1 ] && { echo "  (dry run) would POST $(basename "$f")"; continue; }
		gh api --method POST "repos/$REPO/rulesets" --input "$f" >/dev/null
	fi
done

echo
echo "Active rulesets on $REPO:"
# The list endpoint omits `rules`, so fetch each one to report what it enforces.
gh api "repos/$REPO/rulesets" --jq '.[].id' | while read -r id; do
	gh api "repos/$REPO/rulesets/$id" \
		--jq '"  \(.name) [\(.enforcement)] \(.rules | map(.type) | join(", "))"'
done
