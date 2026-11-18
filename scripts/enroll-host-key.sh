#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
#  scripts/enroll-host-key.sh — mint a host key and make it a sops recipient
# ──────────────────────────────────────────────────────────────
# Usage:
#   scripts/enroll-host-key.sh <host> [--out DIR]
#
#   host   hosts/<host>/ ; becomes the &<host> anchor in .sops.yaml
#   --out  where to put ssh_host_ed25519_key (default: a fresh mktemp dir).
#          The key is 0600 and is the machine's ONLY sops/age identity — move
#          it somewhere safe and delete it after the install.
#
# What it does, in order, because each step needs the previous one:
#
#   1. `ssh-keygen` a fresh ed25519 host key  (never on the target: the key has
#      to exist BEFORE the secrets can be encrypted to it)
#   2. derive the age recipient from its PUBLIC half
#   3. write it into .sops.yaml as &<host> and add *<host> to the shared rule
#   4. `sops updatekeys`, which decrypts with YOUR key and re-encrypts to the new
#      recipient set
#   5. print the key path and the commit to run afterwards
#
# Step 4 needs one of:
#   - the Token2 plugged in (it holds the PGP key that is a .sops.yaml
#     recipient). The secret never leaves the card, so this is one touch, not an
#     export. Verified: `sops -d` reaches the card and waits for the tap.
#   - SOPS_AGE_KEY_FILE / SOPS_AGE_SSH_PRIVATE_KEY_FILE pointing at any other
#     recipient's identity, e.g. the current host's own host key:
#       sudo SSH_TO_AGE=1 SOPS_AGE_SSH_PRIVATE_KEY_FILE=/persist/etc/ssh/ssh_host_ed25519_key \
#         scripts/enroll-host-key.sh newbox
#
# This is the shared half of `deploy.sh`; a remote install calls it and then
# pushes the key over SSH, while a laptop installed locally calls it and copies
# the key onto the installer stick by hand.
# ──────────────────────────────────────────────────────────────
set -euo pipefail

HOST="${1:-}"
OUT=""
[ "${2:-}" = "--out" ] && OUT="${3:-}"

die()  { echo "❌ $*" >&2; exit 1; }
step() { echo; echo "── $* ──"; }

[ -n "$HOST" ] || die "usage: $0 <host> [--out DIR]"
FLAKE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOPS_YAML="$FLAKE_DIR/.sops.yaml"
SOPS_FILE="$FLAKE_DIR/secrets/secrets.sops.yaml"
[ -f "$SOPS_YAML" ] || die "$SOPS_YAML missing"
[ -f "$SOPS_FILE" ] || die "$SOPS_FILE missing"
command -v sops >/dev/null 2>&1 || die "sops is not on PATH — run inside \`nix develop .#\`"
[ -d "$FLAKE_DIR/hosts/$HOST" ] || die "hosts/$HOST does not exist — run scripts/new-host.sh first"

# The card holds SUBKEYS only (verified with `gpg --card-status --with-colons`:
# it reports the three subkey fingerprints and not the master). sops names the
# master in .sops.yaml, and gpg cannot build a key hierarchy out of a subkey, so
# without the master public key in the keyring decryption fails with "No secret
# key" even with the token plugged in. The public key is committed for exactly
# this reason, so import it rather than making the caller remember to.
step "checking the PGP recipient is in the keyring"
PGP_KEYS=$(awk '/^  - &/{v=$NF} v ~ /^[0-9A-F]{16,40}$/{print v}' "$SOPS_YAML" | sort -u)
for k in $PGP_KEYS; do
	if gpg --list-keys "$k" >/dev/null 2>&1; then
		echo "→ $k already present"
		continue
	fi
	pub=$(find "$FLAKE_DIR/hosts" -name '*.asc' -o -name '*.gpg' 2>/dev/null | head -1)
	[ -n "$pub" ] || die "$k is not in the keyring and no public key file is in the repo
   to import. gpg has no way to read it off the card either — the card only
   carries subkeys. Add the public key under hosts/<h>/wkd/ or run
   `gpg --recv-keys $k`."
	gpg --import "$pub" >/dev/null 2>&1 || die "could not import $pub"
	gpg --list-keys "$k" >/dev/null 2>&1 || die "imported $pub but $k is still missing"
	echo "→ imported $k from ${pub#$FLAKE_DIR/}"
done

KEY_DIR="${OUT:-$(mktemp -d)}"
mkdir -p "$KEY_DIR"
KEY_FILE="$KEY_DIR/ssh_host_ed25519_key"

step "generating a host key for $HOST"
ssh-keygen -t ed25519 -N '' -C "$HOST host key" -f "$KEY_FILE" >/dev/null
chmod 600 "$KEY_FILE"

# `ssh-to-age -private-key` emits AGE-SECRET-KEY-…, which is a DECRYPTION key.
# .sops.yaml needs the age1… recipient, which comes from the public half.
AGE_KEY="$(ssh-keygen -y -f "$KEY_FILE" | nix run nixpkgs#ssh-to-age -- 2>/dev/null | tail -1)"
case "$AGE_KEY" in
age1*) ;;
*) die "could not derive an age recipient from the generated key" ;;
esac
echo "→ recipient: $AGE_KEY"

step "adding $HOST to .sops.yaml"
# Replace in place when the anchor exists, so names, ordering and the comments
# that explain each key all survive. Rewriting the file would not.
if grep -qE "^[[:space:]]*-[[:space:]]*&$HOST\b" "$SOPS_YAML"; then
	sed -i -E "s|(- &$HOST )[^[:space:]]+|\1$AGE_KEY|" "$SOPS_YAML"
	echo "→ replaced the existing &$HOST anchor"
else
	# Below the LAST key entry rather than right under `keys:`, so the comment
	# blocks above each anchor keep pointing at the key they describe.
	LAST_KEY_LINE=$(awk '/^creation_rules:/{exit} /^  - &/{n=NR} END{print n}' "$SOPS_YAML")
	[ -n "$LAST_KEY_LINE" ] || die "could not find the key list in $SOPS_YAML"
	sed -i "${LAST_KEY_LINE}a\\  - \&$HOST $AGE_KEY" "$SOPS_YAML"
	echo "→ added a new &$HOST anchor"
fi

# Membership of the shared rule's age list is what makes `updatekeys` actually
# encrypt to this host. An anchor alone is just a name.
if grep -qE "^[[:space:]]*-[[:space:]]*\*$HOST\b" "$SOPS_YAML"; then
	echo "→ already in the shared key group"
else
	sed -i "/^[[:space:]]*- age:/a\          - *$HOST" "$SOPS_YAML"
	echo "→ joined the shared key group"
fi

step "re-encrypting the secrets to the new recipient set"
# This is the step that proves a recipient exists: sops must decrypt with YOUR
# key first. A Token2 tap happens here, or nothing does.
if ! sops updatekeys --yes "$SOPS_FILE" >/dev/null; then
	die "sops updatekeys failed — .sops.yaml has been edited but the ciphertext
   is unchanged. Restore it with: git checkout .sops.yaml
   Then plug in the Token2 (or set SOPS_AGE_KEY_FILE) and re-run."
fi
echo "→ secrets re-encrypted"

cat <<EOF

═══════════════════════════════════════════════════════════
  $HOST is now a sops recipient
═══════════════════════════════════════════════════════════

  private key : $KEY_FILE
                (0600 — this is the machine's ONLY sops identity)

  Commit the re-encryption, or the next \`autoUpgrade\` pull leaves a host
  holding a secret set it cannot decrypt:

    git add .sops.yaml secrets/secrets.sops.yaml
    git commit -m 'chore(secrets): authorise $HOST'

  Then move the key to where the install expects it, and DELETE this copy.
EOF
