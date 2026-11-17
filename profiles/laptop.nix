# Laptop baseline = desktop + battery-aware power management + full disk
# encryption.
#
# Auto-cpufreq handles the battery/charger governor split (it conflicts with
# power-profiles-daemon, so that is disabled). True S3 deep suspend is forced
# because these machines otherwise stay half-awake in a backpack and drain the
# battery to zero. Import this instead of desktop.nix on anything that runs on
# battery.
#
# The disk layout is imported HERE rather than by each host because a laptop is
# the machine that leaves the house. A desktop stays behind a locked door; a
# laptop gets lost, stolen, or left in a cafe, and an unencrypted root on it is
# the whole threat model. Making it part of the role means a new laptop cannot
# forget it — there is no per-host line to omit.
#
# This imports the layout unconditionally, which is only safe because every
# laptop in this repo is installed by `scripts/deploy.sh`: a disko layout on a
# running system is inert (it affects the *installer*, not the running machine),
# and the script refuses a hardware-configuration.nix that also defines
# fileSystems, so the two cannot disagree. A host that wants a different layout
# sets devices itself; the layout is a default, not a constraint.
#
# An ephemeral (tmpfs) root is NOT part of this role. Encryption is about what
# happens when the machine is stolen; ephemerality is about how much leftover
# drift you are willing to tolerate between reboots, and that is a per-machine
# judgement. To opt in, add the two lines:
#   imports = [ ./state.nix ];
#   modules.disk.ephemeralRoot = true;
{ inputs, ... }:
{
  imports = [
    ./desktop.nix
    ../modules/nixos/autocpufreq.nix
    inputs.disko.nixosModules.disko
    ./disk/luks-btrfs-laptop.nix
  ];

  modules.autocpufreq.enable = true;

  # Force real S3 (deep) suspend instead of s2idle (Modern Standby)
  boot.kernelParams = [ "mem_sleep_default=deep" ];
}
