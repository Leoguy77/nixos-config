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
#   - SSH host key generation (for agenix)
#   - adding host key to secrets/secrets.nix
#   - prompts for tier-specific secrets
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
SECRETS_FILE="$(dirname "$0")/../secrets/secrets.nix"

# ── Step 1: create host directory ──
mkdir -p "$HOST_DIR"

if [ ! -f "$HOST_DIR/default.nix" ]; then
  echo "📝 Writing hosts/$HOST/default.nix"
  cat > "$HOST_DIR/default.nix" << HOSTNIX
# Host-specific configuration
{ config, pkgs, lib, inputs, mylib, myvars, pkgs-stable, agenix, ... }:

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
  modules.secrets.enable = true;

  nixpkgs.overlays = import ../../overlays;

  networking.hostName = "$HOST";

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit mylib myvars pkgs-stable inputs pkgs agenix; };
    users.leoguy77 = { config, ... }: {
      imports = [ ../../modules/home ./home.nix ];
      modules.home.secrets.enable = true;
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

# ── Step 2: generate host SSH key for agenix ──
echo ""
echo "🔑 Generating host SSH key..."
HOST_SSH_DIR="$HOST_DIR/ssh"
mkdir -p "$HOST_SSH_DIR"

if [ ! -f "$HOST_SSH_DIR/ssh_host_ed25519_key" ]; then
  ssh-keygen -t ed25519 -f "$HOST_SSH_DIR/ssh_host_ed25519_key" -N "" -C "root@$HOST" >/dev/null 2>&1
fi

HOST_PUBKEY=$(cat "$HOST_SSH_DIR/ssh_host_ed25519_key.pub")
AGE_PUBKEY=$(ssh-to-age < "$HOST_SSH_DIR/ssh_host_ed25519_key.pub" 2>/dev/null || echo "")

echo "   Age pubkey: $AGE_PUBKEY"

# Inject via extra-files
EXTRA_FILES="$HOST_DIR/extra-files"
mkdir -p "$EXTRA_FILES/etc/ssh"
cp "$HOST_SSH_DIR/ssh_host_ed25519_key" "$EXTRA_FILES/etc/ssh/ssh_host_ed25519_key"
cp "$HOST_SSH_DIR/ssh_host_ed25519_key.pub" "$EXTRA_FILES/etc/ssh/ssh_host_ed25519_key.pub"
chmod 600 "$EXTRA_FILES/etc/ssh/ssh_host_ed25519_key"

# ── Step 3: add host key to secrets/secrets.nix ──
if grep -q "$HOST" "$SECRETS_FILE" 2>/dev/null; then
  echo "   ⏭️  $HOST already in secrets/secrets.nix"
else
  echo "   📝 Adding $HOST to secrets/secrets.nix"
  sed -i "/AUTO-HOSTS-START/a\\  $HOST = \"$AGE_PUBKEY\";" "$SECRETS_FILE"
  sed -i "/AUTO-HOST-LIST/i\\    $HOST" "$SECRETS_FILE"
fi

# ── Step 4: prompt for tier-specific secrets ──
echo ""
echo "═══════════════════════════════════════════════════════"
echo "  🔐  Create secrets for $HOST"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  Add global secrets (all machines decrypt):"
echo "    agenix -e secrets/global/<name>.age"
echo ""
echo "  Add machine secrets (only $HOST + you):"
echo "    agenix -e secrets/machine/$HOST/<name>.age"
echo ""
echo "  Add user secrets (all machines, home-manager):"
echo "    agenix -e secrets/user/<name>.age"
echo ""
echo "  Then uncomment matching entries in secrets/secrets.nix"
echo ""

read -rp "  Open editor to add secrets now? (y/N) " EDIT_SECRETS
if [ "$EDIT_SECRETS" = "y" ] || [ "$EDIT_SECRETS" = "Y" ]; then
  mkdir -p secrets/global secrets/machine/"$HOST" secrets/user

  echo ""
  echo "  Enter secret names (space-separated, e.g., 'cloudflared-token wifi github-token'):"
  read -rp "  > " -a SECRET_NAMES

  for s in "${SECRET_NAMES[@]}"; do
    echo ""
    echo "  Tier for '$s'? (g = global / m = machine / u = user)"
    read -rp "  > " TIER
    case "$TIER" in
      g|global)
        TIER_DIR="global"
        RECIPS="[ leon ] ++ allMachines"
        ;;
      m|machine)
        TIER_DIR="machine/$HOST"
        RECIPS="[ leon $HOST ]"
        ;;
      u|user)
        TIER_DIR="user"
        RECIPS="[ leon ]"
        ;;
      *)
        TIER_DIR="global"
        RECIPS="[ leon ] ++ allMachines"
        ;;
    esac

    FILE="secrets/$TIER_DIR/$s.age"
    mkdir -p "$(dirname "$FILE")"

    echo -n "  Value for '$s': "
    read -rs VALUE
    echo ""

    # Encrypt with rage directly (avoids EDITOR)
    R1=$(ssh-to-age < ~/.ssh/id_ed25519.pub 2>/dev/null || echo "")
    R2="$AGE_PUBKEY"

    if [ "$TIER" = "u" ] || [ "$TIER" = "user" ]; then
      echo -n "$VALUE" | rage -e -r "$R1" -o "$FILE" 2>/dev/null
    elif [ "$TIER" = "g" ] || [ "$TIER" = "global" ]; then
      echo -n "$VALUE" | rage -e -r "$R1" -r "$R2" -o "$FILE" 2>/dev/null
    else
      echo -n "$VALUE" | rage -e -r "$R1" -r "$R2" -o "$FILE" 2>/dev/null
    fi

    echo "   ✅ Created: $FILE"

    # Add to recipients in secrets.nix
    ENTRY="\"$TIER_DIR/$s.age\".publicKeys = $RECIPS;"
    sed -i "/AUTO-HOSTS-END/i\\    $ENTRY" "$SECRETS_FILE"

    # Add security config
    if [ "$TIER" = "u" ] || [ "$TIER" = "user" ]; then
      sed -i "/AUTO-HOSTS-END/i\\    \"$TIER_DIR/$s.age\" = levels.user_readable;"
    else
      sed -i "/AUTO-HOSTS-END/i\\    \"$TIER_DIR/$s.age\" = levels.restricted;"
    fi
  done
fi

# ── Step 5: confirm deploy ──
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

# ── Step 6: LUKS password ──
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

# ── Step 7: run nixos-anywhere ──
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

# ── Step 8: recap ──
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
