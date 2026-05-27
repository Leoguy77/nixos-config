# System services
{ config, pkgs, lib, ... }:

{
  # Display & Desktop
  services = {
    xserver = {
      enable = true;
      xkb = {
        layout = "de";
        variant = "";
      };
    };

    displayManager.sddm.enable = true;
    desktopManager.plasma6.enable = true;

    # Audio
    pipewire = {
      enable = true;
      alsa = {
        enable = true;
        support32Bit = true;
      };
      pulse.enable = true;
    };

    # Printing
    printing.enable = true;

    # SSH
    openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
      };
    };
  };

  # Power management (good for Surface/laptops)
  services.power-profiles-daemon.enable = false;
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
}
