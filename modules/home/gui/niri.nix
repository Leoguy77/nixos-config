# Niri session: compositor config, bar, launcher, locker.
#
# This is the HOME half of profiles/desktops/niri.nix. The NixOS profile turns on
# the compositor and the display manager; everything the session starts lives
# here, because it is all user-scoped config files.
#
# config.kdl does NOT restate niri's defaults. It `include`s the default config
# niri ships (632 lines: every standard bind, input defaults, window rules) and
# only overrides what is actually different. That works because the parser
# merges each node into `Config::default()`, and for the one section where
# merging would be wrong -- `binds {}` -- conflicting keys are REPLACED rather
# than rejected (niri-config/src/lib.rs:219-231: "We replace conflicting binds,
# rather than error, to support the use-case where you import some
# preconfigured-dots.kdl, then override some binds with your own").
#
# Consequence when editing: a bind written here silently wins over the included
# one. Keep this file to deliberate differences only.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.modules.home.desktops.niri;

  # The default config of the niri we actually build, so it cannot drift from
  # the compositor version. Symlinked next to config.kdl and pulled in by a
  # relative `include`.
  defaultConfig = "${pkgs.niri.doc}/share/doc/niri/default-config.kdl";
in
{
  options.modules.home.desktops.niri.enable =
    lib.mkEnableOption "the Niri session (config + bar + launcher + locker)";

  config = lib.mkIf cfg.enable {
    # ── Compositor ────────────────────────────────────────────────────────
    # The config is a real file in this repo (config.kdl, next to this module)
    # symlinked out of the store rather than inlined into a store path. That is
    # the whole point: tuning the compositor is the one thing done dozens of
    # times in a row, and a store-path config forces a full nixos-rebuild switch
    # per attempt. Out of store, an edit goes live on
    # `niri msg action reload-config`.
    #
    # The absolute path is unavoidable -- a store symlink cannot point into the
    # working tree any other way -- so it is derived from homeDirectory rather
    # than repeated per host. A host that enables this module without the repo
    # checked out gets a dangling link and niri's own error, not a failed
    # evaluation: niri then falls back to its compiled-in defaults and the
    # session still starts.
    xdg.configFile = {
      "niri/config.kdl".source =
        config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/Desktop/Code/nixos-config/modules/home/gui/niri/config.kdl";

      # The include target of config.kdl. Deliberately still a store path: it is
      # niri's own file, and pinning it to the build we run is what stops the two
      # drifting apart. A relative include resolves against the directory of the
      # config as opened (~/.config/niri/), even through the symlink above
      # (verified against niri-config/src/lib.rs:345-380).
      "niri/default-config.kdl".source = defaultConfig;
    };

    # ── Bar ───────────────────────────────────────────────────────────────
    # systemd integration deliberately left off: niri's default config already
    # does `spawn-at-startup "waybar"`, so a unit would race it and draw two
    # bars. The module still installs the package (home.packages) and writes
    # ~/.config/waybar/{config,style.css}, which is all that is needed.
    programs.waybar = {
      enable = true;

      settings.mainBar = {
        layer = "top";
        position = "top";
        height = 34;
        spacing = 4;

        modules-left = [
          "niri/workspaces"
          "niri/window"
        ];
        modules-center = [ "clock" ];
        modules-right = [
          "wireplumber"
          "backlight"
          "battery"
          "tray"
        ];

        "niri/workspaces" = {
          format = "{index}";
        };
        "niri/window" = {
          max-length = 60;
          separate-outputs = true;
        };

        clock = {
          format = "{:%a %d %b  %H:%M}";
          tooltip-format = "{calendar}";
        };

        wireplumber = {
          format = "{volume}%";
          format-muted = "muted";
          on-click = "${pkgs.pavucontrol}/bin/pavucontrol";
        };

        # Dell Latitude 5410 exposes intel_backlight; waybar finds it by class.
        backlight.format = "{percent}%";

        battery = {
          format = "{capacity}%";
          states = {
            warning = 30;
            critical = 15;
          };
        };

        tray = {
          icon-size = 18;
          spacing = 8;
        };
      };

      style = ''
        * {
          font-family: "Noto Sans", sans-serif;
          font-size: 13px;
          border: none;
          border-radius: 0;
          min-height: 0;
        }

        window#waybar {
          background: rgba(30, 30, 46, 0.92);
          color: #cdd6f4;
        }

        #workspaces button {
          padding: 0 8px;
          color: #6c7086;
        }

        #workspaces button.active {
          color: #cdd6f4;
          box-shadow: inset 0 -2px #89b4fa;
        }

        #window { color: #a6adc8; }

        #clock, #wireplumber, #backlight, #battery, #tray { padding: 0 10px; }

        #battery.warning { color: #f9e2af; }
        #battery.critical { color: #f38ba8; }
      '';
    };

    # ── Session programs ──────────────────────────────────────────────────
    home.packages = with pkgs; [
      fuzzel # Mod+D launcher
      swaylock # lock screen
      swayidle # idle -> lock -> blank, plus lock before suspend
      mako # notification daemon
      pavucontrol # mixer, opened from the bar
      brightnessctl # XF86MonBrightness* binds from niri's defaults
      playerctl # XF86Audio* media keys from niri's defaults
      xwayland-satellite # runs X11 apps; niri execs it by bare name on demand
    ];
  };
}
