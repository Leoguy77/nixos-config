#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
#  scripts/install-locally.sh — install this flake onto the LOCAL disk
# ──────────────────────────────────────────────────────────────
# Run this from the stock NixOS ISO, in its console, as root:
#
#   nix run github:Leoguy77/nixos-config#install-locally -- kirito
#
# It replaces the ~50 hand-typed commands of docs/INSTALL-KIRITO.md step 2:
#
#   1. fetch the flake ref, so the sops anchor and the disko pin come from the
#      flake itself rather than being copied into a doc and going stale
#   2. find the host key (--key, an ordinary USB stick, or the old root —
#      opening LUKS read-only if the old root is encrypted)
#   3. PROVE that key is the sops recipient for this host before formatting
#      anything, because a mismatch installs a machine whose secrets do not
#      decrypt and whose greeter nobody can log into
#   4. disko at the pinned rev, host key into /persist, then nixos-install
#
# Usage:
#   install-locally.sh <host> [--key PATH] [--disk DEV] [--flake REF] [-y]
#
#   host    nixosConfigurations attribute: hosts/<host>/ and the &<host> anchor
#           in .sops.yaml
#   --key   the host's ssh_host_ed25519_key (a private key, 0600). Omit to let
#           it search: /root, /run/media/*, then the old root partition
#   --disk  whole block device to erase (default /dev/nvme0n1)
#   --flake flake ref to install (default github:Leoguy77/nixos-config).
#           Pass path:$PWD#... to install uncommitted work instead.
#   -y      skip the erase confirmation
#
# Env:
#   ASSUME_YES=1              same as -y
#   ALLOW_UNVERIFIED_KEY=1    proceed when the key is not a sops recipient for
#                             this host (a genuinely new host, option B in the
#                             doc: secrets stay unreadable until `sops updatekeys`)
#   DISK=…                    same as --disk
# ──────────────────────────────────────────────────────────────
set -euo pipefail

HOST=""
KEY=""
DISK="${DISK:-/dev/nvme0n1}"
FLAKE="github:Leoguy77/nixos-config"
ASSUME_YES="${ASSUME_YES:-0}"
ALLOW_UNVERIFIED_KEY="${ALLOW_UNVERIFIED_KEY:-0}"

# Work dir lives in RAM, so it survives the repartition it describes.
# ponytail: root-only, no cleanup trap — the ISO is throwaway and a trap that
# fails mid-format is worse than a full tmpfs.
WORK=$(mktemp -d /tmp/install-locally.XXXXXX)

die() {
	echo "❌ $*" >&2
	exit 1
}
step() {
	echo
	echo "── $* ──"
}

while [ $# -gt 0 ]; do
	case "$1" in
	--key)
		KEY="$2"
		shift 2
		;;
	--disk)
		DISK="$2"
		shift 2
		;;
	--flake)
		FLAKE="$2"
		shift 2
		;;
	-y | --yes)
		ASSUME_YES=1
		shift
		;;
	-h | --help)
		sed -n '2,45p' "$0" | sed 's/^# \{0,1\}//'
		exit 0
		;;
	-*) die "unknown flag: $1" ;;
	*)
		[ -z "$HOST" ] || die "unexpected argument: $1"
		HOST="$1"
		shift
		;;
	esac
done

[ -n "$HOST" ] || die "usage: $0 <host> [--key PATH] [--disk DEV] [--flake REF]"
[ "$(id -u)" -eq 0 ] || die "run as root (from the ISO console: \`sudo -i\`)"

# The stock ISO ships no nix.conf with flakes enabled, and every nested nix call
# below would fail with "experimental Nix feature 'nix-command' is disabled".
export NIX_CONFIG='experimental-features = nix-command flakes'

step "flake $FLAKE#$HOST"
# The flake is materialised so .sops.yaml and flake.lock can be read from the
# SAME revision that gets installed. Copying those values into this script or
# into the doc is exactly how they go stale.
if [[ "$FLAKE" == path:* ]]; then
	FLAKE_DIR="${FLAKE#path:}"
	FLAKE_DIR="${FLAKE_DIR%%#*}"
else
	FLAKE_DIR=$(nix flake metadata --json "$FLAKE" --no-write-lock-file 2>/dev/null |
		grep -o '"path": *"[^"]*"' | head -1 | sed 's/.*"path": *"//; s/"$//') || true
fi
[ -d "${FLAKE_DIR:-}" ] || die "could not resolve $FLAKE to a directory"
[ -d "$FLAKE_DIR/hosts/$HOST" ] || die "hosts/$HOST does not exist in $FLAKE"
echo "→ source: $FLAKE_DIR"

ANCHOR=$(grep -oP "^ *- &${HOST} \K\S+" "$FLAKE_DIR/.sops.yaml" 2>/dev/null || true)
echo "→ sops anchor for $HOST: ${ANCHOR:-<none — this host is not a recipient>}"

# Read from flake.lock rather than `nix flake metadata`, so no new fetch happens.
DISKO_REV=$(nix eval --impure --raw --expr \
	"(builtins.fromJSON (builtins.readFile $FLAKE_DIR/flake.lock)).nodes.disko.locked.rev" \
	2>/dev/null || true)
echo "→ disko pin: ${DISKO_REV:-<none, falling back to nixpkgs#disko>}"
DISKO_REF="nixpkgs#disko"
[ -n "$DISKO_REV" ] && DISKO_REF="github:nix-community/disko/$DISKO_REV"

# ── 1. find the host key ─────────────────────────────────────
step "locating the host key"
KEY="$(printf '%s' "$KEY")"

# A key on an ordinary USB stick is the recommended path (doc step 0c, option A):
# it needs no knowledge of how the old disk was laid out.
if [ -z "$KEY" ]; then
	for cand in /root/hostkey /root/ssh_host_ed25519_key \
		/run/media/*/hostkey /run/media/*/*/hostkey /mnt/hostkey; do
		[ -s "$cand" ] && {
			KEY="$cand"
			break
		}
	done
fi

[ -n "$KEY" ] && install -m 0600 "$KEY" "$WORK/hostkey" && KEY="$WORK/hostkey"

# Otherwise read it off the old root. This has to cope with the old root being
# encrypted, which is what the previous install left behind: the plain
# `mount /dev/nvme0n1p2` of earlier versions fails here with
# "unknown filesystem type 'crypto_LUKS'".
if [ -z "$KEY" ]; then
	for p in $(lsblk -lno NAME,FSTYPE "$DISK" | awk '$2=="crypto_LUKS"{print $1}'); do
		echo "→ trying encrypted partition /dev/$p"
		# The container that holds /etc/ssh is the root one; try each and stop
		# at the first that actually carries a host key.
		dev="/dev/mapper/localinstall-$$-$(basename "$p")"
		# FIDO2-only containers (what this repo produces) prompt for a token tap
		# here, not a passphrase — plug the Token2 in before running.
		cryptsetup open --readonly --type luks2 "/dev/$p" "$(basename "$dev")" ||
			{
				echo "   could not open /dev/$p — no token tap?"
				continue
			}
		mp=$(mktemp -d)
		if mount -o ro "$dev" "$mp" 2>/dev/null; then
			if [ -s "$mp/etc/ssh/ssh_host_ed25519_key" ]; then
				install -m 0600 "$mp/etc/ssh/ssh_host_ed25519_key" "$WORK/hostkey"
				KEY="$WORK/hostkey"
			fi
			umount "$mp"
		fi
		rmdir "$mp" 2>/dev/null || true
		cryptsetup close "$dev" 2>/dev/null || true
		[ -n "$KEY" ] && break
	done
	[ -n "$KEY" ] || die "no host key found.

   Tried, in order: /root/hostkey, /run/media/*, $DISK's LUKS containers.
   If the old root is on this disk, plug the FIDO2 token in and re-run so
   cryptsetup can open it, or copy the key to a USB stick and pass --key PATH.

   If this host genuinely has no key yet (doc step 6, option B), set
   ALLOW_UNVERIFIED_KEY=1 — it will mint one, and every secret stays
   unreadable until \`sops updatekeys\` runs from another machine."
fi

[ -s "$KEY" ] || die "$KEY is empty or missing"
chmod 600 "$KEY" 2>/dev/null || true
echo "→ key: $KEY"
ssh-keygen -lf "$KEY" || die "$KEY is not an SSH key"

# ── 2. prove it is the right key, before touching the disk ────
step "verifying the key against .sops.yaml"
ssh-keygen -y -f "$KEY" >"$WORK/hostkey.pub" || die "cannot derive the public key"
# The RECIPIENT comes from the public key. `ssh-to-age -private-key` prints the
# AGE-SECRET-KEY identity instead, which sops-nix feeds to age at boot but which
# is NOT comparable to the anchor in .sops.yaml.
RECIPIENT=$(nix run nixpkgs#ssh-to-age -- -i "$WORK/hostkey.pub" 2>/dev/null) ||
	die "ssh-to-age failed"
echo "→ recipient: $RECIPIENT"
if [ -z "$ANCHOR" ]; then
	echo "⚠  $HOST has no &$HOST anchor in .sops.yaml — it is not a secret recipient."
	echo "   Before installing, run this on a machine holding a recipient (the Token2):"
	echo "       scripts/enroll-host-key.sh $HOST --out <dir>"
	echo "   then install with --key <dir>/ssh_host_ed25519_key."
	[ "$ALLOW_UNVERIFIED_KEY" = 1 ] ||
		die "refusing to continue. Re-run with ALLOW_UNVERIFIED_KEY=1 if that is intended."
elif [ "$RECIPIENT" != "$ANCHOR" ]; then
	die "recipient mismatch — this key is NOT the sops identity for $HOST.
   installer: $RECIPIENT
   .sops.yaml: $ANCHOR
   Installing would produce a machine that cannot decrypt its own secrets.
   Use the key the secrets were encrypted to, or enrol this one first:
       scripts/enroll-host-key.sh $HOST"
else
	echo "✓ matches the &$HOST anchor"
fi

# ── 3. confirm, then erase ───────────────────────────────────
step "target $DISK"
lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTLABEL "$DISK" | sed 's/^/   /'
if [ "$ASSUME_YES" != 1 ]; then
	echo
	echo "   Everything on $DISK is destroyed, /home included: it is a btrfs"
	echo "   subvolume inside the LUKS root, not a partition of its own."
	echo "   Take a restic snapshot first (doc step 0c) if you have not."
	echo
	read -rp "   Type the device path to confirm: " confirm
	[ "$confirm" = "$DISK" ] || die "aborted"
fi

step "formatting (disko) — recovery keys are printed twice, store both"
# Pinned to the flake's own revision, not nixpkgs#disko: disko builds the format
# script from the package's cli.nix and reads only disko.devices.disk out of the
# flake, so a floating disko can disagree with the declared layout.
echo "   Plug the FIDO2 token in NOW. There is no passphrase: enrollFido2 wipes"
echo "   slot 0, so the recovery key printed below is the only way back in."
echo
DISKO_SKIP_SWAP=1 nix shell "$DISKO_REF" -c disko \
	--mode destroy,format,mount \
	--flake "$FLAKE#$HOST" \
	--root-mountpoint /mnt

# ── 4. the host key, where activation can actually read it ───
step "seeding the host key"
# /persist is what the fix in profiles/state.nix points sops.age.sshKeyPaths at:
# neededForUsers secrets are decrypted by an activation script that runs from
# the INITRD, before impermanence bind-mounts /persist/etc/ssh onto /etc/ssh.
# Without this the users step fails with "0 successful groups required, got 0",
# no password reaches /etc/shadow, and the machine boots to a dead greeter.
install -D -m 0600 "$KEY" /mnt/persist/etc/ssh/ssh_host_ed25519_key
install -D -m 0600 "$WORK/hostkey.pub" /mnt/persist/etc/ssh/ssh_host_ed25519_key.pub
# Belt and braces for a stage-2 reader of the /etc path. impermanence would
# provide it a second later, but nixos-install's own activation runs first.
install -D -m 0600 "$KEY" /mnt/etc/ssh/ssh_host_ed25519_key
echo "→ /mnt/persist/etc/ssh/ and /mnt/etc/ssh/"

# ── 5. install ──────────────────────────────────────────────
step "nixos-install (quiet for minutes; ~14 GiB onto the target disk)"
if ! nixos-install --flake "$FLAKE#$HOST" --no-channel-copy --no-root-password; then
	die "nixos-install failed. If it said 'No space left on device' on
   /nix/.rw-store you built in the live store — this script uses nixos-install,
   which builds with --store /mnt, so check for a nested \`nix build\` instead."
fi

cat <<EOF

═══════════════════════════════════════════════════════════
  installed: $HOST on $DISK

  reboot, then remove the USB stick. The initrd asks for a
  token tap on EACH container — twice, because user presence
  is a fresh HMAC-SHA1 challenge per \`cryptsetup open\`.

  No passphrase exists. If the token is lost or broken, type
  the recovery key from the format step at the prompt.

  /home is empty. Restore it from host1 as root:
    sudo -i
    restic-system snapshots --latest 3
    restic-system restore latest --target / --verify
═══════════════════════════════════════════════════════════
EOF
