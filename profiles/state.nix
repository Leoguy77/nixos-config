# Impermanence — persist a declared set of system paths across a wiped root.
#
# A profile, not a module: importing this file IS the switch, so there is no
# `enable` flag to set as well. It stays out of modules/nixos on purpose —
# `scanPaths` would auto-import it everywhere, and impermanence's NixOS module
# unconditionally injects `home-manager.sharedModules` into whichever host it
# lands on. A host that does not want this should not pay for it.
#
# Pair it with an `ephemeralRoot` disk layout: a tmpfs / plus a /persist
# subvolume. Without one the persistence is inert but harmless.
#
# The point is not "wipe / for fun". The machine's real state is the flake, so
# anything outside this list is a leftover, and a reboot proves the config is
# complete instead of leaving it as a claim.
#
# SCOPE: /home is NOT made ephemeral by any layout here. It is a real btrfs
# subvolume, so user data survives on its own and is deliberately absent from
# this list. That is the whole design: the risky half (system state, where a
# forgotten file breaks boot) is declared and provable, and the half with
# irreplaceable data (home) is not a guess. Enumerating user paths would mean
# the machine silently eats whatever was not listed — `.config/mozilla` instead
# of `.mozilla/firefox` is exactly that bug, and it costs 976M of profile.
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
{ inputs, ... }:

{
  imports = [ inputs.impermanence.nixosModules.impermanence ];

  # impermanence's README is blunt about this: the persistent volume must be
  # neededForBoot, or the bind mounts race the root mount and land on an empty
  # directory. The sops host key lives here, so that failure mode is a machine
  # that boots with no secrets.
  fileSystems."/persist".neededForBoot = true;

  # The sops/age identity must be readable where the "users" activation runs, and
  # that is NOT /etc/ssh. `neededForUsers` secrets (the login password hash) are
  # decrypted by sops-nix's `setupSecretsForUsers` ACTIVATION SCRIPT, and NixOS
  # runs activation from the initrd — `initrd-nixos-activation` does
  # `exec chroot /sysroot "$closure/prepare-root"` because users must exist before
  # any stage-2 unit starts. At that point impermanence's `/persist/etc/ssh →
  # /etc/ssh` bind mount has not happened yet, so the /etc path from
  # modules/nixos/sops.nix does not exist and sops fails with
  #   "Error getting data key: 0 successful groups required, got 0"
  # followed by "password file /run/secrets-for-users/… does not exist" — and the
  # greeter then has no password to check, i.e. a machine that boots fine, serves
  # SSH by key, and cannot be logged into. /persist IS mounted by then (disko
  # gives it neededForBoot), so the persisted copy is the one that works.
  #
  # Both paths are kept: this one covers the initrd activation (and the
  # nixos-install activation, which chroots the same way), the /etc one covers
  # stage-2 services. `age.sshKeyPaths` is a list option, so the definitions
  # merge, and a missing path only produces a warning.
  sops.age.sshKeyPaths = [ "/persist/etc/ssh/ssh_host_ed25519_key" ];

  environment.persistence."/persist" = {
    hideMounts = true;

    directories = [
      # NixOS and systemd bookkeeping: generations, timers, machine state.
      "/var/lib/nixos"
      "/var/lib/systemd"

      # Root's home. `/` is tmpfs, so without this /root is empty every boot —
      # root shell history, root's .ssh and any token files dropped there are
      # gone. Cheap to keep and only surprising once.
      "/root"

      # Logs. An ephemeral journal dies with the boot that produced the evidence,
      # which is the wrong half of a debugging session to lose.
      "/var/log"

      # Tailscale node identity. Lose it and the machine rejoins the tailnet as a
      # new node with a new address, orphaning every DNS record naming it.
      "/var/lib/tailscale"

      # Bluetooth pairings. Re-pairing every headset on every boot is the classic
      # reason people abandon an ephemeral root.
      "/var/lib/bluetooth"

      # The restic repository cache: sops supplies the password, but restic's own
      # cache and the fallback generated file live here too.
      "/var/backup"

      # sops-nix's per-host age key, for hosts that use one instead of the ssh
      # host key.
      "/var/lib/sops-nix"

      # Saved wifi networks and the flipdot WireGuard connection. A DIRECTORY, so
      # it belongs here — listed under `files` impermanence would symlink the
      # directory itself and NetworkManager would see no saved networks.
      "/etc/NetworkManager/system-connections"
    ];

    files = [
      # Machine identity. systemd derives the journal, DHCP identity and
      # machine-scoped services from it; a fresh one every boot means a new
      # journal and a new lease each time.
      "/etc/machine-id"

      # The SSH host keys — which are ALSO the sops/age identity. Losing these is
      # not a "re-trust the fingerprint" annoyance, it is every secret on the
      # machine failing to decrypt. Persist ALL of them: NixOS 25.11 also
      # generates ssh_host_mldsa44_ed25519_key (post-quantum), and a key that is
      # recreated every boot breaks any client that pinned the old one.
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
      "/etc/ssh/ssh_host_rsa_key"
      "/etc/ssh/ssh_host_rsa_key.pub"
      "/etc/ssh/ssh_host_mldsa44_ed25519_key"
      "/etc/ssh/ssh_host_mldsa44_ed25519_key.pub"
    ];
  };
}
