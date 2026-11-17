# Laptop baseline = desktop + battery-aware power management.
#
# Auto-cpufreq handles the battery/charger governor split (it conflicts with
# power-profiles-daemon, so that is disabled). True S3 deep suspend is forced
# because these machines otherwise stay half-awake in a backpack and drain the
# battery to zero. Import this instead of desktop.nix on anything that runs on
# battery.
{ ... }:
{
  imports = [
    ./desktop.nix
    ../modules/nixos/autocpufreq.nix
  ];

  modules.autocpufreq.enable = true;

  # Force real S3 (deep) suspend instead of s2idle (Modern Standby)
  boot.kernelParams = [ "mem_sleep_default=deep" ];
}
