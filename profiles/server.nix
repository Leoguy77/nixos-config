# Server baseline — no desktop, key-only SSH, remote LUKS unlock.
#
# A role profile: it composes the narrow single-purpose modules the second
# server (and mail) need. Every module here does one thing; this file is where
# they are switched on together. Host files write
#   imports = [ ../../profiles/server.nix ];
# and add host-specific data (admin keys, firewall ports) as `modules.*` opts.
{
  pkgs,
  inputs,
  system,
  lib,
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

  # ── Channel ──────────────────────────────────────────────────────────────
  # A server is exactly what the `-small` channel gates on (nginx, openssh,
  # postgres, php, …), so it publishes security fixes days before the large
  # channel does — nginx 1.30.7, the nginx2shell fix, landed there first.
  #
  # Setting `nixpkgs.pkgs` replaces the whole package set for this host, which
  # is why the choice belongs here and not in flake.nix: importing this file IS
  # the server role, so no host has to be listed anywhere else.
  #
  # CONTRACT: `nixpkgs.config` and `nixpkgs.pkgs` are mutually exclusive
  # (nixos/modules/misc/nixpkgs.nix asserts it). Any host importing this file
  # must keep `nixpkgs.config` empty — pass options like allowUnfree to the
  # `import` below, not as `nixpkgs.config.*`. Deliberately not guarded with a
  # custom check: nixpkgs' own assertion fails the evaluation with
  # "system configures nixpkgs with an externally created instance", and CI
  # builds every host, so a violation is a red run rather than a surprise.
  nixpkgs.pkgs = import inputs.nixpkgs-small {
    inherit system;
    config.allowUnfree = true;
  };

  # `nixosSystem` sets this from the *calling* flake's nixpkgs input, which is
  # still the large channel. Left alone it would pin `nix.registry.nixpkgs` to
  # 1.30.6 on a host running 1.30.7, so `nix-shell -p nginx` would silently get
  # the vulnerable build.
  #
  # This fixes the registry only. The module tree is chosen in flake.nix's
  # mkHost, which calls nixosSystem on this channel's lib for exactly these
  # hosts — a mismatch there builds old modules against new packages.
  nixpkgs.flake.source = lib.mkForce inputs.nixpkgs-small.outPath;

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
