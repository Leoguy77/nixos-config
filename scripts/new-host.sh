#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
#  scripts/new-host.sh — scaffold a new host of this flake
# ──────────────────────────────────────────────────────────────
# Usage:
#   scripts/new-host.sh <name> [--role laptop|desktop|server]
#
#   laptop   desktop stack + autocpufreq + S3 suspend + FDE   (default)
#   desktop  the shared graphical stack, no battery handling
#   server   non-graphical; remote unlock, fail2ban, sshd policy
#
# Creates exactly three files, which is the whole minimum this flake needs:
#
#   hosts/<name>/default.nix                  imports + role + hostName
#   hosts/<name>/hardware-configuration.nix   the machine-specific facts
#   hosts/<name>/home.nix                     home-manager overrides (not server)
#
# and then prints the two commands that install it. It does NOT invent hardware
# facts: `nixos-generate-config` on the real machine fills those in, and the
# generated file must have its fileSystems/swapDevices blocks removed because
# disko owns them (scripts/deploy.sh refuses the file otherwise).
# ──────────────────────────────────────────────────────────────
set -euo pipefail

NAME="${1:-}"
ROLE="${2:-}"
[ "${ROLE:-}" = "--role" ] && ROLE="${3:-}"
ROLE="${ROLE:-laptop}"
FLAKE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIR="$FLAKE_DIR/hosts/$NAME"

die() {
	echo "❌ $*" >&2
	exit 1
}

[ -n "$NAME" ] || die "usage: $0 <name> [--role laptop|desktop|server]"
[[ "$NAME" =~ ^[a-z0-9]([a-z0-9_-]{0,61}[a-z0-9])?$ ]] ||
	die "\"$NAME\" is not a valid hostName (lowercase alnum, - and _, no leading _)"
[ -e "$DIR" ] && die "hosts/$NAME already exists"

case "$ROLE" in
laptop)
	PROFILE="../../profiles/laptop.nix"
	KIND="laptop"
	;;
desktop)
	PROFILE="../../profiles/desktop.nix"
	KIND="desktop"
	;;
server)
	PROFILE="../../profiles/server.nix"
	KIND="server"
	;;
*) die "unknown role: $ROLE (laptop|desktop|server)" ;;
esac

mkdir -p "$DIR"

# ── default.nix ─────────────────────────────────────────────
# Deliberately the shortest file that works. Everything optional lives in the
# role profile; a host that needs more opts in with one line per service, which
# is the point of the narrow-module split.
if [ "$KIND" = server ]; then
	cat >"$DIR/default.nix" <<EOF
{
  mylib,
  ...
}:

{
  imports = mylib.scanPaths ../../modules/nixos ++ [
    ./hardware-configuration.nix
    $PROFILE
  ];

  networking.hostName = "$NAME";
}
EOF
else
	cat >"$DIR/default.nix" <<EOF
{
  mylib,
  ...
}:

{
  imports = mylib.scanPaths ../../modules/nixos ++ [
    ./hardware-configuration.nix
    $PROFILE
  ];

  # profiles/$KIND.nix leaves this to the host: it is the path to THIS
  # machine's home-manager overrides, which cannot be guessed.
  modules.desktop.homeModule = ./home.nix;

  networking.hostName = "$NAME";

  # Optional services are per host on purpose (see profiles/README or
  # docs/MODULES.md). Uncomment what this machine actually needs:
  # modules.tailscale.enable = true;
  # modules.tailscale.openFirewall = true;
  # modules.ssh.enable = true;
  # modules.rdp.enable = true;
  # modules.printing.enable = true;
}
EOF
fi

# ── hardware-configuration.nix ──────────────────────────────
# NOT invented here. These are the facts a generic x86_64 machine almost always
# shares, and nixos-generate-config overrides them on the real box. The two
# blocks it generates that MUST be deleted are fileSystems and swapDevices:
# disko generates those from profiles/disk/, and defining them twice stops
# every evaluation on a conflict.
if [ "$KIND" = server ]; then
	cat >"$DIR/hardware-configuration.nix" <<'EOF'
# Run `nixos-generate-config` on the machine and replace this file with its
# output, then DELETE the `fileSystems` and `swapDevices` blocks — the disko
# layout in profiles/disk/ owns them and defining them twice is a hard error.
{ lib, ... }:
{
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  boot.initrd.availableKernelModules = [ "ahci" "nvme" "sd_mod" "virtio_pci" "virtio_scsi" ];
}
EOF
else
	cat >"$DIR/hardware-configuration.nix" <<'EOF'
# Run `nixos-generate-config` on the machine and replace this file with its
# output, then DELETE the `fileSystems` and `swapDevices` blocks — the disko
# layout in profiles/disk/ owns them and defining them twice is a hard error.
#
# The values below are the generic ones every laptop needs to boot at all; the
# generated file adds the machine-specific modules (touchpad, card reader,
# fingerprint, backlight). Leaving them out is not fatal — it means the device
# silently does not work.
{ config, lib, ... }:
{
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # Storage + USB, needed in the initrd to find the disk it must unlock.
  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usb_storage" "sd_mod" ];
  boot.initrd.kernelModules = [ ];

  # Swap must be at least RAM to hibernate, and sleeping is the point of a
  # laptop. disko has no default on purpose — this is a fact about THIS
  # machine's memory. 18G suits 16G RAM.
  disko.devices.disk.main.content.partitions.swap.size = "18G";

  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  # AMD instead:
  # hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
EOF
fi

# ── home.nix ────────────────────────────────────────────────
[ "$KIND" = server ] || cp "$FLAKE_DIR/scripts/templates/home.nix" "$DIR/home.nix"

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  scaffolded hosts/$NAME ($ROLE)"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "  1. On the new machine, boot the stock NixOS ISO and run:"
echo "       nixos-generate-config --root /tmp --show-hardware-config"
echo "     Paste that into hosts/$NAME/hardware-configuration.nix, KEEPING the"
echo "     swap.size / microcode lines, and DELETE fileSystems + swapDevices."
echo ""
echo "  2. Enrol the host's key, then install:"
echo ""
echo "     remotely, from here (deploy.sh enrols the key itself):"
echo "       nix develop .# --command scripts/deploy.sh $NAME root@<address> /dev/nvme0n1"
echo ""
echo "     or from the machine itself (no reachable target, e.g. a laptop):"
echo "       scripts/enroll-host-key.sh $NAME --out ~/.ssh/$NAME"
echo "       # then, on the ISO console:"
echo "       nix run github:Leoguy77/nixos-config#install-locally -- $NAME --key ~/.ssh/$NAME/ssh_host_ed25519_key"
echo ""
echo "  git add hosts/$NAME && git commit -m 'feat(hosts): add $NAME'"
echo ""
