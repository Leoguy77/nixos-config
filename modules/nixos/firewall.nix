# Server networking baseline.
#
# Single purpose: a firewall and network stack for a headless server with a
# fixed address — no NetworkManager, no DHCP, nftables with a small open-port
# set, tailscale interface trusted. The actual addresses/gateways are static
# and provider-specific, so they live in the host config, not here.
{
  config,
  lib,
  ...
}:

let
  cfg = config.modules.firewall;
in

{
  options.modules.firewall = {
    enable = lib.mkEnableOption "server network/firewall baseline";

    openPorts = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      default = [ ];
      description = "TCP ports to open on the public interface.";
    };
  };

  config = lib.mkIf cfg.enable {
    networking = {
      useNetworkd = true;
      useDHCP = false;
      nftables.enable = true;
      firewall = {
        enable = true;
        allowedTCPPorts = cfg.openPorts;
        # `tailscale up --ssh` terminates in tailscaled, but admin traffic to
        # the tailnet address should not be fought over by nftables.
        trustedInterfaces = [ "tailscale0" ];
      };
      # Mail servers must not depend on MagicDNS; hosts set real resolvers.
      resolvconf.enable = false;
    };
  };
}
