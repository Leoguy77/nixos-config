# RDP server (xrdp) — remote desktop access into a Plasma session.
#
# Single purpose: expose the host over RDP. This is a real attack-surface
# service, so it is opt-in per host — most machines never open port 3389.
{
  config,
  lib,
  ...
}:

{
  options.modules.rdp = {
    enable = lib.mkEnableOption "the RDP server (xrdp)";
  };

  config = lib.mkIf config.modules.rdp.enable {
    services.xrdp = {
      enable = true;
      defaultWindowManager = "startplasma-x11";
    };
    networking.firewall.allowedTCPPorts = [ 3389 ];
  };
}
