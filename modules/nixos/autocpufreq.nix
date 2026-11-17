# Auto CPU frequency governor (battery vs charger).
#
# Single purpose: the auto-cpufreq power daemon for laptops. Conflicts with
# power-profiles-daemon, so enabling this disables that.
{
  config,
  lib,
  ...
}:

{
  options.modules.autocpufreq = {
    enable = lib.mkEnableOption "auto-cpufreq power management";
  };

  config = lib.mkIf config.modules.autocpufreq.enable {
    services.auto-cpufreq = {
      enable = true;
      settings = {
        battery = {
          governor = "powersave";
          turbo = "never";
        };
        charger = {
          governor = "performance";
          turbo = "auto";
        };
      };
    };
    services.power-profiles-daemon.enable = false;
  };
}
