#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
#  scripts/deploy.sh — install any host of this flake on a remote machine
# ──────────────────────────────────────────────────────────────
# Usage:
#   scripts/deploy.sh <host> <target> [disk]
#
#   host    nixosConfigurations attribute, i.e. the directory hosts/<host>/
#   target  user@address to install through (key-based SSH; the user needs
#           password-less sudo unless it is root)
#   disk    whole block device on the target (default /dev/vda)
#
# Env:
#   VM_TEST=1          run `nixos-anywhere --vm-test` only: partitions a
#                      throwaway VM with the host's layout, touches nothing
#   EXTRA_FILES=<dir>  pass --extra-files <dir> (files copied into the new root)
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
echo "→ disko layout: $DISKO_DEVICE (overridden by --disk main $DISK)"

HOSTNAME_CFG="$(nix_eval config.networking.hostName || echo "$HOST")"
TS_ENABLED="$(nix_eval_json config.modules.initrdTailscale.enable || echo false)"
echo "→ hostname: $HOSTNAME_CFG   tailnet-only initrd ssh: $TS_ENABLED"

# ── Initrd tailscale bootstrap key (only needed for a first install) ──
# Conventional location, gitignored, derived from sops when possible. After the
# first boot the node identity persists on the ESP and no key is involved.
AUTHKEY="$FLAKE_DIR/secrets/tailscale-initrd-$HOST.authkey"
AUTHKEY_DERIVED=0
if [ "$TS_ENABLED" = "true" ] && [ ! -s "$AUTHKEY" ] && command -v sops >/dev/null 2>&1; then
  mkdir -p "$(dirname "$AUTHKEY")"
  if sops -d --extract '["tailscale_initrd_authkey"]' \
       "$FLAKE_DIR/secrets/secrets.sops.yaml" > "$AUTHKEY" 2>/dev/null; then
    chmod 600 "$AUTHKEY"
    AUTHKEY_DERIVED=1
  else
    rm -f "$AUTHKEY"
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
    echo "   Add it once to sops and this script derives it on every install:"
    echo "     sops $FLAKE_DIR/secrets/secrets.sops.yaml"
    echo "     # add: tailscale_initrd_authkey = tskey-auth-…"
    echo "   (pre-approved key, 7 days is plenty — only the first boot uses it)"
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
[ "$CONFIRM" = "y" ] || [ "$CONFIRM" = "Y" ] || { echo "Aborted."; exit 0; }

# ── LUKS passphrase ───────────────────────────────────────────
echo ""
LUKS_PASSFILE="$(mktemp)"
cleanup() {
  rm -f "$LUKS_PASSFILE"
  # A derived key only had to exist for this build.
  [ "${AUTHKEY_DERIVED:-0}" = "1" ] && rm -f "$AUTHKEY"
}
trap cleanup EXIT

read -rsp "🔐 LUKS passphrase for the disk: " LUKS_PASS; echo ""
read -rsp "🔐 Repeat: " LUKS_PASS2; echo ""
[ "$LUKS_PASS" = "$LUKS_PASS2" ] || { echo "❌ Passphrases differ." >&2; exit 1; }
printf '%s' "$LUKS_PASS" > "$LUKS_PASSFILE"
unset LUKS_PASS LUKS_PASS2

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
    --disk main "$DISK" \
    --vm-test
  echo ""
  echo "✅ layout + config boot in a VM. Re-run without VM_TEST=1 to install."
  exit 0
fi

# ── Install ──────────────────────────────────────────────────
echo ""
echo "⚡ nixos-anywhere is partitioning $DISK and installing…"
EXTRA_ARGS=()
if [ -n "${EXTRA_FILES:-}" ]; then
  EXTRA_ARGS+=(--extra-files "$EXTRA_FILES")
fi

nix run github:nix-community/nixos-anywhere -- \
  --flake "$FLAKE_REF" \
  --target-host "$TARGET" \
  --disk main "$DISK" \
  --disk-encryption-keys "$LUKS_PASSFILE" /tmp/luks-password \
  "${EXTRA_ARGS[@]}"

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
echo "  3. Then, on the running system:"
echo "       nixos-rebuild switch --flake .#$HOST --target-host $TARGET --use-remote-sudo"
echo ""
