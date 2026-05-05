# NixOS Configuration

A modular, flake-based NixOS configuration for the Surface laptop.

## Structure

```
~/dotfiles/nixos-config/
├── flake.nix              # Main flake entry point with inputs
├── configuration.nix      # Main config that imports all modules
├── home.nix               # Home Manager user configuration
├── hardware-configuration.nix  # Auto-generated hardware config (copy from /etc/nixos)
└── modules/
    ├── system.nix         # System settings (boot, nix, networking, fonts)
    ├── services.nix       # System services (desktop, audio, ssh, etc.)
    ├── packages.nix       # System-wide packages
    └── users.nix          # User accounts and programs
```

## Quick Start

### 1. Copy hardware configuration
```bash
sudo cp /etc/nixos/hardware-configuration.nix ~/dotfiles/nixos-config/
```

### 2. Initialize git repository
```bash
cd ~/dotfiles
git init
git add nixos/
git commit -m "Initial NixOS configuration"
```

### 3. Test the configuration
```bash
cd ~/dotfiles/nixos-config
nixos-rebuild build --flake .#surface
```

### 4. Apply the configuration
```bash
sudo nixos-rebuild switch --flake .#surface
```

## Git Workflow

### Recommended `.gitignore` for nixos/
```
# Auto-generated files
hardware-configuration.nix
flake.lock
```

### Push to remote
```bash
# Add your remote (GitHub, GitLab, etc.)
git remote add origin git@github.com:yourusername/dotfiles.git

# Push
git push -u origin main
```

### Pull on another machine
```bash
git clone git@github.com:yourusername/dotfiles.git ~/dotfiles
cd ~/dotfiles/nixos-config
sudo nixos-rebuild switch --flake .#surface
```

## Installation (Fresh Install or Migration)

### Option A: Symlink (Recommended)
```bash
# Backup existing config
sudo mv /etc/nixos /etc/nixos.backup

# Create symlink
sudo ln -s ~/dotfiles/nixos-config /etc/nixos

# Rebuild
sudo nixos-rebuild switch --flake .#surface
```

### Option B: Copy (If symlink causes issues)
```bash
sudo cp -r ~/dotfiles/nixos-config/* /etc/nixos/
sudo nixos-rebuild switch --flake /etc/nixos#surface
```

## Key Features

### System
- ✅ Automatic Nix garbage collection (weekly, keep 14 days)
- ✅ Store optimization enabled
- ✅ Firewall enabled (SSH allowed)
- ✅ Intel microcode updates

### Desktop
- ✅ KDE Plasma 6
- ✅ PipeWire audio
- ✅ SDDM display manager
- ✅ German keyboard layout

### Power Management
- ✅ auto-cpufreq for dynamic CPU frequency scaling
- ✅ Optimized for laptop battery life

### User Environment
- ✅ Zsh with Oh My Zsh (agnoster theme)
- ✅ Kitty terminal with Catppuccin theme
- ✅ Tmux with custom prefix (Ctrl+a)
- ✅ direnv for project environments
- ✅ Modern CLI tools (eza, bat, fzf, zoxide, etc.)

### Development
- ✅ Git with LFS
- ✅ Python, Node.js, GCC
- ✅ VSCode (FHS version)
- ✅ Common utilities (jq, ripgrep, fd, etc.)

### Security
- ✅ SSH with key-only authentication
- ✅ Sudo requires password
- ✅ 1Password integration

## Customization

### Add your Git info
Edit `home.nix` and update:
```nix
programs.git = {
  userName = "Your Name";
  userEmail = "your@email.com";
  # ...
};
```

### Add SSH keys
```bash
mkdir -p ~/.ssh
# Copy or generate your SSH keys
```

### Add more packages
- System-wide: Edit `modules/packages.nix`
- User-specific: Edit `home.nix` under `home.packages`

### Enable/disable services
Edit `modules/services.nix` to add or remove services.

## Useful Commands

```bash
# Rebuild configuration
cd ~/dotfiles/nixos-config
sudo nixos-rebuild switch --flake .#surface

# Test configuration without applying
sudo nixos-rebuild build --flake .#surface

# Update flake inputs
sudo nixos-rebuild switch --flake .#surface --update-inputs

# Garbage collect old generations
sudo nix-collect-garbage --delete-older-than 14d

# List available generations
sudo nixos-rebuild list-generations

# Check flake for errors
nix flake check
```

## Troubleshooting

### Boot issues
Select previous generation from systemd-boot menu.

### Rollback
```bash
sudo nixos-rebuild switch --rollback
```

### Flake lock issues
```bash
nix flake update
```

### Permission issues with symlink
Make sure your user can read the files:
```bash
chmod -R u+r ~/dotfiles/nixos-config
```

## Tips

1. **Commit often**: Small commits make it easier to track changes and rollback
2. **Use branches**: Test experimental changes on a branch before merging
3. **Keep hardware-configuration.nix out of git**: It's machine-specific and auto-generated
4. **Backup flake.lock**: Actually, keep it in git for reproducible builds, but update periodically
