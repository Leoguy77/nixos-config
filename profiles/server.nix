# Server baseline — no desktop, key-only SSH, remote LUKS unlock.
#
# A role profile: it composes the narrow single-purpose modules the second
# server (and mail) need. Every module here does one thing; this file is where
# they are switched on together. Host files write
#   imports = [ ../../profiles/server.nix ];
# and add host-specific data (admin keys, firewall ports) as `modules.*` opts.
{
  pkgs,
  ...
}:
{
  imports = [
    ../modules/nixos/accounts.nix
    ../modules/nixos/fail2ban.nix
    ../modules/nixos/firewall.nix
    ../modules/nixos/locale.nix
    ../modules/nixos/nix-daemon.nix
    ../modules/nixos/remote-unlock.nix
    ../modules/nixos/sshd.nix
    ../modules/nixos/sysctl.nix
    ../modules/nixos/tailscale.nix
    ../modules/nixos/zram.nix
  ];

  # Compose the pieces into a server.
  modules.accounts.enable = true;
  modules.locale.enable = true;
  modules.nix.enable = true;
  modules.fail2ban.enable = true;
  modules.firewall.enable = true;
  modules.firewall.openPorts = [
    22
    80
    443
  ];
  modules.remoteUnlock.enable = true;
  modules.sshd.enable = true;
  modules.sysctl.enable = true;
  modules.tailscale.enable = true;
  modules.zram.enable = true;

  # UEFI boot, reused from the shared narrow modules.
  modules.boot.enable = true;
  modules.boot.systemdBoot = true;
  modules.boot.efi = true;

  # Server tooling. Deliberately not modules.packages: that list carries
  # desktop-only tools (pinentry-qt, fastfetch) a headless box never uses.
  environment.systemPackages = with pkgs; [
    btop
    curl
    git
    htop
    jq
    nano
    rsync
    tmux
    unzip
    vim
  ];
}
