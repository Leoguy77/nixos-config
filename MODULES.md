# NixOS Configuration Structure

This directory contains a modular NixOS configuration using flakes and Home Manager.

## Directory Structure

```
nixos-config/
├── flake.nix                      # Flake entry point with inputs
├── flake.lock                     # Locked flake dependencies
├── configuration.nix              # Main NixOS configuration (imports modules)
├── home.nix                       # Home Manager configuration (imports modules)
├── hardware-configuration.nix     # Hardware config (auto-generated)
├── modules/
│   ├── nixos/                     # NixOS system modules
│   │   ├── boot.nix               # Bootloader, kernel, hardware
│   │   ├── system.nix             # Core system, nix, networking, locale, fonts
│   │   ├── services.nix           # Display, audio, printing, SSH, power
│   │   ├── packages.nix           # System-wide packages
│   │   ├── users.nix              # User accounts and shells
│   │   └── security.nix           # Security settings (sudo, rtkit)
│   └── home/                      # Home Manager modules
│       ├── core.nix               # Git, GPG, Zsh, direnv, basic packages
│       ├── development.nix        # Dev tools (tmux, mise, 1password)
│       ├── desktop.nix            # Desktop apps (kitty, firefox, dark mode)
│       └── pi.nix                 # Pi agent configuration
└── README.md                      # This file
```

## Module Descriptions

### NixOS Modules (`modules/nixos/`)

| Module | Purpose |
|--------|---------|
| `boot.nix` | Bootloader (systemd-boot), kernel modules, hardware microcode |
| `system.nix` | Nix GC, networking, hostname, timezone, locale, fonts |
| `services.nix` | X11, KDE Plasma, Pipewire, printing, SSH, auto-cpufreq |
| `packages.nix` | System-wide packages (git, vim, htop, vscode, etc.) |
| `users.nix` | User accounts, groups, default programs |
| `security.nix` | Sudo, rtkit, pulseaudio settings |

### Home Manager Modules (`modules/home/`)

| Module | Purpose |
|--------|---------|
| `core.nix` | Git config, GPG, Zsh with oh-my-zsh, direnv, CLI tools |
| `development.nix` | Tmux, mise (version manager), 1Password SSH agent |
| `desktop.nix` | Kitty terminal, Firefox, dark mode preference |
| `pi.nix` | Pi agent packages and extensions |

## Usage

### Rebuild system
```bash
sudo nixos-rebuild switch --flake .#surface
```

### Rebuild with hardware config regeneration
```bash
sudo nixos-rebuild switch --flake .#surface --recreate-lock-file
```

### Update flake inputs
```bash
nix flake update
```

### Run Home Manager standalone
```bash
home-manager switch --flake .#leoguy77
```

## Adding New Modules

1. Create a new `.nix` file in `modules/nixos/` or `modules/home/`
2. Add it to the `imports` list in `configuration.nix` or `home.nix`
3. Rebuild to test

Example module:
```nix
{ config, pkgs, lib, ... }:

{
  # Your configuration here
}
```

## Customization

- **Add packages**: Edit `modules/nixos/packages.nix` (system) or `modules/home/core.nix` (user)
- **Change services**: Edit `modules/nixos/services.nix`
- **Modify shell**: Edit `modules/home/core.nix` (aliases, git, gpg)
- **Pi configuration**: Edit `modules/home/pi.nix`
