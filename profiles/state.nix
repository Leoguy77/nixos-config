# Impermanence — persist a declared set of paths across a wiped root.
#
# Opt-in per host: import this file and set `modules.impermanence.enable = true`,
# and pair it with an `ephemeralRoot` disk layout. A host that does not import it
# is untouched — this file is in profiles/, not scanPaths, so nothing switches it
# on by accident.
#
# The point is not "wipe / for fun". It is that the machine's real state is the
# flake, and anything outside this list is a leftover. A reboot then proves the
# config is complete instead of leaving it as a claim.
#
# Two things this file exists to get right, because both are silent data loss:
#
#   1. The sops/age identity must be persisted. `modules/nixos/sops.nix` decrypts
#      with `/etc/ssh/ssh_host_ed25519_key`. On an ephemeral root that key is
#      regenerated every boot, every secret fails to decrypt, and the machine is
#      unusable in a way that looks like a broken flake.
#
#   2. No ordering wiring is needed here, and adding it would be wrong. sops-nix
#      sets `RequiresMountsFor` on its `age.sshKeyPaths` and starts after
#      `local-fs.target`; impermanence's per-path units finish `before`
#      `local-fs.target`. systemd therefore already guarantees the host key is
#      mounted before decryption is attempted.
{
  config,
  inputs,
  lib,
  myvars,
  ...
}:

let
  cfg = config.modules.impermanence;
in

{
  imports = [ inputs.impermanence.nixosModules.impermanence ];

  options.modules.impermanence = {
    enable = lib.mkEnableOption "impermanence (persist a declared path set across a wiped root)";

    persistDir = lib.mkOption {
      type = lib.types.str;
      default = "/persist";
      description = "Mount point of the persistent subvolume. All persisted paths live under here.";
    };
  };

  config = lib.mkIf cfg.enable {
    # impermanence's README is blunt about this: every persistent storage volume
    # must be neededForBoot, or its bind mounts race the root mount and land on an
    # empty directory. The host key lives here, so the failure mode is a machine
    # that boots with no secrets.
    fileSystems.${cfg.persistDir}.neededForBoot = lib.mkDefault true;

    environment.persistence.${cfg.persistDir} = {
      hideMounts = true;

      directories = [
        # NixOS and systemd bookkeeping: generations, timers, machine state.
        "/var/lib/nixos"
        "/var/lib/systemd"

        # Logs. An ephemeral journal dies with the boot that produced the
        # evidence, which is the wrong half of a debugging session to lose.
        "/var/log"

        # Tailscale node identity. Lose it and the machine rejoins the tailnet as
        # a new node with a new address, orphaning every DNS record naming it.
        "/var/lib/tailscale"

        # Bluetooth pairings. Re-pairing every headset on every boot is the
        # classic reason people abandon an ephemeral root.
        "/var/lib/bluetooth"

        # The restic repository password. Generated on first boot by
        # modules/nixos/backup.nix when passwordFile is null; without it every
        # existing snapshot becomes unreadable.
        "/var/backup"

        # sops-nix's per-host age key, for hosts that use one instead of the ssh
        # host key.
        "/var/lib/sops-nix"
      ];

      files = [
        # Machine identity. systemd derives the journal, DHCP identity and
        # machine-scoped services from it; a fresh one every boot means a new
        # journal and a new lease each time.
        "/etc/machine-id"

        # The SSH host keys — which are ALSO the sops/age identity. Losing these
        # is not a "re-trust the fingerprint" annoyance, it is every secret on
        # the machine failing to decrypt.
        "/etc/ssh/ssh_host_ed25519_key"
        "/etc/ssh/ssh_host_ed25519_key.pub"
        "/etc/ssh/ssh_host_rsa_key"
        "/etc/ssh/ssh_host_rsa_key.pub"

        # Saved wifi networks and the flipdot WireGuard connection.
        "/etc/NetworkManager/system-connections"
      ];

      # User state. Deliberately short: this list decides whether a reboot is
      # invisible or infuriating, and every entry is a bet that the path holds
      # state rather than cache.
      users.${myvars.username} = {
        directories = [
          "Desktop"
          "Documents"
          "Pictures"
          "Videos"

          # GPG: the keyring and trust db. Private keys live on the Token2, but
          # the keyring that knows they exist does not.
          {
            directory = ".gnupg";
            mode = "0700";
          }

          # SSH identities and known_hosts. known_hosts especially: re-accepting
          # every fingerprint after every boot trains you to ignore the warning.
          {
            directory = ".ssh";
            mode = "0700";
          }

          # Secret stores and their identities.
          ".password-store"
          ".config/sops"
          ".config/age"
          ".local/share/keyrings"
          ".config/gh"

          # Agent state that cannot be regenerated: conversation history,
          # session summaries, indexed memories.
          ".pi"
          ".local/share/pi"
          ".config/pi"

          # Browsers: profile, bookmarks, extensions, logins. Cache subdirs are
          # not listed — those are correctly thrown away.
          ".mozilla/firefox"

          # Shell history. Losing it is the most disproportionately annoying part
          # of a careless ephemeral root.
          ".local/share/zsh"

          # Repos and the toolchain state that is expensive to rebuild.
          "Development"
          ".config/git"
          ".local/state/nix"
          ".local/share/direnv"
        ];

        files = [
          ".bash_history"
          ".zsh_history"
        ];
      };
    };
  };
}
