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

    trayApplet = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Install nm-applet. Off by default because most desktops in this repo
        ship a bar that talks to NetworkManager itself (noctalia). Turn it on
        for a desktop whose bar has no network widget.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # No tray applet by default. `networkmanagerapplet` used to be installed here
    # so a bar could show it; noctalia's own `network` widget now opens its
    # control-center network section, which does the same job against the same
    # NetworkManager API (verified: it lists APs and calls ActivateConnection,
    # including the AddAndActivate fallback for an unknown SSID). Keeping the
    # applet too put a second network icon in the tray, and its binary registers
    # an org.freedesktop.NetworkManager secret agent while noctalia registers
    # one too -- two agents means a password prompt can land on the one that is
    # not on screen.
    #
    # A host picking a desktop without noctalia (plasma, hyprland) turns this
    # back on from its own profile.
    environment.systemPackages = lib.mkIf cfg.trayApplet [ pkgs.networkmanagerapplet ];

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
