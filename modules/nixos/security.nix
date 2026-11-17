# Security extras: polkit + smart-card daemon.
#
# Single purpose: the desktop privilege/credential plumbing. Sudo lives in
# accounts.nix (it belongs with the admin identity, not with polkit).
{
  config,
  lib,
  ...
}:

{
  options.modules.security = {
    enable = lib.mkEnableOption "polkit and smart-card support";
  };

  config = lib.mkIf config.modules.security.enable {
    # Polkit for privilege escalation
    security.polkit.enable = lib.mkDefault true;

    # Smart-card daemon for FIDO2/PIV/OpenPGP over CCID (Token2 security keys)
    services.pcscd.enable = lib.mkDefault true;
  };
}
