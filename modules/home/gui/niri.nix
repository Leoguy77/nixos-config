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

      # Noctalia's config. A store symlink is enough here, unlike config.kdl:
      # this file holds no values worth iterating on (they are all switches that
      # turn noctalia's own shell off), so a rebuild per change is fine.
      #
      # It belongs in ~/.config/noctalia/ and NOT in ~/.local/state/noctalia/.
      # `noctalia config export --help` defines the order: "every *.toml in the
      # active config dir, then the state-dir settings.toml overrides". The
      # state dir is the shell's own scratch space; this is the layer underneath
      # it.
      "noctalia/noctalia.toml".source = ./niri/noctalia.toml;
    };

    # ── Launcher ──────────────────────────────────────────────────────────
    # fuzzel was running on its built-in defaults, which are Solarized light —
    # background fdf6e3, a cream colour that read as a white box on an
    # otherwise dark desktop. The HM module only writes fuzzel.ini when
    # `settings` is non-empty, which is why there was no config file at all.
    #
    # Keys are the ones in the packaged example, `$out/etc/xdg/fuzzel/fuzzel.ini`
    # (56-72), which lists every option with its default commented out. Colours
    # are 8-digit RRGGBBAA. Catppuccin Mocha, same palette as hyprlock/swaync/
    # wlogout.
    #
    # `dpi-aware = no` is deliberate: on `auto` fuzzel only honours the output's
    # scaling factor when every monitor has scale 1, and this panel runs at
    # 1.25. `no` makes it follow the scale instead, so the text is not tiny.
    programs.fuzzel = {
      enable = true;
      settings = {
        main = {
          font = "Fira Code:size=11";
          prompt = "❯ ";
          dpi-aware = "no";
          lines = 12;
          width = 40;
          horizontal-pad = 24;
          vertical-pad = 16;
          inner-pad = 8;
          layer = "overlay";
        };
        colors = {
          background = "1e1e2ee6";
          text = "cdd6f4ff";
          prompt = "89b4faff";
          input = "cdd6f4ff";
          placeholder = "6c7086ff";
          match = "f9e2afff";
          selection = "313244ff";
          selection-text = "cdd6f4ff";
          selection-match = "f9e2afff";
          counter = "6c7086ff";
          border = "89b4faff";
        };
        border = {
          width = 2;
          radius = 12;
        };
      };
    };

    # ── Session programs ──────────────────────────────────────────────────
    home.packages = with pkgs; [
      swayidle # idle -> lock -> blank, plus lock before suspend
      pavucontrol # full mixer, opened from the bar's volume right-click
      noctalia # the top bar; see niri/noctalia.toml for which roles it owns
      libnotify # notify-send, for testing notifications from a shell
      brightnessctl # the backlight device swayosd-client drives on this box
      playerctl # XF86Audio* media keys from niri's defaults
      # Region screenshot + annotation, on Mod+Shift+S. niri's own screenshot
      # UI (Print) captures but cannot annotate, so these add the markup pass.
      # wl-clipboard, already present, is satty's copy target.
      grim
      slurp
      satty
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

    # ── Bluetooth applet ──────────────────────────────────────────────────
    # `services.blueman` (from modules/nixos/bluetooth.nix) only installs the
    # package and its dbus activation files — blueman ships an XDG autostart
    # .desktop and NOTHING reads it here: niri has no xdg-autostart support
    # (grep -i autostart src/main.rs turns up one comment about the env var and
    # no loader), so the applet would never start. This declares the systemd
    # user unit instead, which the bar's tray module then hosts.
    #
    # Requires=tray.target is in the unit's own definition, so it waits for a
    # status notifier host rather than silently failing to draw.
    services.blueman-applet.enable = true;

    # ── Default applications ──────────────────────────────────────────────
    # Nothing set a default file manager, so the winner was whatever package
    # happened to claim the type. kitty's helper declares `inode/directory`
    # in kitty-open.desktop (to support `kitty +open`), which made double-
    # clicking a folder in any GTK app spawn a terminal listing instead of
    # Thunar. Nothing about that is a conscious choice — kitty's .desktop
    # ships that line regardless of whether kitty is anyone's file manager.
    #
    # `image/*` has the same shape: satty (the screenshot annotator) declares
    # it, so opening a PNG launches the annotation UI. Left alone here because
    # satty does display the image and there is no dedicated viewer installed;
    # if one is added, point image/* at it.
    xdg.mimeApps = {
      enable = true;
      defaultApplications = {
        "inode/directory" = "thunar.desktop";
      };
    };

    # ── Volume / brightness OSD ───────────────────────────────────────────
    # Pressing a media key did the right thing and showed nothing: the default
    # config calls wpctl and brightnessctl directly, and neither draws. This
    # serves the GTK layer-shell bar (declared as a user unit, PartOf the
    # wayland target) and the binds in config.kdl call swayosd-client, which
    # does the action AND reports it. The packaged stylesheet is already
    # theme-derived (alpha(@theme_bg_color, 0.8)), so it follows the dark GTK
    # theme rather than needing a palette restated here.
    services.swayosd.enable = true;

    # ── Cursor theme ──────────────────────────────────────────────────────
    # Nothing installed a cursor theme at all, so niri logged
    # `error loading xcursor col-resize@48: no default icon` on every window
    # resize and fell back to whatever single cursor it could find. The
    # dconf/gtk settings named `breeze_cursors`, a Plasma theme that is not
    # installable on its own (kdePackages.breeze is 1.8 GiB for the icon set).
    #
    # adwaita-icon-theme is ALREADY in both the system and home closures (it
    # comes in with GTK) and ships a full share/icons/Adwaita/cursors tree, so
    # pointing at it adds nothing to download. Only the name had to change:
    # `Adwaita`, not `breeze_cursors`.
    home.pointerCursor = {
      enable = true;
      name = "Adwaita";
      package = pkgs.adwaita-icon-theme;
      size = 24; # matches the gtk settings already on disk
    };

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

    # ── Power menu ────────────────────────────────────────────────────────
    # The default config binds Mod+Shift+E to a bare `quit` with a confirmation
    # dialog. Replacing it with wlogout keeps quit reachable (its logout button
    # is the same `niri msg action quit`) and adds lock, suspend, reboot and
    # shutdown, which had no binding at all.
    #
    # wlogout is GTK3 plus gtk-layer-shell, and niri implements the
    # wlr-layer-shell protocol (src/handlers/layer_shell.rs), so it draws a
    # full-screen layer surface rather than a floating window.
    programs.wlogout = {
      enable = true;

      layout = [
        {
          label = "lock";
          action = "hyprlock";
          text = "Lock";
          keybind = "l";
        }
        {
          label = "logout";
          action = "niri msg action quit";
          text = "Logout";
          keybind = "e";
        }
        {
          label = "suspend";
          action = "systemctl suspend";
          text = "Suspend";
          keybind = "u";
        }
        {
          label = "hibernate";
          action = "systemctl hibernate";
          text = "Hibernate";
          keybind = "h";
        }
        {
          label = "reboot";
          action = "systemctl reboot";
          text = "Reboot";
          keybind = "r";
        }
        {
          label = "shutdown";
          action = "systemctl poweroff";
          text = "Shutdown";
          keybind = "s";
        }
      ];

      # Same Catppuccin Mocha palette as hyprlock/swaync.
      #
      # The icons are the ones the wlogout package ships in its own
      # $out/share/wlogout/icons; upstream's default style.css points at them
      # by absolute store path too, since there is no /usr/share here to find
      # them by name. Written as a Nix string so `pkgs.wlogout` resolves.
      style = ''
        * {
          background: transparent;
          border: none;
          font-family: "Noto Sans", sans-serif;
        }

        window {
          background: rgba(30, 30, 46, 0.88);
        }

        button {
          background: rgba(49, 50, 68, 0.9);
          color: #cdd6f4;
          border-radius: 16px;
          margin: 12px;
          font-size: 18px;
          background-repeat: no-repeat;
          background-position: center 32%;
          background-size: 64px 64px;
          padding-top: 96px;
        }

        button:focus,
        button:hover {
          background-color: rgba(69, 71, 90, 0.95);
          color: #89b4fa;
          outline: 2px solid #89b4fa;
        }

        label {
          font-size: 15px;
          margin-top: 8px;
        }

        ${lib.concatStrings (
          lib.mapAttrsToList
            (name: icon: ''
              #${name} {
                background-image: url("${pkgs.wlogout}/share/wlogout/icons/${icon}.png");
              }
            '')
            {
              lock = "lock";
              logout = "logout";
              suspend = "suspend";
              hibernate = "hibernate";
              reboot = "reboot";
              shutdown = "shutdown";
            }
        )}

        /* Shutdown and reboot are the destructive ones; make them read that
           way before they are clicked, not after. */
        #shutdown label,
        #reboot label {
          color: #f38ba8;
        }
      '';
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
      # Catppuccin Mocha, matching the hyprlock palette: base #1e1e2e,
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

    # Catppuccin Mocha, matching the fuzzel palette already in this file
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
