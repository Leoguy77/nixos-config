# Module Reference

Every reusable part of this configuration is an **option-bearing module**: it
declares `options.modules.<name>`, does nothing until something sets
`.enable = true`, and takes its values from options rather than hardcoding them.
Hosts are thin — they enable modules and supply machine-specific values.

Verify anything here against the live option tree rather than trusting this
page:

```bash
nix eval --json .#nixosConfigurations.surface.config.modules --apply builtins.attrNames
nix eval --json .#nixosConfigurations.surface.config.modules.server --apply builtins.attrNames
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
├── disko/                   # disk layouts for nixos-anywhere
└── iso/                     # per-host installer ISO
secrets/secrets.sops.yaml    # encrypted (sops + sops-nix), committed
scripts/deploy.sh            # install/upgrade any host via nixos-anywhere
```

Hosts are discovered automatically: the flake iterates `hosts/*/default.nix`,
so a host is buildable the moment that file exists. A directory **without**
`default.nix` is intentionally inert (see `hosts/asuna/`).

## NixOS modules (`modules/nixos/`)

| File | Option root | Notable sub-options |
|---|---|---|
| `server.nix` | `modules.server` | `enable`, `adminKeys`, `mainUser`, `initrdSsh`, `initrdSshPort`, `initrdSshHostKey`, `zramPercent` |
| `boot.nix` | `modules.boot` | `enable`, `systemdBoot`, `efi` |
| `system.nix` | `modules.system` | `enable`, `hostName`, `timeZone`, `locale`, `keymap` |
| `services.nix` | `modules.services` | `enable`, `plasma`, `pipewire`, `printing`, `ssh`, `rdp`, `autoCpufreq`, `tailscale` |
| `packages.nix` | `modules.packages` | `enable`, `extraPackages` |
| `users.nix` | `modules.users` | `enable`, `mainUser`, `userShell` |
| `security.nix` | `modules.security` | `enable`, `sudo` |
| `onepassword.nix` | `modules.onepassword` | `enable`, `polkitOwners` |
| `sops.nix` | `modules.sops` | `enable` |
| `wireguard.nix` | `modules.wireguard` | `enable`, `address`, `dns`, `dnsSearch`, `dnsPriority` |
| `initrd-tailscale.nix` | `modules.initrdTailscale` | `enable`, `port`, `stateMountPoint`, `stateDevice`, `stateFile`, `extraUpFlags` |
| `dns.nix` | `modules.dns` | `records`, `push.{enable,zone,ignore,variables}` |
| `mail.nix` | `modules.mail` | `enable`, `hostname`, `webmailHostname`, `domain`, `acmeEmail`, `dnssecValidation`, `accounts.<name>.{passwordFile,hashedPasswordFile,aliases,quota,sieveScript}`, plus read-only `mtaStsPolicy`/`mtaStsId` |
| `backup.nix` | `modules.backup` | `enable`, `paths`, `exclude`, `repository`, `passwordFile`, `timerConfig`, `pruneOpts`, `initialize` |

The option table above is a summary. Print the authoritative list for any module
with the two `nix eval` commands at the top of this page.

`server.nix` is the one that changes a host's shape: it turns off the desktop,
enables a key-only sshd with a strict settings set, adds fail2ban (sshd,
recidive), zram, kernel/sysctl hardening, and a remote-unlock sshd in the initrd
plus `modules.initrdTailscale`, which rebinds that sshd to the tailnet address
so LUKS can be unlocked without a console.

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

1. `mkdir -p hosts/newhost`
2. Generate `hosts/newhost/hardware-configuration.nix` (from the installer, or
   `nixos-generate-config`).
3. `hosts/newhost/default.nix`:

   ```nix
   { mylib, ... }:
   {
     imports = mylib.scanPaths ../../modules/nixos ++ [ ./hardware-configuration.nix ];

     modules.system.hostName = "newhost";
     modules.boot.enable = true;
     # Desktop host? enable modules.services.plasma etc.
     # Server host? modules.server.enable = true; modules.server.adminKeys = [ … ];

     home-manager.users.leoguy77.imports = [ ../../modules/home ./home.nix ];
   }
   ```

4. Nothing to register — the flake picks up `hosts/*/default.nix` automatically.
5. `nix build .#nixosConfigurations.newhost.config.system.build.toplevel`

A host with an encrypted root also needs a disko layout and an entry in
`scripts/deploy.sh`'s expectations; see `hosts/mail/README.md` for the full
worked example (custom ISO, initrd tailnet unlock, host-key seeding).

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
