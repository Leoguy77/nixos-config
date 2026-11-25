# NixOS modules index
#
# Reference: every narrow single-purpose module in modules/nixos. None of
# these are imported through this file — hosts auto-import the directory via
# `mylib.scanPaths ../../modules/nixos`, and role profiles (profiles/*.nix)
# import the modules they compose directly. This index exists so a reader can
# see the whole catalog at a glance.
#
# Note: `enable` defaults to false on every module here, so auto-importing the
# directory is harmless — a host only activates what its profile switches on.
{
  accounts = ./accounts.nix;
  autocpufreq = ./autocpufreq.nix;
  boot = ./boot.nix;
  backup = ./backup.nix;
  dns = ./dns.nix;
  fail2ban = ./fail2ban.nix;
  firewall = ./firewall.nix;
  firmware = ./firmware.nix;
  fonts = ./fonts.nix;
  initrdTailscale = ./initrd-tailscale.nix;
  locale = ./locale.nix;
  mail = ./mail.nix;
  networkmanager = ./networkmanager.nix;
  nix-daemon = ./nix-daemon.nix;
  onepassword = ./onepassword.nix;
  packages = ./packages.nix;
  pipewire = ./pipewire.nix;
  plasma = ./plasma.nix;
  printing = ./printing.nix;
  rdp = ./rdp.nix;
  remoteUnlock = ./remote-unlock.nix;
  security = ./security.nix;
  sops = ./sops.nix;
  ssh = ./ssh.nix;
  sshd = ./sshd.nix;
  sysctl = ./sysctl.nix;
  tailscale = ./tailscale.nix;
  users = ./users.nix;
  wireguard = ./wireguard.nix;
  x11 = ./x11.nix;
  zram = ./zram.nix;
  zsh = ./zsh.nix;
}
