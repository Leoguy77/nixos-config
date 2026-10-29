#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────
#  scripts/deploy.sh — deploy a new host via nixos-anywhere
# ──────────────────────────────────────────────────────────
# Usage:
#   scripts/deploy.sh <hostname> <user@host> [disk]
#
# Automates:
#   - host directory & config creation
#   - SSH host key generation (deploy identity)
#   - reminders for sops secrets
#   - nixos-anywhere deploy with LUKS + disko
# ──────────────────────────────────────────────────────────

HOST="${1:-}"
TARGET="${2:-}"
DISK="${3:-/dev/sda}"

if [ -z "$HOST" ] || [ -z "$TARGET" ]; then
  echo "Usage: $0 <hostname> <user@host> [disk]"
  echo "  e.g. $0 server root@192.168.3.50 /dev/nvme0n1"
  exit 1
fi

HOST_DIR="$(dirname "$0")/../hosts/$HOST"
FLAKE_DIR="$(dirname "$0")/.."

# ── Step 1: create host directory ──
mkdir -p "$HOST_DIR"

if [ ! -f "$HOST_DIR/default.nix" ]; then
  echo "📝 Writing hosts/$HOST/default.nix"
  cat > "$HOST_DIR/default.nix" << HOSTNIX
# Host-specific configuration
{ config, pkgs, lib, inputs, mylib, myvars, pkgs-stable, ... }:

{
  imports = mylib.scanPaths ../../modules/nixos;

  modules.boot.enable = true;
  modules.boot.systemdBoot = true;
  modules.boot.efi = true;

  modules.system.enable = true;
  modules.services.enable = true;
  modules.services.ssh = true;

  modules.users.enable = true;
  modules.security.enable = true;

  nixpkgs.overlays = import ../../overlays;

  networking.hostName = "$HOST";

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit mylib myvars pkgs-stable inputs pkgs; };
    users.leoguy77 = { config, ... }: {
      imports = [ ../../modules/home ./home.nix ];
      modules.home.sops.enable = true;
      home.stateVersion = myvars.system.stateVersion;
    };
  };
}
HOSTNIX

  cat > "$HOST_DIR/home.nix" << 'HOMENIX'
# Host-specific Home Manager overrides
{ config, pkgs, lib, myvars, ... }:
{
  modules.home.core.enable = true;
  modules.home.base.development.enable = true;
  modules.home.tui.enable = true;
}
HOMENIX
fi

# ── Step 2: generate host SSH key (for nixos-anywhere/deploy) ──
echo ""
echo "🔑 Generating host SSH key..."
HOST_SSH_DIR="$HOST_DIR/ssh"
mkdir -p "$HOST_SSH_DIR"

if [ ! -f "$HOST_SSH_DIR/ssh_host_ed25519_key" ]; then
  ssh-keygen -t ed25519 -f "$HOST_SSH_DIR/ssh_host_ed25519_key" -N "" -C "root@$HOST" >/dev/null 2>&1
fi

# Inject via extra-files
EXTRA_FILES="$HOST_DIR/extra-files"
mkdir -p "$EXTRA_FILES/etc/ssh"
cp "$HOST_SSH_DIR/ssh_host_ed25519_key" "$EXTRA_FILES/etc/ssh/ssh_host_ed25519_key"
cp "$HOST_SSH_DIR/ssh_host_ed25519_key.pub" "$EXTRA_FILES/etc/ssh/ssh_host_ed25519_key.pub"
chmod 600 "$EXTRA_FILES/etc/ssh/ssh_host_ed25519_key"

# ── Step 3: remind about sops secrets ──
echo ""
echo "───────────────────────────────────────────────────────────"
echo "  🔐  sops secrets ($FLAKE_DIR/secrets/secrets.sops.yaml)"
echo "───────────────────────────────────────────────────────────"
echo ""
echo "  Add secrets to the shared sops file, then apply:"
echo "    sops $FLAKE_DIR/secrets/secrets.sops.yaml    # edit & re-encrypt"
echo "    sudo nixos-rebuild switch --flake '$FLAKE_DIR#$HOST'    # system secrets"
echo "    home-manager switch --flake '$FLAKE_DIR#leoguy77@$HOST' # home secrets"
echo ""
echo "  Decryption identity: ~/.config/sops/age/keys.txt  (BACK IT UP)"
echo ""

# ── Step 4: confirm deploy ──
echo ""
echo "🚀 Ready to deploy $HOST to $TARGET (disk: $DISK)"
echo ""
echo "   Target: NixOS installer ISO with SSH access"
echo ""
read -rp "   Proceed? (y/N) " CONFIRM
if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
  echo "   ⏭️  Aborted."
  exit 0
fi

# ── Step 5: LUKS password ──
echo ""
LUKS_PASSFILE=$(mktemp)
trap 'rm -f "$LUKS_PASSFILE"' EXIT

read -rsp "   🔐 Enter LUKS password: " LUKS_PASS
echo ""
read -rsp "   🔐 Confirm LUKS password: " LUKS_PASS2
echo ""
if [ "$LUKS_PASS" != "$LUKS_PASS2" ]; then
  echo "   ❌ Passwords don't match."
  exit 1
fi
echo -n "$LUKS_PASS" > "$LUKS_PASSFILE"
unset LUKS_PASS LUKS_PASS2

# ── Step 6: run nixos-anywhere ──
echo ""
echo "⚡ Deploying..."

DISKO_CONFIG="$(dirname "$0")/../modules/disko/luks-btrfs.nix"
nixos-anywhere \
  --flake "$FLAKE_DIR#$HOST" \
  --disko "$DISKO_CONFIG" \
  --disk main "$DISK" \
  --extra-files "$EXTRA_FILES" \
  --disk-encryption-keys "$LUKS_PASSFILE" /tmp/luks-password \
  --generate-hardware-config nixos-generate-config "$HOST_DIR/hardware-configuration.nix" \
  "$TARGET"

echo ""
echo "   ✅ nixos-anywhere completed."
echo ""

# ── Step 7: recap ──
echo "═══════════════════════════════════════════════════════"
echo "  ✅  DEPLOYED: $HOST → $TARGET"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  📋 Commit:"
echo "    git add hosts/$HOST secrets/ && git commit -m 'Add $HOST host'"
echo ""
echo "  🏠 ssh leoguy77@<ip>"
echo ""
echo "═══════════════════════════════════════════════════════"
