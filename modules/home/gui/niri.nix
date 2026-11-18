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

  # OS wallpaper from nixos-artwork, the same set the NixOS installer offers.
  # `gnomeFilePath` rather than `kdeFilePath`: both point at the same PNG, but
  # the gnome one is a stable `share/backgrounds/...` path, while the kde one
  # lives under a per-wallpaper `share/wallpapers/<name>/contents/images/`
  # layout that is an implementation detail of Plasma's wallpaper plugin.
  wallpaper = pkgs.nixos-artwork.wallpapers.catppuccin-mocha.gnomeFilePath;
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
    # `niri msg action load-config-file`.
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

      # Wallpaper, symlinked to a stable name so config.kdl can just point
      # swaybg at `~/.config/niri/wallpaper.png`. A literal store path in an
      # out-of-store file would go stale on every nixpkgs bump; this one is
      # re-pointed by home-manager.
      "niri/wallpaper.png".source = wallpaper;
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
          "custom/swaync"
          "wireplumber"
          "backlight"
          "battery"
          "tray"
        ];

        # Notification count, click to open the control centre. swaync-client
        # --subscribe-waybar emits {text, alt, tooltip, class} JSON whenever the
        # notification list changes, so this needs return-type = "json" and no
        # interval.

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

        "custom/swaync" = {
          exec = "${pkgs.swaynotificationcenter}/bin/swaync-client -swb";
          return-type = "json";
          tooltip = true;
          on-click = "${pkgs.swaynotificationcenter}/bin/swaync-client -t -sw";
          on-click-right = "${pkgs.swaynotificationcenter}/bin/swaync-client -d -sw";
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

        #custom-swaync { padding: 0 10px; color: #a6adc8; }
        #custom-swaync.dnd { color: #f38ba8; }
        #custom-swaync.unread { color: #89b4fa; }

        #battery.warning { color: #f9e2af; }
        #battery.critical { color: #f38ba8; }
      '';
    };

    # ── Session programs ──────────────────────────────────────────────────
    home.packages = with pkgs; [
      fuzzel # Mod+D launcher
      swayidle # idle -> lock -> blank, plus lock before suspend
      pavucontrol # mixer, opened from the bar
      libnotify # notify-send, for testing swaync from a shell
      brightnessctl # XF86MonBrightness* binds from niri's defaults
      playerctl # XF86Audio* media keys from niri's defaults
      xwayland-satellite # runs X11 apps; niri execs it by bare name on demand
      swaybg # draws the wallpaper; see the note in config.kdl
    ];
    # ── PolicyKit authentication agent ────────────────────────────────────
    # A Wayland session gets no polkit agent for free: polkitd is a system
    # service that only decides, and something in the session has to draw the
    # password prompt. Plasma ships its own; niri does not, and the niri NixOS
    # module has no polkit reference at all — so until now every privileged
    # prompt was silently dropped.
    #
    # What still worked without it: mounting removable media, because
    # org.freedesktop.udisks2.filesystem-mount is allow_active=yes. What did
    # not: anything auth_admin — formatting a disk, most NetworkManager edits.
    # Those fail with no dialog and no error the user can see, which is why this
    # is worth fixing before cosmetics.
    #
    # polkit-gnome rather than hyprpolkitagent: it is the plain GTK agent, so a
    # prompt does not drag in a Qt/Kirigami stack, and home-manager already has
    # a module that declares the right systemd user unit.
    services.polkit-gnome.enable = true;

    # ── Clipboard history ─────────────────────────────────────────────────
    # The HM module runs two watchers (`wl-paste --watch cliphist store`), one
    # for text and one for images, and declares cliphist itself. Only the
    # picker is missing, which is a bind in config.kdl.
    services.cliphist = {
      enable = true;

      # Images in history are worth having (screenshot -> paste), and the
      # watcher is a separate cheap process. Setting this false would leave
      # images unrecorded entirely.
      allowImages = true;

      # Defaults: 500 entries, dedupe within the last 10. Long enough to find
      # something from days ago, bounded enough that the DB stays small.
    };

    # ── Notifications ─────────────────────────────────────────────────────
    # swaync replaces mako. Both claim the `org.freedesktop.Notifications`
    # D-Bus name, so exactly one can run; mako's spawn-at-startup line is gone
    # from config.kdl and swaync is a systemd user service instead
    # (PartOf/WantedBy config.wayland.systemd.target, which defaults to
    # graphical-session.target — active under niri).
    #
    # What this buys over mako: a notification history (a notification you miss
    # while the screen is locked is not lost), click-to-open control centre,
    # and do-not-disturb. mako draws toasts and nothing else — it keeps no
    # history at all, which is why a missed notification was simply gone.
    services.swaync = {
      enable = true;

      # Only keys that differ from the packaged schema defaults are set. The
      # defaults already are positionX=right, positionY=top, layer=overlay,
      # layer-shell=true, so restating them would only add drift.
      settings = {
        control-center-width = 400;
        notification-window-width = 360;

        # 0 = never expire. Critical notifications are the ones an app
        # explicitly marks as needing attention (a failed backup, a battery
        # warning), so losing one silently would be the worst case.
        timeout = 10;
        timeout-critical = 0;

        fit-to-screen = true;
        hide-on-clear = false;

        notification-icon-size = 48;
        text-empty = "No notifications";
      };

      # swaync loads its packaged style.css as a base and then this file as an
      # override at the same priority (src/functions.vala:92-127), so the ones
      # that matter are the `:root` custom properties — everything downstream
      # reads them through var(). That makes the theme ~25 lines instead of a
      # 561-line copy of upstream's stylesheet.
      #
      # Catppuccin Mocha, matching the waybar/hyprlock palette: base #1e1e2e,
      # surface0 #313244, surface1 #45475a, overlay0 #6c7086, text #cdd6f4,
      # blue #89b4fa.
      style = ''
        :root {
          --cc-bg: rgba(30, 30, 46, 0.96);
          --noti-bg: 30, 30, 46;
          --noti-bg-alpha: 0.96;
          --noti-bg-darker: rgb(24, 24, 37);
          --noti-bg-hover: rgb(49, 50, 68);
          --noti-bg-focus: rgba(69, 71, 90, 0.7);
          --noti-close-bg: rgb(69, 71, 90);
          --noti-close-bg-hover: rgb(88, 91, 112);
          --noti-border-color: rgba(137, 180, 250, 0.18);
          --text-color: rgb(205, 214, 244);
          --text-color-disabled: rgb(108, 112, 134);
          --bg-selected: rgb(137, 180, 250);
          --border-radius: 12px;
        }

        /* The control centre and notification cards inherit --cc-bg, but the
           summary line is drawn with the link colour by default, which is a
           jarring blue against this palette. */
        .notification-content .summary {
          color: var(--text-color);
          font-weight: 600;
        }

        .notification-content .body {
          color: rgb(166, 173, 200);
        }

        /* DND on: mark it loudly, because a silenced notification produces no
           other feedback at all. */
        .control-center .widget-title > button.dnd,
        .control-center .widget-title > button.dnd:hover {
          color: rgb(243, 139, 168);
          border-color: rgb(243, 139, 168);
        }
      '';
    };
    # ── Locker ──────────────────────────────────────────────────
    # hyprlock, not swaylock. swaylock draws a ring and nothing else -- no
    # password field, no text, no failed-attempt feedback; the ring IS the
    # entire UI (its complete option list is indicator size/thickness/position
    # and font size). That is a deliberate minimalist design, and it is what
    # made the idle lock look like a broken white screen.
    #
    # hyprlock is a general ext-session-lock-v1 client, not a Hyprland-only
    # one: it pulls in no Hyprland daemon (hyprland appears 0 times in its
    # closure) and niri serves the protocol natively
    # (src/handlers/mod.rs:70 delegate_session_lock, src/niri.rs:279
    # session_lock_state).
    #
    # Unlock was proven before the idle ladder was repointed, in a nested niri
    # session (winit backend) so a failure could not strand the real one: a
    # wrong password reached PAM and redrew as "Authentication failed", and the
    # real password unlocked it. Note a `timeout N hyprlock` test proves
    # nothing -- Smithay's `Drop for SessionLocker`
    # (src/wayland/session_lock/mod.rs:195-202) calls `lock.finished()` when the
    # locker dies, so niri unlocks without any authentication happening.
    #
    # What it buys: a real input field with dots, a placeholder, a proper
    # blurred screenshot background, and fractional scaling (it logged
    # "Got fractional scale: 125.0%" on this 1.25-scale panel).
    programs.hyprlock.enable = true;

    # Catppuccin Mocha, matching the waybar/fuzzel palette already in this file
    # (base #1e1e2e, surface0 #313244, text #cdd6f4, blue #89b4fa, overlay0
    # #6c7086).
    #
    # `path = "screenshot"` makes hyprlock grab the screen it is covering and
    # blur it, so the lock screen shows a blurred version of whatever was open
    # instead of a flat colour. blur_passes 3 is the usual "readable but clearly
    # backgrounded" setting; each pass costs GPU time on every frame it
    # re-renders, so this is not a knob to just turn up.
    programs.hyprlock.settings = {
      general = {
        hide_cursor = true;
        # No point requiring auth for the first few seconds: nothing has had
        # time to happen yet. Matches the fade-in.
        grace = 0;
      };

      background = [
        {
          monitor = "";
          path = "screenshot";
          blur_passes = 3;
          blur_size = 8;
          noise = 0.05;
          contrast = 0.9;
          brightness = 0.7;
          vibrancy = 0.2;
        }
      ];

      # The part swaylock does not have at all: a drawn input field with an
      # outlined box, password dots, and a placeholder that vanishes on first
      # keypress.
      input-field = [
        {
          monitor = "";
          size = "280, 52";
          outline_thickness = 2;
          dots_size = 0.25;
          dots_spacing = 0.35;
          dots_center = true;
          rounding = 12;
          fade_on_empty = false;
          outer_color = "rgb(137, 180, 250)";
          inner_color = "rgb(49, 50, 68)";
          font_color = "rgb(205, 214, 244)";
          placeholder_text = ''<span foreground="##6c7086">Password</span>'';
          # Show the failure reason (wrong password, etc.) rather than silently
          # resetting dots, which is the other thing that made swaylock feel
          # like it was ignoring input.
          fail_text = ''<span foreground="##f38ba8">$FAIL</span>'';
          # Reveal the on-screen keyboard layout when Caps Lock is on -- this is
          # the single most common cause of "my password is right but rejected".
          capslock_color = "rgb(249, 226, 175)";
        }
      ];

      # Clock above the field, so the lock screen is not a blank wall.
      label = [
        {
          monitor = "";
          text = "$TIME";
          font_size = 64;
          font_family = "monospace";
          color = "rgb(205, 214, 244)";
          position = "0, 220";
        }
        {
          monitor = "";
          text = ''cmd[update:60000] date +"%A, %d %B"'';
          font_size = 18;
          font_family = "monospace";
          color = "rgb(166, 173, 200)";
          position = "0, 160";
        }
      ];
    };
  };
}
