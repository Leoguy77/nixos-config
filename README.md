# Leon's NixOS Configuration

NixOS hosts declared as an option-based flake — desktops, a laptop, and a
headless mail server. Every reusable piece is a module that does nothing until a
host enables it.

## Hosts

| Host | Role | Notes |
|---|---|---|
| `kirito` | Workstation | 8 cores / 15 GB |
| `surface` | Laptop | KDE Plasma |
| `mail` | Mail server | netcup VPS, 1 GB RAM, encrypted root unlocked over the tailnet — see [hosts/mail/README.md](./hosts/mail/README.md) |

`hosts/asuna/` exists but is intentionally inert (no `default.nix`, no hardware
config); it holds that machine's DNS records until it is migrated to NixOS.

## Build

```bash
sudo nixos-rebuild switch --flake .#surface     # or kirito, mail
home-manager switch --flake .#leoguy77@surface
nix flake update
nix flake check
nix fmt
```

Install or reinstall a host from scratch with the shared deploy script:

```bash
nix develop .# --command scripts/deploy.sh <host> <user@address> [disk]
```

## Structure

```
flake.nix              # inputs, mkHost, devShell, checks, per-host installer ISO
hosts/<name>/          # default.nix + hardware-configuration.nix (+ home.nix, dns.nix)
modules/nixos/         # system modules (option-bearing), auto-imported by scanPaths
modules/home/          # Home Manager: base/ (headless) tui/ (terminal) gui/ (desktop)
modules/disko/         # disk layouts for nixos-anywhere
modules/iso/           # per-host installer ISO
lib/default.nix        # scanPaths, publishDns
vars/default.nix       # username, email, networking, signing keys
secrets/               # sops-encrypted secrets (committed)
scripts/deploy.sh      # install/upgrade any host
docs/                  # module reference, secrets guide, archive
```

Hosts are discovered by iterating `hosts/*/default.nix`, so adding a host means
adding that file — nothing to register.

## What's included

**System** — systemd-boot/EFI, KDE Plasma 6 + SDDM, PipeWire, NetworkManager,
auto-cpufreq. Servers swap the desktop for a hardened baseline:
key-only sshd for the admin account, fail2ban (sshd, recidive, and
per-service jails on mail), sysctl hardening, zram, a remote-unlock sshd in the
initrd, and Tailscale.

**User** — Zsh, git with SSH signing via 1Password, kitty, Firefox, tmux, mise,
lazygit, delta, and the pi coding agent.

**Mail** — declarative postfix + dovecot + rspamd + Roundcube via
nixos-mailserver, with DKIM/DMARC/SPF, DNSSEC validation through a local
recursor, DANE, MTA-STS, autoconfig, and the entire `lsinfra.de` zone managed
from this repo.

## Secrets

sops + sops-nix, decrypted by the machine's SSH host key (system) and a personal
PGP key (user). See [docs/SECRETS.md](./docs/SECRETS.md) — including the host-key
provisioning flow that makes an encrypted-root server possible.

## Documentation

- [docs/MODULES.md](./docs/MODULES.md) — module reference, options, how to add a host or module
- [docs/SECRETS.md](./docs/SECRETS.md) — sops setup and key rotation
- [docs/SIGNED_COMMITS.md](./docs/SIGNED_COMMITS.md) — how commit signing is set up, and what is not enforced
- [hosts/mail/README.md](./hosts/mail/README.md) — the mail server runbook
- [docs/archive/](./docs/archive/) — historical notes, kept for context only

## Troubleshooting

```bash
nix flake check                      # evaluate every host
sudo nixos-rebuild build --flake .#surface   # build without switching
sudo nixos-rebuild switch --rollback
sudo nixos-rebuild list-generations
```

## License

Personal configuration, provided as-is. Use it as inspiration freely.
