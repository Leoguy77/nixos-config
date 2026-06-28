# Leon's NixOS Configuration

A fully modular NixOS configuration using flakes and Home Manager.

## 🚀 Quick Start

### Build System
```bash
sudo nixos-rebuild switch --flake .#surface
```

### Build Home Manager
```bash
home-manager switch --flake .#leoguy77@surface
```

### Update System
```bash
nix flake update
sudo nixos-rebuild switch --flake .#surface
```

## 📁 Structure

```
nixos-config/
├── flake.nix              # Entry point
├── hosts/                 # Host-specific configs
│   └── surface/           # My Surface device
├── modules/               # Reusable modules
│   ├── nixos/             # System modules
│   └── home/              # User modules
└── lib/                   # Shared utilities
```

## 📦 What's Included

### System (NixOS)
- **Boot**: systemd-boot, EFI
- **Desktop**: KDE Plasma 6, SDDM
- **Audio**: PipeWire with ALSA/Pulse/Jack
- **Network**: NetworkManager, SSH
- **Power**: auto-cpufreq
- **Packages**: git, vim, htop, btop, vs-code, and more

### User (Home Manager)
- **Shell**: Zsh with oh-my-zsh, aliases, smart home functions
- **Git**: SSH signing via 1Password
- **Terminal**: Kitty with Catppuccin theme
- **Browser**: Firefox with dark mode
- **Dev Tools**: tmux, mise, lazygit, delta
- **Pi Agent**: LLM agents integration

## 🔧 Customization

See [MODULES.md](./MODULES.md) for detailed module documentation.

### Quick Overrides

Create `hosts/surface/hardware.nix` for system overrides:
```nix
{
  modules.system.hostName = "my-host";
  modules.packages.extraPackages = [ /* packages */ ];
}
```

Create `hosts/surface/home.nix` for user overrides:
```nix
{
  modules.home.desktop.darkMode = false;
}
```

## 📚 Documentation

- [MODULES.md](./MODULES.md) - Module reference and options
- [NixOS Wiki](https://wiki.nixos.org/) - General NixOS help
- [Home Manager Manual](https://nix-community.github.io/home-manager/) - User config

## 🛠️ Troubleshooting

### Check Configuration
```bash
nix flake check
```

### Dry Run Build
```bash
sudo nixos-rebuild build --flake .#surface
```

### Rollback
```bash
sudo nixos-rebuild switch --rollback
```

### View Generations
```bash
sudo nixos-rebuild list-generations
```

## 📝 License

This configuration is personal and provided as-is. Feel free to use as inspiration for your own setup!
