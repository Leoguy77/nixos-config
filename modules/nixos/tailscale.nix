# Tailscale VPN client.
#
# Single purpose: join this host to the tailnet. No exit-node/subnet-router
# role by default. Whether the firewall trusts the tailscale interface is a
# per-host decision (servers prefer `tailscale ssh`, desktops route GUI admin
# traffic over it), so it is an option, not hardcoded.
{
  config,
  lib,
  ...
}:

let
  cfg = config.modules.tailscale;
in

{
  options.modules.tailscale = {
    enable = lib.mkEnableOption "Tailscale VPN client";

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Trust the tailscale interface in the firewall.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.tailscale = {
      enable = true;
      # No exit node / subnet router.
      useRoutingFeatures = "none";
      inherit (cfg) openFirewall;
    };
  };
}
