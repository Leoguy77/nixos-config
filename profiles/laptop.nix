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
  # PowerOff rather than the default HybridSleep. HybridSleep writes an image
  # and then suspends, so a machine that dies at 0% wakes to a dead battery and
  # has to re-read the image it just wrote. PowerOff always works and is what a
  # flat battery needs. Hibernate itself does work here now (see below).
  services.upower = {
    enable = true;
    criticalPowerAction = "PowerOff";
  };

  # Force real S3 (deep) suspend instead of s2idle (Modern Standby)
  boot.kernelParams = [ "mem_sleep_default=deep" ];

  # Hibernation NEEDS this kernel. On 6.18.63 every `systemctl hibernate`
  # aborted inside copy_data_pages(): it logged "Creating image:" and "Need to
  # copy N pages" and then unwound to "hibernation exit" with the machine still
  # awake, no image on swap, and no "Preparing to enter system sleep state S4"
  # anywhere in the journal -- over seven attempts across the platform, shutdown
  # and reboot disk modes, with pm_test at [none] and the i2c touchpad pruned
  # from the wake sources. 7.3.4 reaches S4 every time. Newer than 6.18, not a
  # step backwards.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Lid close: suspend-then-hibernate on battery, stay awake on external power.
  #
  # On battery, S3 keeps drawing power and this pack is worn to ~57% of design
  # capacity, so "suspend forever" means the session is lost when the battery
  # runs out. After HibernateDelaySec the kernel writes the image to swap and
  # powers down, so a drained pack costs nothing but a resume. Safe because
  # hibernation actually works on 7.3.4 (see the kernel note above), and the
  # touchpad wake prune below is what makes the delay reachable at all.
  #
  # On external power, do nothing. The machine stays at S0 and keeps working with
  # the lid shut -- it is plugged in, there is nothing to conserve. This must be
  # set EXPLICITLY: logind picks the action in logind-button.c:150 and falls back
  # to HandleLidSwitch only when HandleLidSwitchExternalPower is an invalid
  # action. nixpkgs leaves it unset, so it reads back from D-Bus as the empty
  # string, and the value that looked like "no policy" is what quietly turned a
  # plugged-in lid close into a suspend.
  #
  # HandleLidSwitchDocked is already `ignore` by default (logind-core.c:62) and
  # is checked first (logind-button.c:148), so a docked lid is fine as-is.
  #
  # 2h: roughly 3.5%/hour of S3 drain on 28.9 Wh, so even a 20% battery lasts
  # ~6h asleep while staying well inside the delay.
  services.logind.settings.Login.HandleLidSwitch = "suspend-then-hibernate";
  services.logind.settings.Login.HandleLidSwitchExternalPower = "ignore";
  systemd.sleep.settings.Sleep.HibernateDelaySec = "2h";

  # The power button must do NOTHING at the OS level.
  #
  # Both things that could handle it are wrong here.
  #
  # niri grabs the power key and maps it to Action::Suspend
  # (src/input/mod.rs:4414), holding a `block` inhibitor on handle-power-key so
  # logind never applies policy. The press that powers the machine back ON after
  # a hibernate is still delivered to the kernel once the image is restored, so
  # niri suspended again 1.2 s after every resume -- measured three times in a
  # row at [268.63] [292.96] [316.00], 23 s apart. That is the "came back to the
  # lock screen and nothing responds" hang. `disable-power-key-handling` in the
  # niri config takes niri out of it.
  #
  # logind is not a safe fallback. HoldoffTimeoutSec does NOT cover this:
  # logind-dbus.c:2032 only calls manager_set_lid_switch_ignore(), and the
  # comment there says so ("Make sure the lid switch is ignored for a while").
  # power_key_ignore_inhibited defaults to false (logind-core.c:64), so nothing
  # suppresses HandlePowerKey on the resume press. `hibernate` would loop
  # exactly as niri did, only writing ~5 GB to swap per cycle; `poweroff` would
  # cut the machine dead on a stray press. `ignore` returns before any action is
  # taken (logind-action.c:355-358).
  #
  # The button still powers the machine on and still wakes it from suspend or
  # hibernate -- that is firmware and kernel, not logind. Hibernate and suspend
  # stay on the session menu and on the lid.
  services.logind.settings.Login.HandlePowerKey = "ignore";

  # The i2c-HID touchpad is armed as a wake source by default and fires in S3
  # with nothing touching it. That silently defeats suspend-then-hibernate:
  # the spurious wake is not the RTC alarm, so systemd takes the
  # `if (!woken_by_timer) return 0;` branch in custom_timer_suspend
  # (sleep.c:501) and treats it as a manual wakeup -- no re-suspend, no
  # hibernate, just a laptop sitting awake until the battery runs out.
  #
  # Measured on this machine, twice, with an RTC alarm armed for 60s:
  #   wakeup enabled  -> resumed after 10s, pm_wakeup_irq 51 (DELL09A0:00)
  #   wakeup disabled -> slept the full 64s, pm_wakeup_irq empty (RTC)
  #
  # `power/wakeup` only governs system-sleep wakeup, so the touchpad behaves
  # normally while the machine is awake; tap-to-wake is the one thing lost, and
  # the lid or any key still wakes it.
  services.udev.extraRules = ''
    SUBSYSTEM=="i2c", DRIVER=="i2c_hid_acpi", ATTR{power/wakeup}="disabled"

    # TOKEN2 FIDO2 security keys (349e) are missing from libfido2's official
    # 70-u2f.rules (only 0020/0022 FIDO variants are listed, not the R3 0024
    # FIDO+PGP or the 0200-series Bio3 line). Without uaccess the hidraw node
    # stays root:root 0600, so 1Password's helper gets FIDO_ERR_INTERNAL and
    # the key blinks waiting for a touch it can never receive. fido_id only
    # tags USB keys with ID_SECURITY_TOKEN, and 0024 is not among them.
    #
    # Matched by VID/PID so every variant of this key family gets in.
    KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="349e", TAG+="uaccess"
  '';

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
