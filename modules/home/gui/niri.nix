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
  # the compositor version.
  defaultConfig = "${pkgs.niri.doc}/share/doc/niri/default-config.kdl";

  terminal = "${pkgs.kitty}/bin/kitty";
  launcher = "${pkgs.fuzzel}/bin/fuzzel";
  lock = "${pkgs.swaylock}/bin/swaylock";
in
{
  options.modules.home.desktops.niri.enable =
    lib.mkEnableOption "the Niri session (config + bar + launcher + locker)";

  config = lib.mkIf cfg.enable {
    # ── Compositor ────────────────────────────────────────────────────────
    # Plain config file rather than Nix options: niri validates its own config
    # (`niri validate -c <file>`), so re-modelling the schema in Nix would add a
    # second, worse schema over the real one.
    xdg.configFile."niri/config.kdl".text = ''
      // Generated from modules/home/gui/niri.nix — edit there, not here.

      // Every standard bind, input default, window rule, and the
      // `spawn-at-startup "waybar"` that starts the bar. A bind restated below
      // replaces the included one.
      include "${defaultConfig}"

      input {
        // xkb is deliberately NOT set. With an empty `xkb {}` block (as in the
        // included default) niri takes the layout from
        // org.freedesktop.locale1, which NixOS drives from
        // services.xserver.xkb.layout (modules/nixos/locale.nix). Writing a
        // layout here would silently ignore modules.nixos.locale.

        // `touchpad` REPLACES the included one wholesale rather than merging
        // field-by-field -- merge_clone! in niri-config/src/macros.rs:11-19 does
        // `clone_from`, and the shipped default-config.kdl says as much:
        // "Omitting settings disables them". So tap + natural-scroll must be
        // restated here or they are silently switched off. (Verified: dropping
        // them left only `dwt` in effect.)
        touchpad {
          tap
          natural-scroll
          dwt // ignore the touchpad while typing
        }
      }

      // niri has no idle daemon of its own; swayidle does the lock-then-blank
      // ladder. `-w` also covers suspend via the before-sleep hook.
      //
      // One KDL string = one argv entry: spawn-at-startup execs directly, with
      // no shell. swayidle matches argv[i] against the literal words `timeout`
      // and `before-sleep` (swayidle main.c:864-892) and exits with
      // "Unsupported command" on anything else, so the keywords must be their
      // own arguments. The command *it* runs goes through `sh -c`
      // (main.c:156), so quoting inside that one argument is fine.
      spawn-at-startup "${pkgs.swayidle}/bin/swayidle" "-w" \
        "timeout" "300" "${lock}" \
        "timeout" "600" "niri msg action power-off-monitors" \
        "before-sleep" "${lock}"

      spawn-at-startup "${pkgs.mako}/bin/mako"

      // ── Overrides ───────────────────────────────────────────────────────
      // The defaults bind Mod+T to alacritty and Mod+D to fuzzel already; only
      // the terminal differs (alacritty is not installed here).
      binds {
        Mod+T hotkey-overlay-title="Terminal: kitty" { spawn "${terminal}"; }
        Mod+D hotkey-overlay-title="Launcher: fuzzel" { spawn "${launcher}"; }
        Super+Alt+L hotkey-overlay-title="Lock" { spawn "${lock}"; }
      }
    '';

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
