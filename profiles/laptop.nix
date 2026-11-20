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
{ inputs, pkgs, ... }:
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

  # Hibernate with a kernel-written image, not the firmware's. /sys/power/disk
  # offers [platform] shutdown reboot suspend test_resume and systemd takes the
  # first entry that works, so the default is always `platform` -- ACPI S4, where
  # the firmware is expected to save memory. It cannot: swap here is LUKS-
  # encrypted, so nothing outside the kernel can write the image, and the
  # matching EFI HibernateLocation variable is never created either (systemd
  # skips it when resume= is on the cmdline). `shutdown` is the kernel writing
  # the image to swap itself and then powering off, which is the only mode that
  # can work on this disk layout. Proven with pm_test=core: hibernation entry now
  # runs to "Allocated 6208020 kbytes" where before it never started at all.
  systemd.sleep.settings.Sleep.HibernateMode = "shutdown";

  # Closing the lid sleeps like suspend, but only for a while: after the delay
  # systemd writes the hibernation image and powers off. The point is the worn
  # pack (57% of design capacity), where a plain S3 suspend keeps drawing power
  # and a low laptop in a bag reaches 0% and loses the session. upower's
  # CriticalPowerAction covers the emergency case; this covers the ordinary one.
  #
  # HandleLidSwitch only. The docked and external-power variants are left at
  # their defaults (ignore and suspend): a lid closed on shore power has no
  # battery to run out, so plain suspend is correct and faster to resume from.
  #
  # 2 hours is the same figure systemd uses when a machine reports no battery,
  # and it is comfortably under this pack's runtime -- roughly 3.5%/hour of
  # suspend drain on 28.9 Wh means even a 20% battery lasts ~6 hours asleep.
  services.logind.settings.Login.HandleLidSwitch = "suspend-then-hibernate";
  systemd.sleep.settings.Sleep.HibernateDelaySec = "2h";

  # Revive the touchpad after resuming from hibernation. It comes back dead:
  # the controller (i2c_designware on LPSS 0000:00:15.1, touchpad chip at 0x2c)
  # logs "controller timed out", "timeout in disabling adapter" and then
  # thousands of "timeout waiting for bus ready", while the device node, the
  # libinput listing and the sysfs bindings all still look healthy. No probe
  # error anywhere -- the bus is simply silent, so rebinding i2c_hid, reloading
  # i2c_hid/i2c_hid_acpi/hid_multitouch, and unbinding the designware platform
  # device all leave it dead.
  #
  # Removing the PCI function and rescanning does bring it back, and is the
  # only thing that does: it recreates the adapter, the client device is
  # re-enumerated and i2c_hid probes it for real. Verified by hand on this
  # machine after a resume had left the bus dead -- the rescan produced a fresh
  # enumeration and the last "timeout waiting for bus ready" in the journal is
  # the one immediately before it.
  #
  # Nothing else on 0000:00:15.1 shares the bus, so re-adding the function
  # cannot disturb another device.
  #
  # Hooked through system-sleep, systemd's own pre/post callout around
  # write_state, and not powerManagement.resumeCommands, which fires on any
  # resume and would churn the controller after every suspend. Hibernation only.
  #
  # $2 is the MAIN operation, not the step systemd is currently running
  # (sleep.c:249 passes main_operation to the hook on purpose), so hibernation
  # reached through suspend-then-hibernate arrives as "suspend-then-hibernate".
  # Matching only "hibernate" would look correct and never once fire for a lid
  # close, which is now the usual way this machine hibernates.
  #
  # Absolute paths for everything external: writeShellScript sets the shebang but
  # NOT PATH (unlike writeShellScriptBin, which wraps with --prefix PATH), and
  # systemd execs this with the manager's environment. A bare `sleep 1` failed
  # with "line 10: sleep: command not found" on the first real hibernation
  # (2026-11-20 08:41:06). `echo` and the redirects are bash builtins, so only
  # sleep needs qualifying.
  environment.etc."systemd/system-sleep/touchpad-hibernate".source =
    pkgs.writeShellScript "touchpad-hibernate" ''
      # Only hibernation leaves the bus wedged; leave suspend alone.
      case "$2" in
        hibernate | suspend-then-hibernate) ;;
        *) exit 0 ;;
      esac
      [ "$1" = "post" ] || exit 0

      # Wait for the restored system to settle before poking the controller.
      ${pkgs.coreutils}/bin/sleep 1
      echo 1 > /sys/bus/pci/devices/0000:00:15.1/remove
      echo 1 > /sys/bus/pci/rescan
    '';
}
