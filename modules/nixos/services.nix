# System services configuration
{ config, pkgs, lib, inputs, ... }:

let
  cfg = config.modules.services;
in

{
  options.modules.services = {
    enable = lib.mkEnableOption "services module";
    x11 = lib.mkEnableOption "X11";
    plasma = lib.mkEnableOption "KDE Plasma";
    pipewire = lib.mkEnableOption "PipeWire audio";
    printing = lib.mkEnableOption "printing service";
    ssh = lib.mkEnableOption "SSH server";
    rdp = lib.mkEnableOption "RDP server (xrdp)";
    autoCpufreq = lib.mkEnableOption "auto-cpufreq power management";
  };

  config = lib.mkIf cfg.enable {
    # X11
    services.xserver.enable = lib.mkDefault cfg.x11;

    # KDE Plasma
    services.displayManager.sddm.enable = lib.mkDefault cfg.plasma;
    services.desktopManager.plasma6.enable = lib.mkDefault cfg.plasma;

    # Audio (PipeWire)
    security.rtkit.enable = lib.mkDefault true;
    services.pipewire = lib.mkIf cfg.pipewire {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      jack.enable = true;
    };

    # Printing
    services.printing.enable = lib.mkDefault cfg.printing;

    # SSH
    services.openssh = lib.mkIf cfg.ssh {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = lib.mkDefault "no";
      };
    };

    # RDP
    services.xrdp.enable = lib.mkIf cfg.rdp true;
    services.xrdp.defaultWindowManager = lib.mkIf cfg.rdp "startplasma-x11";
    networking.firewall.allowedTCPPorts = lib.mkIf cfg.rdp [ 3389 ];

    # Auto CPU Frequency
    services.auto-cpufreq = lib.mkIf cfg.autoCpufreq {
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
  };
}
