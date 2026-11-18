# Module Reference

Every reusable part of this configuration is an **option-bearing module**: it
declares `options.modules.<name>`, does nothing until something sets
`.enable = true`, and takes its values from options rather than hardcoding them.
Hosts are thin — they enable modules and supply machine-specific values.

Verify anything here against the live option tree rather than trusting this
page:

```bash
nix eval --json .#nixosConfigurations.kirito.config.modules --apply builtins.attrNames
```

## Layout

```
flake.nix                    # inputs, mkHost, devShell, checks, ISO packages
hosts/<name>/                # one directory per machine
├── default.nix              # imports scanPaths ../../modules/nixos, enables modules
├── hardware-configuration.nix
├── home.nix                 # user overrides (optional; servers omit it)
└── dns.nix                  # this host's records (optional)
lib/default.nix              # scanPaths, publishDns
vars/default.nix             # username, fullName, email, networking, signing keys
modules/
├── nixos/                   # system modules, all option-bearing
├── home/                    # Home Manager: base/ tui/ gui/ + sops.nix
└── iso/                     # per-host installer ISO
profiles/                    # compositions a host opts into, no options of their own
├── {server,desktop,laptop}.nix  # role
├── desktops/                # the DE itself: import exactly one file
└── disk/                    # disko layouts for nixos-anywhere
secrets/secrets.sops.yaml    # encrypted (sops + sops-nix), committed
scripts/deploy.sh            # install/upgrade any host via nixos-anywhere
```

Hosts are discovered automatically: the flake iterates `hosts/*/default.nix`,
so a host is buildable the moment that file exists. A directory **without**
`default.nix` is intentionally inert (see `hosts/asuna/`).

## NixOS modules (`modules/nixos/`)

| File | Option root | Notable sub-options |
|---|---|---|
| `accounts.nix` | `modules.accounts` | `adminKeys`, `mainUser`, `passwordlessSudo` |
| `autocpufreq.nix` | `modules.autocpufreq` | `enable` |
| `backup.nix` | `modules.backup` | `paths`, `exclude`, `repository`, `passwordFile`, `sshKeyFile`, `knownHost`, `timerConfig`, `pruneOpts`, `initialize` |
| `boot.nix` | `modules.boot` | `systemdBoot`, `efi` |
| `dns.nix` | `modules.dns` | `records`, `push.{enable,zone,ignore,variables}` |
| `fail2ban.nix` | `modules.fail2ban` | `enable` |
| `firewall.nix` | `modules.firewall` | `openPorts` |
| `firmware.nix` | `modules.firmware` | `enable` |
| `fonts.nix` | `modules.fonts` | `enable` |
| `initrd-tailscale.nix` | `modules.initrdTailscale` | `port`, `stateMountPoint`, `stateDevice`, `stateFile`, `extraUpFlags` |
| `locale.nix` | `modules.locale` | `germanSubLocales` |
| `login.nix` | `modules.login` | `passwordSecret`, `passwordUser`, `keys` |
| `mail.nix` | `modules.mail` | `hostname`, `webmailHostname`, `domain`, `acmeEmail`, `dnssecValidation`, `accounts.<name>.{passwordFile,hashedPasswordFile,aliases,quota,sieveScript}`, plus read-only `mtaStsPolicy`/`mtaStsId` |
| `networkmanager.nix` | `modules.networkmanager` | `enable` |
| `nix-daemon.nix` | `modules.nix` | `mainUser` |
| `onepassword.nix` | `modules.onepassword` | `polkitOwners` |
| `packages.nix` | `modules.packages` | `extraPackages` |
| `pipewire.nix` | `modules.pipewire` | `enable` |
| `plasma.nix` | `modules.plasma` | `enable` |
| `printing.nix` | `modules.printing` | `enable` |
| `rdp.nix` | `modules.rdp` | `enable` |
| `remote-unlock.nix` | `modules.remoteUnlock` | `authorizedKeys`, `initrdSsh`, `initrdSshPort`, `initrdSshHostKey` |
| `security.nix` | `modules.security` | `enable` |
| `sops.nix` | `modules.sops` | `enable` (default true) |
| `ssh.nix` | `modules.ssh` | `enable` (client + stock sshd) |
| `sshd.nix` | `modules.sshd` | `mainUser` (hardened server sshd) |
| `sysctl.nix` | `modules.sysctl` | `enable` |
| `tailscale.nix` | `modules.tailscale` | `openFirewall` |
| `users.nix` | `modules.users` | `mainUser`, `userShell` |
| `wireguard.nix` | `modules.wireguard` | `address`, `dns`, `dnsSearch`, `dnsPriority` |
| `x11.nix` | `modules.x11` | `enable` |
| `zram.nix` | `modules.zram` | `memoryPercent` |
| `disk` (in `profiles/disk/`) | `modules.disk` | `ephemeralRoot` |
| `desktop` (in `profiles/desktop.nix`) | `modules.desktop` | `backupFileExt`, `homeModule` |

The option table above is a summary. Print the authoritative list for any module
with the two `nix eval` commands at the top of this page.

`ssh.nix` and `sshd.nix` are deliberately separate: `ssh.nix` is the client plus
whatever sshd stock NixOS provides, `sshd.nix` replaces it with the hardened
server policy (key-only, `AllowUsers`, restricted forwarding). They are
different policies, not one feature written twice — don't consolidate them.

`dns.nix` is split deliberately. **Any** module or host may append to
`modules.dns.records` (via `mylib.publishDns`) — that is a registry. Exactly one
host per zone sets `modules.dns.push`, which is the publisher: it renders every
registered record for that zone through `dnscontrol` on rebuild, with `PURGE` on,
so the zone cannot drift from the config. Records for another zone are filtered
out. Values that are secret are passed as dnscontrol `-v` variables at push time
and never enter the store.

## Home Manager modules (`modules/home/`)

Split by where the software can live, not by topic — `base` works over SSH,
`tui` needs a terminal but no display, `gui` needs a desktop session.

| Path | Option root | Sub-options |
|---|---|---|
| `base/core.nix` | `modules.home.core` | `enable`, `username`, `gitUserName`, `gitUserEmail` |
| `base/development.nix` | `modules.home.base.development` | `enable`, `tmux`, `mise`, `onepassword` |
| `tui/tools.nix` | `modules.home.tui` | `enable`, `btop`, `yazi`, `zellij` |
| `gui/desktop.nix` | `modules.home.gui.desktop` | `enable`, `kitty`, `firefox`, `darkMode`, `element`, `spotify` |
| `gui/pi.nix` | `modules.home.gui.pi` | `enable`, `extensions`, `llmAgentsPackage` |
| `sops.nix` | `modules.home.sops` | `enable` |
| `default.nix` | — | imports all of the above unconditionally; each gates itself on `.enable` |

## Adding a host

1. `scripts/new-host.sh <name> --role laptop|desktop|server` scaffolds the three
   files below, or do it by hand:
2. Generate `hosts/newhost/hardware-configuration.nix` (from the installer, or
   `nixos-generate-config`). It must **not** define `fileSystems` or
   `swapDevices` — disko owns those and defining them twice is a hard error.
3. `hosts/newhost/default.nix`:

   ```nix
   { mylib, ... }:
   {
     imports = [
       (mylib.scanPaths ../../modules/nixos)
       ../../profiles/desktop.nix          # or server.nix / laptop.nix
       ../../profiles/desktops/plasma.nix  # exactly one; omit on a server
       ./hardware-configuration.nix
     ];

     networking.hostName = "newhost";
     modules.boot.enable = true;
     # Optional services are per-host opt-ins, never implied by the role:
     # modules.printing.enable = true;

     home-manager.users.leoguy77.imports = [ ../../modules/home ./home.nix ];
   }
   ```

4. Nothing to register — the flake picks up `hosts/*/default.nix` automatically.
5. `nix build .#nixosConfigurations.newhost.config.system.build.toplevel`

A host with an encrypted root also needs a disko layout and an entry in
`scripts/deploy.sh`'s expectations; see `hosts/mail/README.md` for the full
worked example (custom ISO, initrd tailnet unlock, host-key seeding).

## Choosing the desktop environment

`profiles/desktop.nix` is the **role** — everything a graphical machine needs
that is not the desktop environment itself: audio, fonts, locale, NetworkManager,
the nix daemon, users, backup. It deliberately does not pick a DE.

The DE is a swappable file in `profiles/desktops/`, and a host imports exactly
one:

| File | What it turns on |
|---|---|
| `plasma.nix` | `modules.x11` + `modules.plasma` (Plasma 6, X11 + XWayland, SDDM) |
| `niri.nix` | `programs.niri` + `services.xserver.enable` (XWayland only) + SDDM |
| `hyprland.nix` | `programs.hyprland` + SDDM |

Switching DE is one import line. Two details that bite:

- **`services.xserver.enable` is not the same as `modules.x11`.** The former is
  the X server (which is also XWayland); the latter is the full X11 session
  machinery. Niri and Hyprland need the first, not the second.
- **Niri needs `services.xserver.enable` explicitly; Hyprland does not.**
  Hyprland's module sets `xwayland.enable` from `programs.hyprland.xwayland.enable`
  (`nixos/modules/programs/wayland/wayland-session.nix:17`), while `programs.niri`
  has no such wiring.

The three verify as mutually exclusive — build a throwaway host for each and
check `programs.plasma.enable`, `programs.niri.enable`,
`programs.hyprland.enable`, `services.xserver.enable` and
`services.displayManager.defaultSession`.

## Ephemeral root

`profiles/laptop.nix` imports the layout and turns on full disk encryption, but
NOT an ephemeral root. Both are per-host decisions:

```nix
imports = [ ... ../../profiles/state.nix ];
modules.disk.ephemeralRoot = true;
```

With it on, `/` is a tmpfs (8G) and `/var` is rebuilt from `/persist`; `/nix`
and `/home` stay real btrfs subvolumes. `/home` is deliberately NOT ephemeral:
user data is not configuration, and a path list that misses one directory is
silent data loss. `profiles/state.nix` therefore lists only system state whose
loss breaks a boot.

Two things this depends on, both easy to break:

- `scripts/deploy.sh` writes the host key to `/persist/etc/ssh/` as well as
  `/etc/ssh/`. That key is also the sops/age identity; a tmpfs `/` means the
  `/etc` copy is gone after the first reboot and every secret fails to decrypt.
- impermanence's `method = "auto"` binds when the persisted file exists and
  symlinks otherwise. There is no "reconcile" method — it does not exist in
  upstream impermanence at any commit — so the deploy-time seeding is the only
  thing making a fresh install work. Do not remove it on the assumption that
the module handles it.

## Adding a module

```nix
{ config, lib, ... }:
let cfg = config.modules.myfeature;
in
{
  options.modules.myfeature = {
    enable = lib.mkEnableOption "my feature";
    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
    };
  };

  config = lib.mkIf cfg.enable {
    # …
  };
}
```

Then drop it in `modules/nixos/` — `scanPaths` imports it with no registration —
and set `modules.myfeature.enable = true` in the host.

Two conventions worth keeping:

- **`lib.mkDefault` for anything a host may override**, plain assignment for
  anything that is not a policy choice.
- **`lib.mkForce` when the module must win** over another module's value, and
  comment why. Stock nixpkgs modules assign with `mkDefault` often enough that
  forgetting this is a silent no-op rather than an error.

## Checks

```bash
nix flake check                       # evaluates all hosts, runs pre-commit checks
nix develop .# --command pre-commit run --all-files
nix fmt                               # nixfmt-tree
```

The pre-commit set is deadnix (dead code), nixfmt (formatting) and statix
(lint). `statix.toml` disables exactly one rule, `repeated_keys`, because the
repo deliberately groups related options under repeated `modules.x` keys.
