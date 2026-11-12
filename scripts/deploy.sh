#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
#  scripts/deploy.sh — install any host of this flake on a remote machine
# ──────────────────────────────────────────────────────────────
# Usage:
#   nix develop .# --command scripts/deploy.sh <host> <target> [disk]
#
#   host    nixosConfigurations attribute, i.e. the directory hosts/<host>/
#   target  user@address to install through (key-based SSH; the user needs
#           password-less sudo unless it is root)
#   disk    whole block device on the target (default /dev/vda)
#
# Needs `sops` on PATH, so run it inside the dev shell. It mints the host's SSH
# host key, enrols it as that host's sops recipient, re-encrypts the secrets, and
# seeds the key into the install. The private key exists only in a mktemp dir
# during the run and on the machine afterwards.
#
# Env:
#   VM_TEST=1          run `nixos-anywhere --vm-test` only: partitions a
#                      throwaway VM with the host's layout, touches nothing
#   EXTRA_FILES=<dir>  pass --extra-files <dir> (files copied into the new root)
#   TS_TAG=tag:…       tag for the minted initrd auth key (default tag:fde-unlock)
#   SKIP_DISKO_DEPS=1  pass --no-disko-deps: upload only the disko script (19 KiB)
#                      instead of its tooling (446 MiB). Safe on the custom ISO
#                      from `nix build .#installerIso-<host>`, which puts those
#                      tools on sshd's PATH. The stock kexec installer does NOT,
#                      so for <1.5 GB hosts boot that ISO instead
#                      (see hosts/mail/README.md).
#
# Examples:
#   scripts/deploy.sh mail root@91.132.147.216 /dev/vda
#   VM_TEST=1 scripts/deploy.sh mail root@91.132.147.216 /dev/vda
#
# Assumptions, all enforced below rather than guessed:
#   - hosts/<host>/default.nix exists and imports a disko layout
#   - hosts/<host>/hardware-configuration.nix is committed and does NOT contain
#     fileSystems (disko owns them; `--generate-hardware-config` would fight it)
# ──────────────────────────────────────────────────────────────
set -euo pipefail

HOST="${1:-}"
TARGET="${2:-}"
DISK="${3:-/dev/vda}"
# Tag on the minted auth key: OAuth clients can only create tagged nodes, and a
# dedicated tag means a leaked key cannot enroll anything but an unlock node.
TS_TAG="${TS_TAG:-tag:fde-unlock}"
# Merged with the staged host key later; empty covers the common case.
EXTRA_FILES="${EXTRA_FILES:-}"

FLAKE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if [ -z "$HOST" ] || [ -z "$TARGET" ]; then
	echo "Usage: $0 <host> <user@address> [disk]" >&2
	echo "  e.g. $0 mail root@91.132.147.216 /dev/vda" >&2
	echo "" >&2
	echo "  VM_TEST=1 $0 $HOST $TARGET $DISK   # dry run in a VM" >&2
	exit 1
fi

HOST_DIR="$FLAKE_DIR/hosts/$HOST"

# `path:` instead of the default git+file: git flakes copy only tracked files,
# so gitignored per-host secrets (e.g. the initrd tailscale bootstrap key) would
# silently be missing from the build.
FLAKE_REF="path:$FLAKE_DIR#$HOST"
# Attribute path for introspection — FLAKE_REF above names the configuration,
# which is what nixos-anywhere wants, but `nix eval` needs the full path.
EVAL_REF="path:$FLAKE_DIR#nixosConfigurations.$HOST"

nix_eval() {
	nix eval --raw "$EVAL_REF.$1" 2>/dev/null
}

# For booleans/ints: --raw cannot coerce those to a string.
nix_eval_json() {
	nix eval --json "$EVAL_REF.$1" 2>/dev/null
}

echo "═══════════════════════════════════════════════════════════"
echo "  deploy: $HOST → $TARGET (disk $DISK)"
echo "═══════════════════════════════════════════════════════════"
echo ""

# ── Pre-flight ────────────────────────────────────────────────
[ -f "$HOST_DIR/default.nix" ] || {
	echo "❌ hosts/$HOST/default.nix does not exist. Create the host first." >&2
	exit 1
}

HW="$HOST_DIR/hardware-configuration.nix"
if [ ! -f "$HW" ]; then
	echo "❌ hosts/$HOST/hardware-configuration.nix is missing." >&2
	echo "   Commit one (without fileSystems — disko creates those)." >&2
	exit 1
fi

# Checked before the fileSystems guard below: a host that does not use disko has
# every right to define fileSystems, and the useful message is this one.
if ! DISKO_DEVICE="$(nix_eval config.disko.devices.disk.main.device)"; then
	echo "❌ hosts/$HOST does not import a disko layout" >&2
	echo "   (no config.disko.devices.disk.main). A host can only be installed by" >&2
	echo "   this script if its disk layout lives in the flake. Add to its imports:" >&2
	echo "     inputs.disko.nixosModules.disko" >&2
	echo "     ../../modules/disko/luks-btrfs-server.nix" >&2
	exit 1
fi

if grep -q '^[[:space:]]*fileSystems' "$HW"; then
	echo "❌ $HW defines fileSystems; that clashes with the disko layout." >&2
	echo "   Drop it — disko generates the mount points." >&2
	exit 1
fi
echo "→ disko layout: $DISKO_DEVICE"

# nixos-anywhere dropped `--disk main <dev>` in 1.x: the device comes from the
# disko layout, which is evaluated into the flake, so there is nothing to pass on
# the command line. The $DISK argument therefore only asserts that the layout and
# the operator agree — overriding now means editing the layout.
if [ "$DISK" != "$DISKO_DEVICE" ]; then
	echo "❌ $DISK requested, but the disko layout uses $DISKO_DEVICE." >&2
	echo "   nixos-anywhere 1.x has no --disk override; change the device in" >&2
	echo "   modules/disko/luks-btrfs-server.nix (or the host's own layout)." >&2
	exit 1
fi

HOSTNAME_CFG="$(nix_eval config.networking.hostName || echo "$HOST")"
TS_ENABLED="$(nix_eval_json config.modules.initrdTailscale.enable || echo false)"
echo "→ hostname: $HOSTNAME_CFG   tailnet-only initrd ssh: $TS_ENABLED"

# ── Initrd tailscale bootstrap key (only needed for a first install) ──
# A fresh install wipes the ESP, so the persisted node identity is gone and one
# auth key is needed again. Rather than keeping a 90-day key on disk per host, we
# mint a short-lived one on demand from a Tailscale OAuth client. The client
# secret never expires, so this works for every server forever with no manual
# step; the key it produces lives for one hour and only in this temp file.
#
# The key is a *bootstrap* input only, and it lives on the ESP rather than in the
# initrd: the initrd is rebuilt from the store on every switch, so a key baked
# into it disappears the first time anyone rebuilds without the file present.
# The ESP survives switches, and the initrd already mounts it for node state.
#
# An auth key from a *file* always wins, for the case where the API is unreachable
# or you want to pin a specific key.
AUTHKEY="$FLAKE_DIR/secrets/tailscale-initrd-$HOST.authkey"
AUTHKEY_DERIVED=0

if [ "$TS_ENABLED" = "true" ] && [ ! -s "$AUTHKEY" ] && command -v sops >/dev/null 2>&1; then
	mkdir -p "$(dirname "$AUTHKEY")"

	sops_get() {
		sops -d --extract "[\"$1\"]" "$FLAKE_DIR/secrets/secrets.sops.yaml" 2>/dev/null
	}

	OID="$(sops_get tailscale_oauth_client_id || true)"
	OSECRET="$(sops_get tailscale_oauth_client_secret || true)"

	if [ -n "$OID" ] && [ -n "$OSECRET" ] && command -v curl >/dev/null 2>&1; then
		echo "→ minting a single-use auth key from the tailscale OAuth client…"
		# No jq: parse the two fields we need with sed. Both responses are flat JSON.
		TOKEN="$(curl -fsS -u "$OID:$OSECRET" \
			https://api.tailscale.com/api/v2/oauth/token \
			-d 'grant_type=client_credentials' 2>/dev/null |
			sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')"

		if [ -n "$TOKEN" ]; then
			# 24h, not 1h: the key is minted here but first used by the initrd
			# *after* the build, closure copy, disko run, install and reboot. On
			# a 1-vCPU box over the internet that can outlast a short window, and
			# an expired key drops you back on the provider console. The key is
			# non-reusable, so it dies on first join either way.
			KEY="$(curl -fsS -u "$TOKEN:" -H 'Content-Type: application/json' \
				https://api.tailscale.com/api/v2/tailnet/-/keys \
				-d '{"capabilities":{"devices":{"create":{"reusable":false,"ephemeral":false,"preauthorized":true,"tags":["'"$TS_TAG"'"]}}},"expirySeconds":86400}' 2>/dev/null |
				sed -n 's/.*"key":"\([^"]*\)".*/\1/p')"
			if [ -n "$KEY" ]; then
				printf '%s' "$KEY" >"$AUTHKEY"
				chmod 600 "$AUTHKEY"
				AUTHKEY_DERIVED=1
			else
				echo "⚠  the OAuth client could not mint a key (check Devices→Keys→Auth Keys"
				echo "   write scope and that $TS_TAG exists in the tailnet policy file)"
			fi
		else
			echo "⚠  could not get an access token from the tailscale OAuth client"
		fi
	fi

	# Fallback: a static key in sops, per host first (an auth key can only
	# bootstrap one node, so a shared name would work once and then fail).
	if [ "$AUTHKEY_DERIVED" = "0" ]; then
		for SKEY in "tailscale_initrd_authkey_${HOST//-/_}" tailscale_initrd_authkey; do
			if sops_get "$SKEY" >"$AUTHKEY" 2>/dev/null && [ -s "$AUTHKEY" ]; then
				chmod 600 "$AUTHKEY"
				AUTHKEY_DERIVED=1
				break
			fi
			rm -f "$AUTHKEY"
		done
	fi
fi

HAS_AUTHKEY=0
if [ "$TS_ENABLED" = "true" ]; then
	if [ -s "$AUTHKEY" ]; then
		HAS_AUTHKEY=1
		echo "→ bootstrap auth key ready: first boot joins the tailnet by itself"
	else
		echo ""
		echo "⚠  No bootstrap tailscale auth key, so the first boot will NOT join the"
		echo "   tailnet and can only be unlocked on the provider console."
		echo "   Normally this is automatic: deploy.sh mints a single-use key from the"
		echo "   tailscale OAuth client stored in sops. Check that:"
		echo "     • tailscale_oauth_client_id / _secret are in sops/secrets.sops.yaml"
		echo "     • the client has Devices→Keys→Auth Keys write scope"
		echo "     • $TS_TAG is in tagOwners of the tailnet policy file"
		echo "   Or drop a key at secrets/tailscale-initrd-$HOST.authkey yourself."
		echo ""
		read -rp "   Continue anyway (console-only first boot)? (y/N) " CONSOLE_ONLY
		[ "$CONSOLE_ONLY" = "y" ] || [ "$CONSOLE_ONLY" = "Y" ] || exit 1
	fi
fi

# ── Final confirmation ────────────────────────────────────────
echo ""
echo "⚠  This ERASES $DISK on $TARGET. Check first:"
echo "   • UEFI boot enabled for this machine at the provider"
echo "   • PTR/rDNS for the IPv4 *and* IPv6 address, if this host sends mail"
echo "   • addresses/gateways in hosts/$HOST/default.nix match the machine"
echo "     (a wrong gateway means an unreachable server)"
echo ""
read -rp "   Proceed? (y/N) " CONFIRM
[ "$CONFIRM" = "y" ] || [ "$CONFIRM" = "Y" ] || {
	echo "Aborted."
	exit 0
}

# ── LUKS passphrase ───────────────────────────────────────────
#
# A passphrase nobody recorded is a bricked disk waiting for one forgotten
# character, and this box has no other way in. So: prefer one that 1Password
# already holds, offer to mint and store a new one, and only fall back to typing
# when `op` is absent or locked. `op` needs the signed-in desktop app, which CI
# and a fresh machine do not have, so every path here degrades to the prompt.
echo ""
LUKS_PASSFILE="$(mktemp)"
LUKS_OP_ITEM="${LUKS_OP_ITEM:-$HOST LUKS}"

op_ready() {
	command -v op >/dev/null 2>&1 && op vault list >/dev/null 2>&1
}

op_password() {
	op item get "$LUKS_OP_ITEM" --fields label=password --reveal 2>/dev/null
}

if op_ready; then
	if LUKS_PASS="$(op_password)" && [ -n "$LUKS_PASS" ]; then
		echo "→ using the passphrase already stored in 1Password as \"$LUKS_OP_ITEM\""
	else
		read -rp "→ No 1Password item \"$LUKS_OP_ITEM\". Create one with a fresh passphrase? [Y/n] " ans
		if [ "${ans:-Y}" != "n" ] && [ "${ans:-Y}" != "N" ]; then
			# 48 alphanumeric chars: long enough to be worth generating, short
			# enough to retype on a provider console if 1Password is unreachable.
			# `create` has no --fields, and its --reveal output is human-readable,
			# so read the value back instead of parsing it.
			op item create --category password --title "$LUKS_OP_ITEM" \
				--generate-password='letters,digits,48' >/dev/null 2>&1 || true
			LUKS_PASS="$(op_password)"
		fi
	fi
fi

if [ -z "${LUKS_PASS:-}" ]; then
	read -rsp "🔐 LUKS passphrase for the disk: " LUKS_PASS
	echo ""
	read -rsp "🔐 Repeat: " LUKS_PASS2
	echo ""
	[ "$LUKS_PASS" = "$LUKS_PASS2" ] || {
		echo "❌ Passphrases differ." >&2
		exit 1
	}
	unset LUKS_PASS2
else
	echo "→ recover it later with: op item get '$LUKS_OP_ITEM' --fields label=password --reveal"
fi

printf '%s' "$LUKS_PASS" >"$LUKS_PASSFILE"
unset LUKS_PASS

cleanup() {
	rm -f "$LUKS_PASSFILE"
	# A failed install must leave the repo exactly as it was: otherwise secrets
	# stay encrypted to a key whose only copy is about to be deleted here.
	if [ "${INSTALL_DONE:-0}" != "1" ] && [ -n "${KEY_DIR:-}" ] && [ -d "$KEY_DIR" ]; then
		[ -f "$KEY_DIR/sops.yaml.orig" ] && cp "$KEY_DIR/sops.yaml.orig" "$SOPS_YAML" || true
		[ -f "$KEY_DIR/secrets.orig" ] && cp "$KEY_DIR/secrets.orig" "$SOPS_FILE" || true
	fi
	rm -rf "${KEY_DIR:-}" "${STAGE_DIR:-}"
	# A derived key only had to exist for this build.
	[ "${AUTHKEY_DERIVED:-0}" = "1" ] && rm -f "$AUTHKEY"
}
trap cleanup EXIT

# ── Reachability ─────────────────────────────────────────────
if ! ssh -o BatchMode=yes -o ConnectTimeout=10 "$TARGET" true 2>/dev/null; then
	echo ""
	echo "⚠  No key-based SSH access to $TARGET."
	echo "   nixos-anywhere needs root, or a user with password-less sudo."
	echo ""
	read -rp "   Try the install anyway? (y/N) " GO
	[ "$GO" = "y" ] || [ "$GO" = "Y" ] || exit 1
fi

# ── Dry run ──────────────────────────────────────────────────
if [ -n "${VM_TEST:-}" ]; then
	echo ""
	echo "🧪 VM test — no real disk is touched"
	nix run github:nix-community/nixos-anywhere -- \
		--flake "$FLAKE_REF" \
		--vm-test
	echo ""
	echo "✅ layout + config boot in a VM. Re-run without VM_TEST=1 to install."
	exit 0
fi

# ── Install ──────────────────────────────────────────────────
echo ""
# ── Host key: generate here, enrol, seed, forget ─────────────
#
# The SSH host key is also this machine's sops/age identity (`age.sshKeyPaths`),
# so it has to exist before the secrets can be encrypted to it — which is why it
# is minted here and not on the target. It lives in a mktemp dir for the length
# of this run and is deleted by the EXIT trap; afterwards the only copy is on the
# server, where it stays forever.
#
# `sops updatekeys` re-encrypts every value to the new recipient, so the committed
# file only opens on THIS machine's current key. Two consequences, both real:
#   - a redeploy mints a new key and rotates every secret, so the resulting
#     .sops.yaml + secrets.sops.yaml change must be committed or the host's next
#     `autoUpgrade` pull leaves it with a secret set it cannot decrypt
#   - losing the machine loses the identity; a reinstall starts from scratch
# Nothing needs to be committed *before* the install: the key travels to the
# target via --extra-files, so the install never reads sops.
if ! command -v sops >/dev/null 2>&1; then
	echo "❌ sops is not on PATH, so this host's key cannot be enrolled."
	echo "   Run this inside the dev shell:"
	echo ""
	echo "     nix develop .# --command scripts/deploy.sh $HOST $TARGET $DISK"
	exit 1
fi

SOPS_FILE="$FLAKE_DIR/secrets/secrets.sops.yaml"
SOPS_YAML="$FLAKE_DIR/.sops.yaml"
KEY_DIR="$(mktemp -d)"
HOST_KEY_FILE="$KEY_DIR/ssh_host_ed25519_key"
cp "$SOPS_YAML" "$KEY_DIR/sops.yaml.orig"
cp "$SOPS_FILE" "$KEY_DIR/secrets.orig"

# updatekeys has to decrypt the file first, and the only identity it can use is
# your PGP key. Import it from ~/.ssh/GPG unless the keyring already has one, so
# this does not silently depend on a previous manual import.
if ! gpg --batch --list-secret-keys 2>/dev/null | grep -q '^sec'; then
	echo "→ importing your PGP key from ~/.ssh/GPG…"
	if ! ssh-to-pgp -private-key -i "$HOME/.ssh/GPG" 2>/dev/null | gpg --batch --import >/dev/null 2>&1; then
		echo "❌ Could not import ~/.ssh/GPG, so sops updatekeys cannot decrypt."
		exit 1
	fi
fi

echo "→ generating an SSH host key for $HOST…"
ssh-keygen -t ed25519 -N '' -C "$HOST host key" -f "$HOST_KEY_FILE" >/dev/null
chmod 600 "$HOST_KEY_FILE"

# Derived from the public half: `ssh-to-age -private-key` emits AGE-SECRET-KEY-…,
# which is a decryption key, not the age1… recipient .sops.yaml needs.
AGE_KEY="$(ssh-keygen -y -f "$HOST_KEY_FILE" | nix run nixpkgs#ssh-to-age -- 2>/dev/null | tail -1)"
case "$AGE_KEY" in
age1*) ;;
*)
	echo "❌ Could not derive an age recipient from the generated key."
	exit 1
	;;
esac

# Point this host's recipient at the new key. Replacing in place keeps names,
# ordering and comments intact, which rewriting the file would not.
if grep -qE "^[[:space:]]*-[[:space:]]*&$HOST\b" "$SOPS_YAML"; then
	sed -i -E "s|(- &$HOST )[^[:space:]]+|\1$AGE_KEY|" "$SOPS_YAML"
else
	# Below the last key entry, not right under `keys:`, so the explanatory
	# comments above them keep pointing at the keys they describe.
	LAST_KEY_LINE=$(awk '/^creation_rules:/{exit} /^  - &/{n=NR} END{print n}' "$SOPS_YAML")
	sed -i "${LAST_KEY_LINE}a\\  - \&$HOST $AGE_KEY" "$SOPS_YAML"
fi
# A new host must also join the shared rule's age list, or updatekeys has no
# reason to encrypt to it.
if ! grep -qE "^[[:space:]]*-[[:space:]]*\*$HOST\b" "$SOPS_YAML"; then
	sed -i "/^[[:space:]]*- age:/a\          - *$HOST" "$SOPS_YAML"
fi
echo "→ recipient: $AGE_KEY"

if ! sops updatekeys --yes "$SOPS_FILE" >/dev/null; then
	echo "❌ sops updatekeys failed; nothing has been touched on $TARGET."
	exit 1
fi
echo "→ secrets re-encrypted to the new key"

STAGE_DIR="$(mktemp -d)"
install -D -m 0600 "$HOST_KEY_FILE" "$STAGE_DIR/etc/ssh/ssh_host_ed25519_key"
# Land the bootstrap key on the ESP (disko mounts it at /mnt/boot, and
# --extra-files untars into /mnt). The initrd mounts that same ESP, so the key is
# there before stage 1 runs and survives every later rebuild.
if [ "${HAS_AUTHKEY:-0}" = "1" ]; then
	install -D -m 0600 "$AUTHKEY" "$STAGE_DIR/boot/tailscale-authkey"
fi
if [ -n "$EXTRA_FILES" ]; then
	cp -a "$EXTRA_FILES/." "$STAGE_DIR/"
	# Re-install after the merge so a caller's tree cannot shadow the key.
	install -D -m 0600 "$HOST_KEY_FILE" "$STAGE_DIR/etc/ssh/ssh_host_ed25519_key"
fi
EXTRA_FILES="$STAGE_DIR"
EXTRA_ARGS=(--extra-files "$EXTRA_FILES")

echo "⚡ nixos-anywhere is partitioning $DISK and installing…"
# Only the disko *script* is uploaded, not its tooling (19 KiB vs 446 MiB). This
# needs sgdisk/parted/mkfs.*/cryptsetup to already resolve on the target's sshd
# PATH — true on `nix build .#installerIso-<host>`, false on the stock kexec
# installer. See the header.
if [ -n "${SKIP_DISKO_DEPS:-}" ]; then
	EXTRA_ARGS+=(--no-disko-deps)
fi

nix run github:nix-community/nixos-anywhere -- \
	--flake "$FLAKE_REF" \
	--target-host "$TARGET" \
	--disk-encryption-keys /tmp/luks-password "$LUKS_PASSFILE" \
	"${EXTRA_ARGS[@]}"

# Past this point the key on the target is the only copy, so the re-encryption
# must be kept rather than rolled back.
INSTALL_DONE=1

# ── What next ────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  ✅ installed — the machine is rebooting into the initrd"
echo "═══════════════════════════════════════════════════════════"
echo ""
if [ "$TS_ENABLED" = "true" ]; then
	if [ "$HAS_AUTHKEY" = "1" ]; then
		echo "  1. Unlock over the tailnet (nothing listens publicly):"
		echo "       ssh -p 2222 root@$HOSTNAME_CFG-initrd"
		echo "       # then, in that session:"
		echo "       systemd-tty-ask-password-agent --watch"
	else
		echo "  1. Unlock on the provider console (no bootstrap key was available):"
		echo "       # the passphrase prompt appears there; type it"
	fi
	echo ""
	echo "  2. Disable key expiry for the $HOSTNAME_CFG-initrd node in the tailscale"
	echo "     admin console, so the initrd never re-authenticates."
else
	echo "  1. Unlock the encrypted root:"
	echo "       ssh -p 2222 root@${TARGET#*@}"
	echo "       # then: systemd-tty-ask-password-agent --watch"
fi
echo ""
echo "  3. Then, on the running system, nothing to do: the install already"
echo "     deployed this exact configuration, and the seeded host key lets it"
echo "     decrypt its secrets on that first boot."
echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  ⚠  commit the rotated secrets before the host pulls again"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "This host's SSH host key doubles as its sops identity, and it was generated"
echo "for this run. Its private half now exists only on the machine — but the"
echo "matching .sops.yaml + secrets/secrets.sops.yaml change is still local:"
echo ""
echo "  git add .sops.yaml secrets/secrets.sops.yaml"
echo "  git commit -m 'chore(secrets): authorise $HOST'"
echo ""
echo "Until that is pushed, the ciphertext in git is encrypted to a key this"
echo "machine will never have again ($AGE_KEY)."
echo ""
