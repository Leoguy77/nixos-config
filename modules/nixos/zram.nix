# Compressed swap in memory (zram).
#
# Single purpose: give memory-constrained boxes a compressed swap device.
# Reusable by laptops and servers alike.
{
  config,
  lib,
  ...
}:

let
  cfg = config.modules.zram;
in

{
  options.modules.zram = {
    enable = lib.mkEnableOption "zram compressed swap";
    memoryPercent = lib.mkOption {
      type = lib.types.int;
      default = 100;
      description = "zram swap size as a percentage of RAM.";
    };
  };

  config = lib.mkIf cfg.enable {
    zramSwap = {
      enable = true;
      priority = 100;
      inherit (cfg) memoryPercent;
    };
  };
}
