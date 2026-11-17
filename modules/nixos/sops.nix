# System-level sops (sops-nix) — decrypts secrets into /run/secrets/<name>.
#
# Enabled by default so existing hosts keep working. A host whose age key is not
# in .sops.yaml may still have it on, as long as it declares no secrets: sops-nix
# only starts its boot service when the secret set is non-empty.
{
  config,
  lib,
  sops-nix,
  ...
}:

let
  cfg = config.modules.sops;
in

{
  imports = [ sops-nix.nixosModules.sops ];

  options.modules.sops.enable = lib.mkEnableOption "system secrets via sops-nix" // {
    default = true;
  };

  config = lib.mkIf cfg.enable {
    sops = {
      defaultSopsFile = ../../secrets/secrets.sops.yaml;

      # Decrypt with the machine's SSH host key (sops-nix converts it to an age
      # identity internally, so it works even though raw age can't use host keys).
      age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    };

    # Declared only when the consumer is enabled. sops-nix starts a boot service
    # whenever the secret set is non-empty, so one unused secret makes every host
    # try to decrypt a key it may not be a recipient of — activation fails and
    # the machine does not come up. With nothing declared here, turning
    # modules.sops on for a host is free until that host has a secret of its own.
    sops.secrets = lib.mkMerge [
      (lib.mkIf config.modules.wireguard.enable {
        wg0_private_key = { };
      })
      # The repository password. It has to come from sops rather than the
      # generated /var/backup/restic-password: a generated file cannot be
      # reproduced from the flake, so a reinstall or an ephemeral root destroys
      # the only copy and every existing snapshot becomes unreadable.
      (lib.mkIf config.modules.backup.enable {
        restic_password = { };
      })
      # The sftp key, kept separate from restic_password on purpose: rotating
      # the password re-encrypts nothing but the repository key, while rotating
      # this means re-authorising one line on the far side.
      #
      # Gated on the repository being remote, not on `sshKeyFile` — that option's
      # default reads this very set, so testing it here is an infinite recursion.
      (lib.mkIf (config.modules.backup.enable && lib.hasPrefix "sftp:" config.modules.backup.repository) {
        restic_ssh_key = { };
      })
    ];
  };
}
