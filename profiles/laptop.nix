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

  # UPower, for the battery. noctalia's battery widget and the power page of its
  # control center read org.freedesktop.UPower and nothing else -- no
  # /sys/class/power_supply fallback -- so with the daemon off the widget is
  # empty and the power page blank, on a machine whose BAT0 is fine. waybar read
  # /sys directly and needed no daemon; a D-Bus bar does.
  #
  # It is also the only thing that acts on a low battery. logind does not watch
  # charge at runtime (battery_is_discharging_and_low in systemd's battery-util
  # is used by systemd-battery-check at early boot, not by logind), so with no
  # upower nothing was watching, and the boot that "turned off hard" ends mid-
  # activity with no shutdown, no suspend and no hibernate in it.
  #
  # PowerOff rather than the default HybridSleep: hibernate has never once
  # written an image on this machine, and HybridSleep suspends afterwards, which
  # is the worst of both -- asleep at 0%. PowerOff always works. Swap it to
  # "Hibernate" the day `systemctl hibernate` is shown to resume here.
  services.upower = {
    enable = true;
    criticalPowerAction = "PowerOff";
  };

  # Force real S3 (deep) suspend instead of s2idle (Modern Standby)
  boot.kernelParams = [ "mem_sleep_default=deep" ];
}
