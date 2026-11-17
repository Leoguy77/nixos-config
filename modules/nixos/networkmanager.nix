# Desktop networking: NetworkManager + systemd-resolved + host firewall.
#
# Single purpose: how a desktop machine talks to the network. Distinct from
# server networking (firewall.nix) which uses networkd/nftables — a laptop
# needs NetworkManager for WiFi/roaming.
{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.modules.networkmanager;
in

{
  options.modules.networkmanager = {
    enable = lib.mkEnableOption "NetworkManager desktop networking";
  };

  config = lib.mkIf cfg.enable {
    # Tray applet for picking networks — belongs with NetworkManager, not with
    # the generic package list (servers have no NetworkManager).
    environment.systemPackages = [ pkgs.networkmanagerapplet ];

    networking = {
      networkmanager.enable = lib.mkDefault true;
      # systemd-resolved routes per link (split DNS), so Tailscale MagicDNS
      # (.ts.net) and flipdot's resolver (.fd, 192.168.3.254) coexist instead of
      # one overwriting /etc/resolv.conf and dropping the other.
      networkmanager.dns = "systemd-resolved";
      firewall = {
        enable = lib.mkDefault true;
        # Plain definition, not mkDefault: firewall.allowedTCPPorts merges by
        # concatenation, but a mkDefault list is discarded as soon as a module
        # that adds a port (rdp.nix -> 3389) defines the option at normal
        # priority. That silently dropped port 22.
        allowedTCPPorts = [ 22 ]; # SSH
      };
    };

    services.resolved.enable = true;
  };
}
